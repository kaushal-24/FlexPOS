import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

type JsonObject = Record<string, unknown>;

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

function recipients(value: unknown): string[] {
  if (typeof value !== "string") return [];
  return value
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(item));
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    "\"": "&quot;",
  }[character] ?? character));
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "POST required" });
  const body = asObject(await request.json().catch(() => null));
  const businessId = text(body?.business_id);
  if (!businessId) return json(400, { error: "business_id is required" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("STOCK_ALERT_FROM_EMAIL");
  if (!supabaseUrl || !anonKey) return json(500, { error: "Supabase runtime is not configured" });

  const authHeader = request.headers.get("Authorization") ?? "";
  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: business, error: businessError } = await client
    .from("businesses")
    .select("id,name,stock_alert_email_enabled,stock_alert_email_recipients,stock_alert_last_email_at")
    .eq("id", businessId)
    .single();
  if (businessError || !business) return json(403, { error: "Business is not accessible" });
  if (!business.stock_alert_email_enabled) return json(400, { error: "Email notifications are disabled" });
  const to = recipients(business.stock_alert_email_recipients);
  if (!to.length) return json(400, { error: "No valid notification recipients are configured" });
  if (!resendKey || !fromEmail) {
    return json(503, { error: "Configure RESEND_API_KEY and STOCK_ALERT_FROM_EMAIL in Supabase secrets" });
  }

  const lastSent = business.stock_alert_last_email_at
    ? Date.parse(String(business.stock_alert_last_email_at))
    : 0;
  if (lastSent > Date.now() - 60 * 60 * 1000) {
    return json(429, { error: "A stock alert email was already sent in the last hour" });
  }

  const { data: notifications, error: notificationError } = await client.rpc(
    "get_inventory_stock_alert_notifications",
    { target_business_id: businessId },
  );
  if (notificationError) return json(500, { error: notificationError.message });
  const active = Array.isArray(notifications)
    ? notifications.filter((item) => item && item.status === "open")
    : [];
  if (!active.length) return json(200, { sent: false, reason: "no_active_alerts" });

  const rows = active.slice(0, 50).map((item) => {
    const product = text(item.product_name) || "Product";
    const warehouse = text(item.warehouse_name) || "Warehouse";
    const available = text(item.available_quantity);
    const target = text(item.target_stock);
    return `<li><strong>${escapeHtml(product)}</strong> · ${escapeHtml(warehouse)}: ${escapeHtml(available)} available (target ${escapeHtml(target)})</li>`;
  }).join("");
  const html = `<h2>${escapeHtml(text(business.name))} low-stock alerts</h2><p>${active.length} active alert(s) require attention.</p><ul>${rows}</ul>`;
  const emailResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: fromEmail, to, subject: `${text(business.name)} low-stock alerts`, html }),
  });
  if (!emailResponse.ok) {
    const errorText = await emailResponse.text();
    return json(502, { error: `Email provider rejected the request: ${errorText.slice(0, 240)}` });
  }
  await client
    .from("businesses")
    .update({ stock_alert_last_email_at: new Date().toISOString() })
    .eq("id", businessId);
  return json(200, { sent: true, count: active.length });
});
