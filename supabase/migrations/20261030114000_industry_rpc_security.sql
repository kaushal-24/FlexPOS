begin;

-- These RPCs perform a permission-checked atomic write.  SECURITY DEFINER is
-- used only so the public API can call non-exposed private authorization
-- helpers without granting broad schema access to client roles.
create or replace function public.create_industry_workflow(
  target_business_id uuid,
  target_branch_id uuid,
  target_kind text,
  target_reference_code text,
  target_title text,
  target_status text default 'draft',
  target_customer_id uuid default null,
  target_product_id uuid default null,
  target_assigned_to uuid default null,
  target_scheduled_at timestamptz default null,
  target_due_at timestamptz default null,
  target_quantity numeric default 0,
  target_unit_price numeric default 0,
  target_total_amount numeric default 0,
  target_deposit_amount numeric default 0,
  target_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_module text := private.industry_module_for_kind(target_kind);
  created_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if target_module is null then raise exception 'Unsupported industry workflow kind'; end if;
  if not private.industry_workflow_authorized(target_business_id, target_module, 'industry.manage') then
    raise exception 'Industry management permission and module entitlement required';
  end if;
  if target_branch_id is not null and not private.has_branch_access(target_branch_id) then
    raise exception 'Branch access required';
  end if;
  if target_reference_code is null or length(btrim(target_reference_code)) < 1 then raise exception 'Reference code is required'; end if;
  if target_title is null or length(btrim(target_title)) < 1 then raise exception 'Title is required'; end if;
  if target_payload is null or jsonb_typeof(target_payload) <> 'object' then raise exception 'Workflow payload must be a JSON object'; end if;
  insert into public.industry_workflows (business_id, branch_id, module_code, workflow_kind, reference_code, title, status, customer_id, product_id, assigned_to, scheduled_at, due_at, quantity, unit_price, total_amount, deposit_amount, payload)
  values (target_business_id, target_branch_id, target_module, target_kind, btrim(target_reference_code), btrim(target_title), target_status, target_customer_id, target_product_id, target_assigned_to, target_scheduled_at, target_due_at, greatest(coalesce(target_quantity,0),0), greatest(coalesce(target_unit_price,0),0), greatest(coalesce(target_total_amount,0),0), greatest(coalesce(target_deposit_amount,0),0), coalesce(target_payload,'{}'::jsonb))
  returning id into created_id;
  insert into public.industry_workflow_events (business_id, workflow_id, to_status, note) values (target_business_id, created_id, target_status, 'Workflow created');
  return created_id;
end;
$$;

create or replace function public.transition_industry_workflow(
  target_business_id uuid,
  target_workflow_id uuid,
  target_status text,
  target_note text default null,
  target_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  workflow_row public.industry_workflows%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into workflow_row from public.industry_workflows where id = target_workflow_id and business_id = target_business_id for update;
  if not found then raise exception 'Workflow not found'; end if;
  if not private.industry_workflow_authorized(target_business_id, workflow_row.module_code, 'industry.manage') then raise exception 'Industry management permission and module entitlement required'; end if;
  update public.industry_workflows set status=target_status, updated_by=auth.uid(), updated_at=now() where id=workflow_row.id and business_id=target_business_id;
  insert into public.industry_workflow_events (business_id, workflow_id, from_status, to_status, note, metadata) values (target_business_id, workflow_row.id, workflow_row.status, target_status, target_note, coalesce(target_metadata,'{}'::jsonb));
  return true;
end;
$$;

revoke execute on function public.create_industry_workflow(uuid,uuid,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,jsonb) from public, anon;
revoke execute on function public.transition_industry_workflow(uuid,uuid,text,text,jsonb) from public, anon;
grant execute on function public.create_industry_workflow(uuid,uuid,text,text,text,text,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,jsonb) to authenticated;
grant execute on function public.transition_industry_workflow(uuid,uuid,text,text,jsonb) to authenticated;

commit;
