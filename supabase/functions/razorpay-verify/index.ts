import { createClient } from "npm:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HEX_64 = /^[0-9a-f]{64}$/i;

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "no-store",
  "content-type": "application/json",
};

function json(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function asObject(value: unknown): JsonObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function basicAuth(keyId: string, keySecret: string): string {
  return `Basic ${btoa(`${keyId}:${keySecret}`)}`;
}

async function razorpayRequest(
  keyId: string,
  keySecret: string,
  path: string,
): Promise<{ response: Response; body: JsonObject }> {
  const response = await fetch(`https://api.razorpay.com/v1/${path}`, {
    headers: {
      authorization: basicAuth(keyId, keySecret),
      "content-type": "application/json",
    },
  });
  let body: JsonObject = {};
  try {
    body = asObject(await response.json()) ?? {};
  } catch {
    body = {};
  }
  return { response, body };
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function hmacHex(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
}

async function sha256(body: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body)));
}

function constantTimeEqual(left: string, right: string): boolean {
  if (!HEX_64.test(left) || !HEX_64.test(right)) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.toLowerCase().charCodeAt(index) ^ right.toLowerCase().charCodeAt(index);
  }
  return difference === 0;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "POST is required" });

  const authorization = request.headers.get("authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SECRET_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "Authentication required" });
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) return json(503, { error: "Supabase runtime is not configured" });
  if (!razorpayKeyId || !razorpayKeySecret) {
    return json(503, { error: "Razorpay test credentials are not configured" });
  }

  const rawBody = await request.text();
  let body: JsonObject;
  try {
    body = asObject(JSON.parse(rawBody)) ?? {};
  } catch {
    return json(400, { error: "Request body must be valid JSON" });
  }
  const paymentId = stringValue(body.payment_id);
  const orderId = stringValue(body.razorpay_order_id);
  const razorpayPaymentId = stringValue(body.razorpay_payment_id);
  const signature = stringValue(body.razorpay_signature).toLowerCase();
  if (!UUID.test(paymentId) || !/^order_[A-Za-z0-9]+$/.test(orderId) ||
      !/^pay_[A-Za-z0-9]+$/.test(razorpayPaymentId) || !HEX_64.test(signature)) {
    return json(400, { error: "Invalid Razorpay verification payload" });
  }

  const expectedSignature = await hmacHex(`${orderId}|${razorpayPaymentId}`, razorpayKeySecret);
  if (!constantTimeEqual(signature, expectedSignature)) {
    return json(401, { error: "Invalid Razorpay payment signature" });
  }

  const supabase = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json(401, { error: "Authentication required" });
  const { data: payment, error: paymentError } = await supabase
    .from("payments")
    .select("id,business_id,sale_id,payment_method,status,amount,provider")
    .eq("id", paymentId)
    .maybeSingle();
  if (paymentError || !payment) return json(404, { error: "Payment not found or not accessible" });
  if (payment.status !== "pending") return json(409, { error: "Only pending payments can be verified" });
  if (payment.payment_method !== "upi" || payment.provider !== "razorpay_upi") {
    return json(422, { error: "This payment is not a Razorpay checkout payment" });
  }
  const { data: sale, error: saleError } = await supabase
    .from("sales")
    .select("id,business_id,currency_code")
    .eq("id", payment.sale_id)
    .eq("business_id", payment.business_id)
    .maybeSingle();
  if (saleError || !sale) return json(404, { error: "Sale not found or not accessible" });

  const orderResult = await razorpayRequest(razorpayKeyId, razorpayKeySecret, `orders/${orderId}`);
  if (!orderResult.response.ok) return json(502, { error: "Razorpay order could not be verified" });
  const order = orderResult.body;
  const orderNotes = asObject(order.notes);
  const expectedPaymentId = stringValue(orderNotes?.flexpos_payment_id);
  if (expectedPaymentId !== payment.id || Number(order.amount) !== Math.round(Number(payment.amount) * 100) ||
      stringValue(order.currency).toUpperCase() !== sale.currency_code) {
    return json(422, { error: "Razorpay order does not match this FlexPOS payment" });
  }

  const paymentResult = await razorpayRequest(
    razorpayKeyId,
    razorpayKeySecret,
    `payments/${razorpayPaymentId}`,
  );
  if (!paymentResult.response.ok) return json(502, { error: "Razorpay payment could not be verified" });
  const providerPayment = paymentResult.body;
  if (stringValue(providerPayment.order_id) !== orderId ||
      Number(providerPayment.amount) !== Math.round(Number(payment.amount) * 100) ||
      stringValue(providerPayment.currency).toUpperCase() !== sale.currency_code) {
    return json(422, { error: "Razorpay payment does not match this FlexPOS payment" });
  }
  const providerStatus = stringValue(providerPayment.status).toLowerCase();
  if (providerStatus !== "captured") {
    return json(409, { error: `Razorpay payment is ${providerStatus || "not captured"}` });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: verification, error: verificationError } = await serviceClient.rpc(
    "record_provider_payment_verification",
    {
      target_payment_id: payment.id,
      provider_name: "razorpay_upi",
      provider_event_id: razorpayPaymentId,
      provider_payment_reference: razorpayPaymentId,
      provider_status: "settled",
      provider_amount: Number(payment.amount),
      provider_currency_code: sale.currency_code,
      payload_sha256: await sha256(rawBody),
    },
  );
  if (verificationError) return json(422, { error: verificationError.message });
  return json(200, {
    provider: "razorpay_upi",
    payment_id: payment.id,
    razorpay_order_id: orderId,
    razorpay_payment_id: razorpayPaymentId,
    result: verification,
  });
});
