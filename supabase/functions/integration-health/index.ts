import { createClient } from "npm:@supabase/supabase-js@2";

const PROVIDERS = new Set(["sms", "whatsapp", "payment_gateway", "tax_service", "ai"]);
const STATUSES = new Set(["not_configured", "configured", "verifying", "verified", "disabled", "error"]);
const SECRET_KEY = /(secret|password|token|api[_-]?key|private[_-]?key|credential)/i;
const SECRET_REF = /^(vault|secret|kms):\/\/[A-Za-z0-9._:/-]+$/;

type JsonObject = Record<string, unknown>;

function json(status: number, body: JsonObject): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function containsSecretKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsSecretKey);
  if (value === null || typeof value !== "object") return false;
  return Object.entries(value as JsonObject).some(([key, child]) => SECRET_KEY.test(key) || containsSecretKey(child));
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json(405, { error: "POST is required" });

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "Authentication required" });

  let body: JsonObject;
  try {
    body = await request.json() as JsonObject;
  } catch {
    return json(400, { error: "Request body must be valid JSON" });
  }

  const businessId = typeof body.business_id === "string" ? body.business_id.trim() : "";
  const providerCode = typeof body.provider_code === "string" ? body.provider_code.trim() : "";
  const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
  const status = typeof body.status === "string" ? body.status.trim() : "";
  const secretRef = typeof body.secret_ref === "string" ? body.secret_ref.trim() : null;
  const config = body.config;
  const lastError = typeof body.last_error === "string" ? body.last_error.trim() : null;

  if (!businessId || !providerCode || !displayName || !STATUSES.has(status) || !PROVIDERS.has(providerCode)) {
    return json(400, { error: "business_id, provider_code, display_name, and a valid status are required" });
  }
  if (displayName.length < 2 || displayName.length > 120) {
    return json(400, { error: "display_name must be between 2 and 120 characters" });
  }
  if (config === null || typeof config !== "object" || Array.isArray(config)) {
    return json(400, { error: "config must be a JSON object" });
  }
  if (containsSecretKey(config)) {
    return json(400, { error: "Provider secrets must be stored in Supabase secrets and referenced by secret_ref" });
  }
  if (secretRef !== null && !SECRET_REF.test(secretRef)) {
    return json(400, { error: "secret_ref must use vault://, secret://, or kms://" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!supabaseUrl || !publishableKey) return json(500, { error: "Supabase runtime is not configured" });

  const supabase = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await supabase.rpc("upsert_integration_connection", {
    target_business_id: businessId,
    target_provider_code: providerCode,
    target_display_name: displayName,
    target_status: status,
    target_secret_ref: secretRef,
    target_config: config,
    target_last_error: lastError || null,
  });

  if (error) return json(400, { error: error.message });
  return json(200, { id: data, status: "persisted" });
});
