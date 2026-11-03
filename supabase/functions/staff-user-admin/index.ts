import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

type Json = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "no-store",
  "content-type": "application/json",
};

function json(status: number, body: Json): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asObject(value: unknown): Json {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Json
    : {};
}

function uuid(value: unknown, field: string): string {
  const candidate = text(value);
  if (!UUID.test(candidate)) throw new Error(`${field} must be a valid UUID`);
  return candidate;
}

function branchIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((entry) => text(entry)).filter((entry) => UUID.test(entry)))];
}

function env(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is not configured`);
  return value;
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
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!anonKey) throw new Error("Supabase publishable key is not configured");
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) throw new Error("Authentication required");
  const adminClient = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  return { user: data.user, userClient, adminClient };
}

async function permissionsFor(
  client: SupabaseClient,
  businessId: string,
  userId: string,
): Promise<Set<string>> {
  const { data: memberships, error: membershipError } = await client
    .from("memberships")
    .select("role_id")
    .eq("business_id", businessId)
    .eq("user_id", userId)
    .eq("status", "active")
    .is("archived_at", null);
  if (membershipError) throw membershipError;
  const roleIds = (memberships ?? []).map((row) => row.role_id as string);
  if (roleIds.length === 0) return new Set();
  const { data: rows, error } = await client
    .from("role_permissions")
    .select("permission_code")
    .in("role_id", roleIds);
  if (error) throw error;
  return new Set((rows ?? []).map((row) => row.permission_code as string));
}

async function assertCanManage(
  admin: SupabaseClient,
  businessId: string,
  actorId: string,
  targetRoleId?: string,
): Promise<void> {
  const actorPermissions = await permissionsFor(admin, businessId, actorId);
  if (!actorPermissions.has("staff.manage")) throw new Error("Staff management permission is required");
  if (!targetRoleId) return;
  const { data: role, error: roleError } = await admin
    .from("roles")
    .select("id,business_id")
    .eq("id", targetRoleId)
    .eq("business_id", businessId)
    .maybeSingle();
  if (roleError) throw roleError;
  if (!role) throw new Error("The selected role does not belong to this business");
  const { data: targetPermissions, error: targetError } = await admin
    .from("role_permissions")
    .select("permission_code")
    .eq("role_id", targetRoleId);
  if (targetError) throw targetError;
  if ((targetPermissions ?? []).some((row) => !actorPermissions.has(row.permission_code as string))) {
    throw new Error("You cannot assign permissions above your own access");
  }
}

async function validateBranches(
  admin: SupabaseClient,
  businessId: string,
  allBranches: boolean,
  ids: string[],
): Promise<void> {
  if (allBranches) return;
  if (ids.length === 0) throw new Error("Select at least one branch or grant all-branch access");
  const { data, error } = await admin
    .from("branches")
    .select("id")
    .eq("business_id", businessId)
    .in("id", ids)
    .is("archived_at", null);
  if (error) throw error;
  if ((data ?? []).length !== ids.length) throw new Error("Every selected branch must belong to this business");
}

async function profileUpsert(
  admin: SupabaseClient,
  userId: string,
  email: string,
  fullName: string,
): Promise<void> {
  const { error } = await admin.from("profiles").upsert({
    id: userId,
    email,
    full_name: fullName || null,
  }, { onConflict: "id" });
  if (error) throw error;
}

async function createUser(
  ctx: AuthContext,
  body: Json,
  businessId: string,
): Promise<Json> {
  const email = text(body.email).toLowerCase();
  const password = text(body.password);
  const fullName = text(body.full_name);
  const roleId = uuid(body.role_id, "role_id");
  const allBranches = body.all_branches === true;
  const ids = branchIds(body.branch_ids);
  if (!EMAIL.test(email)) throw new Error("Enter a valid email address");
  if (password.length < 8 || password.length > 128) throw new Error("Password must be 8–128 characters");
  if (fullName.length > 120) throw new Error("Full name is too long");
  await assertCanManage(ctx.adminClient, businessId, ctx.user.id, roleId);
  await validateBranches(ctx.adminClient, businessId, allBranches, ids);

  const { data: created, error: createError } = await ctx.adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName || null },
  });
  if (createError || !created.user) throw new Error(createError?.message ?? "Could not create the login");

  const userId = created.user.id;
  try {
    await profileUpsert(ctx.adminClient, userId, email, fullName);
    const membershipId = crypto.randomUUID();
    const { error: membershipError } = await ctx.adminClient.from("memberships").insert({
      id: membershipId,
      business_id: businessId,
      user_id: userId,
      role_id: roleId,
      status: "active",
      branch_access_all: allBranches,
      joined_at: new Date().toISOString(),
    });
    if (membershipError) throw membershipError;
    if (!allBranches) {
      const { error: branchError } = await ctx.adminClient.from("member_branch_access").insert(
        ids.map((branchId) => ({ membership_id: membershipId, branch_id: branchId })),
      );
      if (branchError) throw branchError;
    }
    const { error: auditError } = await ctx.adminClient.from("tenant_audit_logs").insert({
      business_id: businessId,
      actor_user_id: ctx.user.id,
      action: "staff.user_created",
      target_type: "user",
      target_id: userId,
      details: { email, role_id: roleId, direct_password: true },
    });
    if (auditError) throw auditError;
  } catch (error) {
    await ctx.adminClient.auth.admin.deleteUser(userId);
    throw error;
  }
  return { user_id: userId, email, full_name: fullName, role_id: roleId };
}

async function updateUser(
  ctx: AuthContext,
  body: Json,
  businessId: string,
): Promise<Json> {
  const userId = uuid(body.user_id, "user_id");
  if (userId === ctx.user.id) throw new Error("You cannot change your own staff access here");
  const roleId = body.role_id === undefined ? undefined : uuid(body.role_id, "role_id");
  await assertCanManage(ctx.adminClient, businessId, ctx.user.id, roleId);
  const { data: member, error: memberError } = await ctx.adminClient
    .from("memberships")
    .select("id,role_id,status,branch_access_all")
    .eq("business_id", businessId)
    .eq("user_id", userId)
    .is("archived_at", null)
    .maybeSingle();
  if (memberError) throw memberError;
  if (!member) throw new Error("Staff membership not found");
  const email = body.email === undefined ? "" : text(body.email).toLowerCase();
  const fullName = body.full_name === undefined ? "" : text(body.full_name);
  const password = body.password === undefined ? "" : text(body.password);
  if (email && !EMAIL.test(email)) throw new Error("Enter a valid email address");
  if (password && (password.length < 8 || password.length > 128)) throw new Error("Password must be 8–128 characters");
  if (email || fullName || password) {
    const { data: existingProfile, error: profileError } = await ctx.adminClient
      .from("profiles")
      .select("email,full_name")
      .eq("id", userId)
      .maybeSingle();
    if (profileError) throw profileError;
    let currentEmail = text(existingProfile?.email);
    const currentName = text(existingProfile?.full_name);
    if (!currentEmail) {
      const { data: currentUser, error: userError } = await ctx.adminClient.auth.admin.getUserById(userId);
      if (userError) throw userError;
      currentEmail = text(currentUser.user?.email);
    }
    if (!currentEmail) throw new Error("The staff login has no email address");
    const patch: {
      email?: string;
      email_confirm?: boolean;
      password?: string;
      user_metadata?: { full_name: string };
    } = {};
    if (email) {
      patch.email = email;
      patch.email_confirm = true;
    }
    if (password) patch.password = password;
    if (fullName) patch.user_metadata = { full_name: fullName };
    const { error } = await ctx.adminClient.auth.admin.updateUserById(userId, patch);
    if (error) throw error;
    await profileUpsert(ctx.adminClient, userId, email || currentEmail, fullName || currentName);
  }
  if (roleId !== undefined || body.status !== undefined || body.all_branches !== undefined) {
    const allBranches = body.all_branches === undefined
      ? member.branch_access_all === true
      : body.all_branches === true;
    let ids = body.branch_ids === undefined ? [] : branchIds(body.branch_ids);
    if (body.branch_ids === undefined && !allBranches) {
      const { data: currentBranches, error: branchError } = await ctx.adminClient
        .from("member_branch_access")
        .select("branch_id")
        .eq("membership_id", member.id);
      if (branchError) throw branchError;
      ids = (currentBranches ?? []).map((row) => row.branch_id as string);
    }
    await validateBranches(ctx.adminClient, businessId, allBranches, ids);
    const { error: accessError } = await ctx.userClient.rpc("update_membership_access", {
      target_membership_id: member.id,
      target_role_id: roleId ?? member.role_id,
      target_status: body.status === undefined ? member.status : text(body.status),
      grants_all_branches: allBranches,
      target_branch_ids: ids,
    });
    if (accessError) throw accessError;
    if (body.status === "active") {
      const { error: unbanError } = await ctx.adminClient.auth.admin.updateUserById(
        userId,
        { ban_duration: "none" },
      );
      if (unbanError) throw unbanError;
    }
  }
  return { user_id: userId, updated: true };
}

async function deleteUser(ctx: AuthContext, body: Json, businessId: string): Promise<Json> {
  const userId = uuid(body.user_id, "user_id");
  if (userId === ctx.user.id) throw new Error("You cannot delete your own login");
  await assertCanManage(ctx.adminClient, businessId, ctx.user.id);
  const { data: targetMembership, error: targetMembershipError } = await ctx.adminClient
    .from("memberships")
    .select("id")
    .eq("business_id", businessId)
    .eq("user_id", userId)
    .is("archived_at", null)
    .maybeSingle();
  if (targetMembershipError) throw targetMembershipError;
  if (!targetMembership) throw new Error("Staff membership not found");
  // Delete access only in the business where the action was requested. A
  // staff login can belong to several businesses, and one tenant manager
  // must never revoke access in another tenant. Archive the membership so it
  // disappears from the active Staff & Roles list while preserving history.
  const { error: revokeError } = await ctx.adminClient
    .from("memberships")
    .update({
      status: "revoked",
      archived_at: new Date().toISOString(),
    })
    .eq("id", targetMembership.id)
    .eq("business_id", businessId)
    .eq("user_id", userId);
  if (revokeError) throw revokeError;
  const { data: remainingMemberships, error: remainingError } = await ctx.adminClient
    .from("memberships")
    .select("id")
    .eq("user_id", userId)
    .eq("status", "active")
    .is("archived_at", null);
  if (remainingError) throw remainingError;
  const loginDisabled = (remainingMemberships ?? []).length === 0;
  if (loginDisabled) {
    const { error: disableError } = await ctx.adminClient.auth.admin.updateUserById(
      userId,
      { ban_duration: "876000h" },
    );
    if (disableError) throw disableError;
  }
  const { error: auditError } = await ctx.adminClient.from("tenant_audit_logs").insert({
    business_id: businessId,
    actor_user_id: ctx.user.id,
    action: "staff.user_deleted",
    target_type: "user",
    target_id: userId,
    details: {
      business_access_archived: true,
      direct_login_deleted: loginDisabled,
      login_disabled: loginDisabled,
      remaining_active_businesses: (remainingMemberships ?? []).length,
    },
  });
  if (auditError) throw auditError;
  return {
    user_id: userId,
    deleted: loginDisabled,
    business_access_removed: true,
    login_disabled: loginDisabled,
    remaining_active_businesses: (remainingMemberships ?? []).length,
  };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "POST is required" });
  try {
    const ctx = await authContext(request);
    const body = asObject(await request.json());
    const action = text(body.action);
    const businessId = uuid(body.business_id, "business_id");
    if (action === "create") return json(200, await createUser(ctx, body, businessId));
    if (action === "update") return json(200, await updateUser(ctx, body, businessId));
    if (action === "delete") return json(200, await deleteUser(ctx, body, businessId));
    return json(400, { error: "action must be create, update, or delete" });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const status = /authentication|required|permission|cannot|not belong|belongs|not found|must be|select at least|password|valid email/i.test(message)
      ? 400
      : 500;
    return json(status, { error: message });
  }
});
