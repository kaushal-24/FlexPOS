import { createClient } from "npm:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
  init: RequestInit = {},
): Promise<{ response: Response; body: JsonObject }> {
  const response = await fetch(`https://api.razorpay.com/v1/${path}`, {
    ...init,
    headers: {
      authorization: basicAuth(keyId, keySecret),
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
  let body: JsonObject = {};
  try {
    const parsed = await response.json();
    body = asObject(parsed) ?? {};
  } catch {
    body = {};
  }
  return { response, body };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "POST is required" });

  const authorization = request.headers.get("authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID");
  const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "Authentication required" });
  if (!supabaseUrl || !publishableKey) return json(503, { error: "Supabase runtime is not configured" });
  if (!razorpayKeyId || !razorpayKeySecret) {
    return json(503, { error: "Razorpay test credentials are not configured" });
  }

  let body: JsonObject;
  try {
    body = asObject(await request.json()) ?? {};
  } catch {
    return json(400, { error: "Request body must be valid JSON" });
  }
  const paymentId = stringValue(body.payment_id);
  if (!UUID.test(paymentId)) return json(400, { error: "A valid payment_id is required" });

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
  if (payment.status !== "pending") return json(409, { error: "Only pending payments can open Razorpay Checkout" });
  if (payment.payment_method !== "upi" || payment.provider !== "razorpay_upi") {
    return json(422, { error: "This payment is not a Razorpay checkout payment" });
  }

  const { data: sale, error: saleError } = await supabase
    .from("sales")
    .select("id,business_id,invoice_number,currency_code,grand_total")
    .eq("id", payment.sale_id)
    .eq("business_id", payment.business_id)
    .maybeSingle();
  if (saleError || !sale) return json(404, { error: "Sale not found or not accessible" });
  if (sale.currency_code !== "INR") return json(422, { error: "Razorpay Checkout currently supports INR sales only" });

  const amount = Number(payment.amount);
  const amountPaise = Math.round(amount * 100);
  if (!Number.isSafeInteger(amountPaise) || amountPaise <= 0) {
    return json(422, { error: "Payment amount is invalid" });
  }
  const invoiceNumber = stringValue(sale.invoice_number) || payment.sale_id;
  const receipt = `flexpos_${invoiceNumber}`.slice(0, 40);
  const orderResponse = await razorpayRequest(razorpayKeyId, razorpayKeySecret, "orders", {
    method: "POST",
    body: JSON.stringify({
      amount: amountPaise,
      currency: sale.currency_code,
      receipt,
      notes: {
        flexpos_payment_id: payment.id,
        flexpos_sale_id: payment.sale_id,
        flexpos_business_id: payment.business_id,
      },
    }),
  });
  if (!orderResponse.response.ok) {
    const description = stringValue(asObject(orderResponse.body.error)?.description);
    return json(502, { error: description || "Razorpay could not create the order" });
  }
  const orderId = stringValue(orderResponse.body.id);
  if (!orderId) return json(502, { error: "Razorpay returned an invalid order" });
  return json(200, {
    key_id: razorpayKeyId,
    order_id: orderId,
    payment_id: payment.id,
    amount: amountPaise,
    currency: sale.currency_code,
    receipt,
    invoice_number: invoiceNumber,
  });
});
