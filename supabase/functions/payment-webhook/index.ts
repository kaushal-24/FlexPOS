import { createClient } from "npm:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;
type PaymentStatus = "pending" | "settled" | "failed";

const PROVIDER = "razorpay_upi";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EVENT_ID = /^[A-Za-z0-9._:-]{4,200}$/;

function json(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function asObject(value: unknown): JsonObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function hexToBytes(value: string): Uint8Array | null {
  if (!/^[0-9a-f]{64}$/i.test(value)) return null;
  const bytes = new Uint8Array(32);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

async function verifySignature(body: string, signature: string, secret: string): Promise<boolean> {
  const supplied = hexToBytes(signature.trim());
  if (!supplied) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)),
  );
  return constantTimeEqual(supplied, expected);
}

async function sha256(body: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body)));
}

function notesValue(notes: unknown, key: string): string | null {
  const object = asObject(notes);
  if (object) {
    const value = object[key];
    return typeof value === "string" ? value.trim() : null;
  }
  if (Array.isArray(notes)) {
    for (const entry of notes) {
      const item = asObject(entry);
      if (!item) continue;
      const value = item[key];
      if (typeof value === "string" && value.trim()) return value.trim();
    }
  }
  return null;
}

function paymentEntity(payload: JsonObject): JsonObject | null {
  const outer = asObject(payload.payload);
  const payment = outer ? asObject(outer.payment) : null;
  return payment ? asObject(payment.entity) : null;
}

function statusForEvent(event: string): PaymentStatus | null {
  switch (event) {
    case "payment.captured":
    case "order.paid":
      return "settled";
    case "payment.failed":
      return "failed";
    case "payment.authorized":
    case "payment.pending":
      return "pending";
    default:
      return null;
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "POST is required" });

  const provider = (request.headers.get("x-flexpos-provider") ??
      new URL(request.url).searchParams.get("provider") ??
      PROVIDER).trim().toLowerCase();
  if (provider !== PROVIDER) return json(422, { error: "Unsupported payment provider" });

  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  if (!secret) return json(503, { error: "Razorpay webhook secret is not configured" });

  const rawBody = await request.text();
  if (rawBody.length === 0 || rawBody.length > 1_000_000) {
    return json(400, { error: "Webhook body is empty or too large" });
  }
  const signature = request.headers.get("x-razorpay-signature");
  if (!signature || !(await verifySignature(rawBody, signature, secret))) {
    return json(401, { error: "Invalid webhook signature" });
  }

  let payload: JsonObject;
  try {
    payload = JSON.parse(rawBody) as JsonObject;
  } catch {
    return json(400, { error: "Webhook body must be valid JSON" });
  }
  const event = typeof payload.event === "string" ? payload.event.trim() : "";
  const status = statusForEvent(event);
  if (!status) return json(422, { error: "Unsupported Razorpay event" });

  const eventId = (request.headers.get("x-razorpay-event-id") ??
      (typeof payload.id === "string" ? payload.id : "")).trim();
  if (!EVENT_ID.test(eventId)) return json(400, { error: "A valid Razorpay event id is required" });

  const entity = paymentEntity(payload);
  if (!entity) return json(400, { error: "Payment entity is missing" });
  const providerMethod = typeof entity.method === "string"
    ? entity.method.trim().toLowerCase()
    : "";
  if (!providerMethod) {
    return json(422, { error: "Razorpay payment method is missing" });
  }
  const targetPaymentId = notesValue(entity.notes, "flexpos_payment_id") ??
      notesValue(entity.notes, "payment_id");
  if (!targetPaymentId || !UUID.test(targetPaymentId)) {
    return json(422, { error: "Razorpay notes must include a FlexPOS payment id" });
  }

  const amountPaise = typeof entity.amount === "number" ? entity.amount : Number(entity.amount);
  const amount = Number.isFinite(amountPaise) && amountPaise > 0 ? amountPaise / 100 : NaN;
  const currency = typeof entity.currency === "string" ? entity.currency.trim().toUpperCase() : "";
  const reference = typeof entity.id === "string" ? entity.id.trim() : "";
  if (!Number.isFinite(amount) || !/^[A-Z]{3}$/.test(currency) || !reference) {
    return json(400, { error: "Payment amount, currency, and reference are required" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SECRET_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(503, { error: "Supabase service credentials are not configured" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await supabase.rpc("record_provider_payment_verification", {
    target_payment_id: targetPaymentId,
    provider_name: PROVIDER,
    provider_event_id: eventId,
    provider_payment_reference: reference,
    provider_status: status,
    provider_amount: amount,
    provider_currency_code: currency,
    payload_sha256: await sha256(rawBody),
  });
  if (error) return json(422, { error: error.message });
  return json(200, {
    provider: PROVIDER,
    provider_method: providerMethod,
    event_id: eventId,
    result: data,
  });
});
