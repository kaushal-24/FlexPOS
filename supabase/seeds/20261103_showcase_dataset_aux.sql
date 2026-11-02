-- Auxiliary review fixtures for targets, recurring expenses, valuation,
-- stock-loss review, accounting subledgers, and device management.

begin;
select set_config('request.jwt.claim.sub', '01331716-1fbd-4780-bc16-b4dba20a96aa', true);

do $$
declare
  b record;
  v_admin constant uuid := '01331716-1fbd-4780-bc16-b4dba20a96aa';
  v_cashier constant uuid := 'b19328a2-ac43-4291-8ff1-615d153b0b0f';
  v_manager constant uuid := '73558bcb-8f47-4e36-9c3e-2ff4f7f16d98';
begin
  for b in
    select * from (values
      ('7b000000-0000-4000-8000-000000000001'::uuid, 'Retail'),
      ('7b000000-0000-4000-8000-000000000002'::uuid, 'Cafe')
    ) as x(id, label)
  loop
    insert into public.sales_targets (
      id, business_id, branch_id, starts_on, ends_on, target_amount,
      notes, created_by, updated_by
    )
    select
      md5(b.id::text || '|sales-target|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || i::text)::uuid,
      current_date - 30, current_date + 30,
      250000 + (i * 50000),
      format('Synthetic monthly sales target for %s branch %s.', b.label, i),
      v_admin, v_admin
    from generate_series(1, 4) as s(i)
    on conflict (id) do update set target_amount = excluded.target_amount, notes = excluded.notes;

    insert into public.accounting_recurring_expenses (
      id, business_id, branch_id, category_id, description, amount,
      tax_amount, payment_method, vendor_name, frequency, next_run_on,
      end_on, is_active, last_generated_on, created_by
    )
    select
      md5(b.id::text || '|recurring-expense|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|expense-category|' || (((i - 1) % 6) + 1)::text)::uuid,
      format('Synthetic recurring %s expense %s.', b.label, i),
      12000 + (i * 1500), 0,
      case when i % 2 = 0 then 'bank_transfer' else 'upi' end,
      format('%s recurring vendor %s', b.label, i),
      case when i % 3 = 0 then 'yearly' when i % 2 = 0 then 'monthly' else 'weekly' end,
      current_date + (i * 3), current_date + 365, true,
      case when i % 3 = 0 then current_date - 30 else null end,
      v_admin
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set amount = excluded.amount, next_run_on = excluded.next_run_on;

    insert into public.inventory_valuation_settings (
      business_id, valuation_method, standard_cost, updated_by
    )
    values (b.id, case when b.label = 'Retail' then 'fifo' else 'weighted_average' end, null, v_admin)
    on conflict (business_id) do update set valuation_method = excluded.valuation_method, updated_by = excluded.updated_by;

    insert into public.stock_loss_events (
      id, business_id, warehouse_id, variant_id, event_number, loss_type,
      product_name, variant_name, sku, quantity, unit_cost, loss_value,
      reason, notes, operation_id, recorded_by, recorded_at
    )
    select
      md5(b.id::text || '|stock-loss|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|warehouse|1')::uuid,
      md5(b.id::text || '|variant|' || (100 + i)::text)::uuid,
      format('%s-LOSS-%06s', upper(left(b.label, 3)), i),
      case when i % 2 = 0 then 'wastage' else 'damage' end,
      format('%s Showcase Product %s', b.label, 100 + i), 'Standard pack',
      format('%s-%s', upper(left(b.label, 3)), lpad((100 + i)::text, 5, '0')),
      2 + i, 40 + (i * 2), round((2 + i)::numeric * (40 + (i * 2)), 2),
      case when i % 2 = 0 then 'Expired stock' else 'Packaging damage' end,
      'Synthetic stock-loss event for review.',
      md5(b.id::text || '|stock-loss-op|' || i::text)::uuid,
      v_manager, now() - make_interval(days => i)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set loss_value = excluded.loss_value, reason = excluded.reason;

    insert into public.accounting_subledger_postings (
      id, business_id, subledger_type, source_id, journal_entry_id,
      memo, posted_by, posted_at
    )
    select
      md5(b.id::text || '|subledger|' || i::text)::uuid,
      b.id, 'sale',
      md5(b.id::text || '|sale|' || i::text)::uuid,
      md5(b.id::text || '|journal-entry|' || i::text)::uuid,
      format('Synthetic subledger posting for sale %s.', i),
      v_admin, now() - make_interval(days => i)
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set memo = excluded.memo, posted_at = excluded.posted_at;

    insert into public.business_devices (
      id, business_id, user_id, device_key, device_name, platform, status,
      last_seen_at, revoked_at
    )
    select
      md5(b.id::text || '|business-device|' || i::text)::uuid,
      b.id,
      case when i % 3 = 0 then v_manager when i % 2 = 0 then v_cashier else v_admin end,
      encode(digest(b.id::text || '|business-device|' || i::text, 'sha256'), 'hex'),
      format('%s Review Device %s', b.label, i),
      (array['web','windows','android','ios'])[1 + ((i - 1) % 4)],
      case when i % 5 = 0 then 'revoked' else 'active' end,
      now() - make_interval(hours => i),
      case when i % 5 = 0 then now() - make_interval(days => i) else null end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status, last_seen_at = excluded.last_seen_at;
  end loop;
end $$;

commit;
