-- Remaining review fixtures: purchase returns, credit notes, register cash
-- movements, and synthetic staff invitations.

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
    insert into public.purchase_returns (
      id, business_id, purchase_order_id, warehouse_id, return_number,
      status, total_cost, reason, notes, operation_id, returned_by, returned_at
    )
    select
      md5(b.id::text || '|purchase-return|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-order|' || i::text)::uuid,
      md5(b.id::text || '|warehouse|1')::uuid,
      format('%s-PR-%06s', upper(left(b.label, 3)), i),
      'completed', 240 + (i * 25),
      case when i % 2 = 0 then 'Supplier quality issue' else 'Over-delivery correction' end,
      'Synthetic supplier return for purchasing review.',
      md5(b.id::text || '|purchase-return-op|' || i::text)::uuid,
      v_manager, now() - make_interval(days => i)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set total_cost = excluded.total_cost, reason = excluded.reason;

    insert into public.purchase_return_items (
      id, business_id, purchase_return_id, purchase_order_item_id, variant_id,
      quantity, unit_cost, line_total
    )
    select
      md5(b.id::text || '|purchase-return-item|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|purchase-return|' || i::text)::uuid,
      md5(b.id::text || '|purchase-item|' || i::text)::uuid,
      md5(b.id::text || '|variant|' || i::text)::uuid,
      2 + i, 35 + (i * 3), round((2 + i)::numeric * (35 + (i * 3)), 2)
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set quantity = excluded.quantity, line_total = excluded.line_total;

    insert into public.credit_notes (
      id, business_id, branch_id, customer_id, original_sale_id, return_id,
      credit_note_number, currency_code, issued_amount, reason, operation_id,
      issued_by, issued_at, expires_at
    )
    select
      md5(b.id::text || '|credit-note|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid,
      md5(b.id::text || '|customer|' || i::text)::uuid,
      md5(b.id::text || '|sale|' || (16 + i)::text)::uuid,
      md5(b.id::text || '|return|' || i::text)::uuid,
      format('%s-CN-%06s', upper(left(b.label, 3)), i),
      'INR', 118, 'Synthetic customer credit note.',
      md5(b.id::text || '|credit-note-op|' || i::text)::uuid,
      v_admin, now() - make_interval(days => i), now() + interval '180 days'
    from generate_series(1, 4) as s(i)
    on conflict (id) do update set issued_amount = excluded.issued_amount;

    insert into public.credit_note_redemptions (
      id, business_id, credit_note_id, sale_id, payment_id, amount,
      redeemed_by, redeemed_at
    )
    select
      md5(b.id::text || '|credit-redemption|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|credit-note|' || i::text)::uuid,
      md5(b.id::text || '|sale|' || (40 + i)::text)::uuid,
      md5(b.id::text || '|payment|' || (40 + i)::text)::uuid,
      50, v_cashier, now() - make_interval(days => i)
    from generate_series(1, 4) as s(i)
    on conflict (id) do update set amount = excluded.amount;

    insert into public.register_cash_movements (
      id, business_id, shift_id, movement_type, amount, reason,
      operation_id, created_by
    )
    select
      md5(b.id::text || '|cash-movement|' || i::text)::uuid,
      b.id,
      md5(b.id::text || '|shift|' || i::text)::uuid,
      case when i % 2 = 0 then 'cash_out' else 'cash_in' end,
      200 + (i * 25),
      case when i % 2 = 0 then 'Safe drop' else 'Opening float top-up' end,
      md5(b.id::text || '|cash-movement-op|' || i::text)::uuid,
      case when i % 2 = 0 then v_manager else v_cashier end
    from generate_series(1, 16) as s(i)
    on conflict (id) do update set amount = excluded.amount, reason = excluded.reason;

    insert into public.business_invitations (
      id, business_id, email, role_id, branch_access_all, token_hash,
      status, invited_by, accepted_by, expires_at, accepted_at, revoked_at
    )
    select
      md5(b.id::text || '|invitation|' || i::text)::uuid,
      b.id,
      format('review.staff%02s@showcase.flexpos.demo', i),
      md5(b.id::text || '|role|' || (array['Cashier','Inventory Manager','Purchase Manager','Accountant'])[1 + ((i - 1) % 4)])::uuid,
      i % 2 = 0,
      encode(digest(b.id::text || '|invitation|' || i::text, 'sha256'), 'hex'),
      case when i % 5 = 0 then 'revoked' when i % 4 = 0 then 'accepted' when i % 3 = 0 then 'expired' else 'pending' end,
      v_admin,
      case when i % 4 = 0 then v_cashier else null end,
      now() + make_interval(days => 7 + i),
      case when i % 4 = 0 then now() - make_interval(days => i) else null end,
      case when i % 5 = 0 then now() - make_interval(days => i) else null end
    from generate_series(1, 8) as s(i)
    on conflict (id) do update set status = excluded.status, expires_at = excluded.expires_at;

    insert into public.invitation_branch_access (invitation_id, branch_id)
    select
      md5(b.id::text || '|invitation|' || i::text)::uuid,
      md5(b.id::text || '|branch|' || (((i - 1) % 4) + 1)::text)::uuid
    from generate_series(1, 8) as s(i)
    where i % 2 = 1
    on conflict do nothing;
  end loop;
end $$;

commit;
