import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

type Json = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "no-store",
};

function json(status: number, body: Json): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function uuid(value: unknown, field: string): string {
  const candidate = text(value);
  if (!UUID.test(candidate)) throw new Error(`${field} must be a valid UUID`);
  return candidate;
}

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
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

function asObject(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

type AuthContext = {
  user: User;
  userClient: SupabaseClient;
  adminClient: SupabaseClient;
};

async function authContext(request: Request): Promise<AuthContext> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) throw new Error("Authentication required");
  const url = env("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!publishableKey) throw new Error("Supabase publishable key is not configured");
  const userClient = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new Error("Authentication required");
  const adminClient = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  return { user: data.user, userClient, adminClient };
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((item) => item.toString(16).padStart(2, "0")).join("");
}

function buildRedirectUrl(value: string, token: string, email: string): string {
  const redirect = new URL(value);
  if (!/^https?:$/.test(redirect.protocol)) throw new Error("redirect_to must be an http or https URL");
  const hashPath = redirect.hash;
  if (hashPath.startsWith("#/")) {
    const separator = hashPath.includes("?") ? "&" : "?";
    redirect.hash = `${hashPath}${separator}token=${encodeURIComponent(token)}&email=${encodeURIComponent(email)}`;
  } else {
    redirect.searchParams.set("token", token);
    redirect.searchParams.set("email", email);
  }
  return redirect.toString();
}

async function sendWithResend(
  apiKey: string,
  from: string,
  email: string,
  businessName: string,
  roleName: string,
  token: string,
  acceptUrl: string,
  expiresAt: string,
): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: `You're invited to ${businessName} on FlexPOS`,
      html: `<h2>You're invited to ${escapeHtml(businessName)}</h2>
        <p>You have been invited as <strong>${escapeHtml(roleName)}</strong>.</p>
        <p><a href="${escapeHtml(acceptUrl)}">Accept the invitation</a></p>
        <p>Invitation code: <strong>${escapeHtml(token)}</strong></p>
        <p>This invitation expires on ${escapeHtml(expiresAt)}.</p>`,
    }),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Email provider rejected the request: ${body.slice(0, 240)}`);
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "POST is required" });
  try {
    const ctx = await authContext(request);
    const body = asObject(await request.json().catch(() => null));
    const businessId = uuid(body.business_id, "business_id");
    const invitationId = uuid(body.invitation_id, "invitation_id");
    const token = text(body.token);
    const redirectTo = text(body.redirect_to);
    if (token.length < 20) throw new Error("Invitation token is invalid");
    if (!redirectTo) throw new Error("redirect_to is required");

    // Read through the caller's RLS session first. This proves the caller can
    // see/manage this invitation before the service-role client is used.
    const { data: visibleInvitation, error: visibleError } = await ctx.userClient
      .from("business_invitations")
      .select("id,business_id,email,status,expires_at,token_hash")
      .eq("id", invitationId)
      .eq("business_id", businessId)
      .maybeSingle();
    if (visibleError) throw visibleError;
    if (!visibleInvitation) throw new Error("Invitation is not accessible");
    if (visibleInvitation.status !== "pending") throw new Error("Invitation is no longer active");
    if (Date.parse(String(visibleInvitation.expires_at)) <= Date.now()) throw new Error("Invitation has expired");
    if ((await sha256Hex(token)) !== text(visibleInvitation.token_hash)) throw new Error("Invitation token is invalid");
    const email = text(visibleInvitation.email).toLowerCase();
    if (!EMAIL.test(email)) throw new Error("Invitation email is invalid");

    const { data: invitation, error: invitationError } = await ctx.userClient
      .from("business_invitations")
      .select("email,expires_at, businesses!inner(name), roles!inner(name)")
      .eq("id", invitationId)
      .single();
    if (invitationError || !invitation) throw invitationError ?? new Error("Invitation not found");
    const business = invitation.businesses as { name?: string };
    const role = invitation.roles as { name?: string };
    const businessName = text(business?.name) || "your FlexPOS business";
    const roleName = text(role?.name) || "staff member";
    const acceptUrl = buildRedirectUrl(redirectTo, token, email);

    const resendKey = Deno.env.get("RESEND_API_KEY")?.trim();
    const from = (Deno.env.get("STAFF_INVITE_FROM_EMAIL") ?? Deno.env.get("INVITATION_FROM_EMAIL") ?? Deno.env.get("STOCK_ALERT_FROM_EMAIL"))?.trim();
    if (resendKey && from) {
      await sendWithResend(
        resendKey,
        from,
        email,
        businessName,
        roleName,
        token,
        acceptUrl,
        String(invitation.expires_at),
      );
      return json(200, { sent: true, provider: "resend", email });
    }

    // Fallback to Supabase Auth's configured SMTP provider. The token is
    // embedded in the redirect URL, so accepting the Auth invite can join the
    // business without requiring the recipient to copy a second code.
    const { error: authInviteError } = await ctx.adminClient.auth.admin.inviteUserByEmail(
      email,
      { redirectTo: acceptUrl },
    );
    if (authInviteError) {
      throw new Error(
        `Email delivery is not configured. Add RESEND_API_KEY and STAFF_INVITE_FROM_EMAIL, or configure Supabase Auth SMTP. ${authInviteError.message}`,
      );
    }
    return json(200, { sent: true, provider: "supabase_auth", email });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = /authentication|required|invalid|not accessible|no longer|expired|permission/i.test(message)
      ? 400
      : 502;
    return json(status, { error: message });
  }
});
