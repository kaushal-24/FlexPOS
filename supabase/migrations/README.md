# Migrations

Phase 1 requires no application tables. The first Phase 2 migration is
`202610190001_phase2_tenants.sql` and must target only the `flexpos-2` project
(`gpbsblokhpydtpgxpwrg`). It was applied to that project on 2026-10-19.

Every tenant-owned table will ship with RLS enabled, explicit positive and
negative policy tests, foreign keys, indexes, audit timestamps, and migration
rollback notes where a safe rollback is possible.

The migration creates the tenant hierarchy, role and permission model, auth
profile trigger, RLS helper functions, and the atomic
`create_business_with_branch` onboarding RPC. Its companion pgTAP checks live
in `supabase/tests/tenant_rls_test.sql`.

`202610190002_phase2_access_admin.sql` completes Phase 2 with staff invitations,
thirteen default role templates, custom role RPCs, membership and branch-access
administration, tenant audit records, and their RLS policies. It was applied to
`flexpos-2` on 2026-10-19. The companion security suite is
`supabase/tests/phase2_access_admin_test.sql`.

`20261020093000_flexpos_accounting_reports.sql` adds the accounting/reporting
vertical slice: immutable expenses and reversals, customer credit ledger and
repayment allocations, new accounting permissions, and a tenant/branch-scoped
dashboard RPC. Its transactional pgTAP coverage is
`supabase/tests/accounting_reports_test.sql`. It was applied to `flexpos-2` on
2026-10-20, followed by `20261020101500_fix_accounting_owner_role_seed.sql`,
`20261020102000_harden_accounting_table_privileges.sql`, and
`20261020103000_optimize_accounting_foreign_keys.sql`. The 17-case live suite
passes and rolls back its fixtures.

`20261020110000_flexpos_sales_returns.sql` adds partial/full sale returns,
immutable cash-refund records, atomic inventory restoration, idempotency, RLS,
and return-aware net dashboard metrics. It was applied to `flexpos-2` on
2026-10-20. The 21-case transactional suite in
`supabase/tests/sales_returns_test.sql` passes and rolls back its fixtures.

`20261020174049_protect_sale_shift_assignment.sql` prevents a cashier from
posting sales into another cashier's open shift unless the caller has the
`registers.manage` override. It also locks the open shift during sale insertion
to avoid close-versus-sale races. It was applied only to `flexpos-2` on
2026-10-20.

`20261020190000_register_cash_movements_reports.sql` adds immutable,
idempotent cash in/out records with mandatory reasons, permission-checked X/Z
shift reports, and refund-aware drawer reconciliation. The expanded 37-case
`supabase/tests/catalog_inventory_pos_test.sql` verifies exact sales, refunds,
drawer movements, cross-cashier rejection, X/Z reports, and tenant isolation;
all fixtures roll back. It was applied only to `flexpos-2` on 2026-10-20.

`20261020193000_guard_register_cash_out_balance.sql` rejects drawer cash-out
amounts that would make expected cash negative. The resulting 38-case register
suite passes live and rolls back all fixtures. It was applied only to
`flexpos-2` on 2026-10-20.

`20261020203000_atomic_sale_exchanges.sql` adds immutable links between the
original sale, return, and replacement sale. Its permission-checked RPC runs
the return, replacement checkout, stock changes, and exact cash-difference
settlement in one idempotent transaction. The expanded 61-case
`supabase/tests/catalog_inventory_pos_test.sql` suite passes live and rolls
back all fixtures. The suite also verifies exact cash/card/wallet split tender,
pending external settlement, partial checkout with customer-credit remainder,
and atomic under-allocation rejection. It was applied only to `flexpos-2` on
2026-10-20.

`20261022140000_mark_mixed_tender_partially_paid.sql` marks completed sales
with settled cash and a remaining balance as `partially_paid`. Its trigger
function is private and has no direct `public`, `anon`, or `authenticated`
execute privilege. It was applied only to `flexpos-2` on 2026-10-22.

`20261022120000_credit_notes.sql` adds immutable credit-note documents and
redemptions, atomic issuance from returned items, and POS redemption with
partial-balance, expiry, customer-binding, concurrency, and idempotency
controls. `20261022123000_fix_credit_note_parameter_ambiguity.sql` makes the
public RPC parameter unambiguous, and
`20261022130000_optimize_credit_note_foreign_keys.sql` adds covering composite
foreign-key indexes. The 35-case `supabase/tests/credit_notes_test.sql` suite
passes live and rolls back all fixtures. These migrations were applied only to
`flexpos-2` on 2026-10-22.

`20261022150000_held_pos_carts.sql` adds tenant- and branch-scoped persistent
POS carts with read RLS and authenticated, permission-checked park, update, and
discard RPCs. Held carts intentionally do not reserve or move inventory;
checkout revalidates current stock and prices. The follow-up
`20261022151000_index_held_pos_cart_branch_fk.sql` covers the composite branch
foreign key in advisor-compatible order. The 23-case transactional suite in
`supabase/tests/held_pos_carts_test.sql` passes live and rolls back all
fixtures. Both migrations were applied only to `flexpos-2` on 2026-10-22.

`20261022160000_pos_draft_sales.sql` adds tenant- and branch-scoped editable
POS drafts with read RLS and authenticated, permission-checked save, update,
and delete RPCs. Drafts intentionally do not create sales, reserve stock, or
move inventory; checkout revalidates current products, prices, and stock. The
23-case transactional suite in `supabase/tests/pos_drafts_test.sql` passes live
and rolls back all fixtures. The migration was applied only to `flexpos-2` on
2026-10-22.

`20261022170000_sales_quotations.sql` adds tenant- and branch-scoped,
non-posting quotation headers and item snapshots with read RLS and
authenticated, permission-checked save/update, cancel, and conversion RPCs.
Quotations do not create sales or payments and never reserve or move stock;
checkout revalidates the current catalog, prices, and stock before linking the
completed sale. The 27-case transactional suite in
`supabase/tests/sales_quotations_test.sql` passes live and rolls back all
fixtures. The migration was applied only to `flexpos-2` on 2026-10-22.

`20261022180000_sales_orders.sql` adds tenant- and branch-scoped sales-order
headers and exact item/price/tax snapshots with read RLS and authenticated,
permission-checked save/update, cancel, and fulfillment RPCs. Open orders
reserve stock without inventory movement; updates atomically replace their
reservation, cancellation releases it, and fulfillment atomically releases it
while completing and linking the authoritative sale. The 40-case transactional
suite in `supabase/tests/sales_orders_test.sql` passes live and rolls back all
fixtures. The migration was applied only to `flexpos-2` on 2026-10-22.

`20261023100000_gift_cards.sql` adds hashed bearer gift cards, permission-gated
issuance, optional customer binding, expiry and masked balance lookup, and an
immutable value ledger. Concurrency-safe redemption locks the card and settles
the payment and sale atomically without exposing the stored-value tables to
client roles. The 41-case transactional suite in
`supabase/tests/gift_cards_test.sql` passes live and rolls back all fixtures.
The migration was applied only to `flexpos-2` on 2026-10-23.

`20261026070919_sales_report_breakdowns.sql` extends the permission-checked
business dashboard RPC with branch, employee, product, and category sales
breakdowns. All totals respect the caller's branch access, selected report
period, and completed returns; product/category results expose net quantities.
Anonymous execution is explicitly revoked. The migration was applied only to
`flexpos-2` on 2026-10-26 and verified against live report data.

`20261026071924_inventory_valuation_report.sql` adds a permission- and
branch-scoped inventory valuation RPC using each warehouse balance's current
weighted-average cost. It returns current value, on-hand/reserved/available
quantities, SKU and low-stock counts, plus warehouse and category breakdowns.
Anonymous execution is explicitly revoked. The migration was applied only to
`flexpos-2` on 2026-10-26 and verified against live inventory data.

`20261026074352_inventory_ageing_report.sql` adds an indexed, permission- and
branch-scoped FIFO inventory ageing RPC. Current on-hand stock is allocated to
the newest inbound movement layers, with unmatched quantities retained in an
explicit untracked bucket. It returns standard age buckets and warehouse and
category detail. Anonymous execution is explicitly revoked. The migration was
applied only to `flexpos-2` on 2026-10-26 and verified against live movement
history.

`20261026075230_inventory_turnover_report.sql` adds an indexed, permission- and
branch-scoped inventory-turnover RPC. It reconstructs period opening and
closing quantities from the immutable movement ledger, calculates net COGS
after returns, and reports two-point average inventory value, turnover ratio,
days on hand, and product/category detail. Anonymous execution is explicitly
revoked. The migration was applied only to `flexpos-2` on 2026-10-26 and
verified against live sales and inventory data.

`20261026080526_stock_alert_report.sql` adds an indexed, permission- and
branch-scoped stock-alert RPC based on available stock after reservations. It
classifies out-of-stock, below-safety-stock, and reorder-point balances,
identifies missing threshold configuration, and returns minimum replenishment
quantity, estimated cost, item detail, and warehouse/category summaries.
Anonymous execution is explicitly revoked. The migration was applied only to
`flexpos-2` on 2026-10-26 and verified with both live data and a rolled-back
alert fixture.

`20261026081833_customer_retention_lifetime_value_report.sql` adds an indexed,
permission- and branch-scoped customer analytics RPC. It measures identified
customer capture, new/returning/repeat behavior, monthly retention, net revenue
after completed returns, and net lifetime value with customer-level ordering.
Walk-in orders remain in the capture-rate denominator but are excluded from
retention and LTV because they cannot be linked reliably. Anonymous execution
is explicitly revoked. The migration was applied only to `flexpos-2` on
2026-10-26 and verified against live report data.

`20261026123058_customer_credit_ageing_report.sql` adds an indexed,
permission- and branch-scoped customer-credit ageing RPC. It reduces each
credit sale using its exact repayment allocations, applies credit adjustments
FIFO to the oldest remaining debt, and returns four ageing buckets,
older-than-60 exposure, customer-level balances, and credit-limit utilization.
Anonymous execution is explicitly revoked. The migration was applied only to
`flexpos-2` on 2026-10-26 and verified with live data plus a rolled-back
repayment and adjustment fixture.

`20261026124424_sales_targets_comparison_report.sql` adds exact-date-range,
branch-level sales targets with permission-gated upserts, audit logging, RLS,
and an indexed lookup path. Its reporting RPC compares the selected period to
the immediately preceding equivalent-duration period, includes completed
returns in net sales, and returns sales, order, average-order, target, gap, and
branch metrics. Anonymous execution and direct client writes are explicitly
revoked. `20261026125240_index_sales_target_audit_foreign_keys.sql` adds the
covering indexes required by the two user audit foreign keys. Both migrations
were applied only to `flexpos-2` on 2026-10-26 and verified against live sales
data plus a rolled-back target fixture.

`20261027053836_sales_forecast_report.sql` adds a permission- and
branch-scoped net-sales forecast RPC. It fills zero-activity history days,
includes completed returns, applies weekday seasonality with a guarded linear
trend, suppresses extrapolation when history is too limited, and returns daily
estimates with an indicative residual-based range. Anonymous execution is
explicitly revoked. The migration was applied only to `flexpos-2` on
2026-10-27 and verified against live sales history inside a rolled-back
transaction before deployment.

`20261027055446_register_staff_performance_report.sql` adds a permission- and
branch-scoped register reconciliation and staff-performance RPC plus a partial
closed-shift reporting index. It aggregates balanced, over, and short shifts,
cash variances, net sales after completed returns, average order value, and
return handling by active staff and accessible register. Anonymous execution
is explicitly revoked. The migration was applied only to `flexpos-2` on
2026-10-27 and verified both before and after deployment.

`20261027070943_net_profit_reporting.sql` augments the secured business
dashboard with net profit (return-adjusted gross profit less net operating
expenses) and net-profit margin while reusing the existing branch-scoped
dashboard calculation. Profit values remain null without `reports.profit`,
anonymous execution is revoked, and the original dashboard RPC remains
available for compatibility. The migration was applied only to `flexpos-2` on
2026-10-27 and verified against live report data.

`20261027072023_sales_adjustments_report.sql` adds permission- and
branch-scoped reporting for completed sale discounts, returns, refund
allocations, credit-note issuance, return reasons, returned products, and
branch discount rates. It distinguishes line and order discounts plus
settled, pending, and failed refunds. Promotion attribution is excluded until
sales persist a promotion identifier. Anonymous execution is explicitly
revoked. The migration was applied only to `flexpos-2` on 2026-10-27 and
verified against live report data.

`20261027075411_purchase_supplier_performance_report.sql` adds a permission-
and branch-scoped purchase and supplier-performance RPC plus a partial
business/order-date reporting index. It reports order status, ordered and
received spend, quantity fulfillment and outstanding exposure, overdue and
on-time delivery metrics, supplier rankings, and top purchased products.
Anonymous execution is explicitly revoked. The migration was applied only to
`flexpos-2` on 2026-10-27 and verified with the admin user's live permissions
inside a rolled-back transaction.

`20261027103342_dead_stock_report.sql` adds a permission- and branch-scoped
dead-stock RPC plus a partial last-sale movement index. It identifies positive
inventory with no sale during a configurable inactivity window, distinguishes
never-sold stock, measures quantity and value exposure, and groups results by
warehouse and category. Anonymous execution is explicitly revoked. The
migration was applied only to `flexpos-2` on 2026-10-27 after a successful
rolled-back live-data test.

`20261028092437_abc_inventory_analysis.sql` adds a permission- and
branch-scoped ABC inventory RPC. It ranks products by return-adjusted sales
value, classifies cumulative contribution as A through 80%, B through 95%, and
C for the remainder, then reports current inventory exposure for each product
and class. Anonymous execution is explicitly revoked. The migration was
applied only to `flexpos-2` on 2026-10-28 after a successful rolled-back
live-data test.

`20261028093719_purchase_return_stock_movement.sql` adds immutable supplier
return headers and lines plus an idempotent, permission- and warehouse-scoped
RPC. It limits returns to gross received quantities, prevents removal of
reserved or unavailable stock, updates weighted inventory balances, and writes
negative `purchase_return` ledger movements. The new tables use RLS and
explicit authenticated grants; anonymous table and function access is revoked.

`20261028094929_damage_wastage_workflows.sql` adds immutable, valued stock-loss
events and an idempotent damage/wastage RPC. It locks inventory balances,
prevents losses from consuming reserved or unavailable stock, snapshots product
identity and weighted-average cost, and writes matching negative inventory
movements. RLS, explicit authenticated grants, anonymous revocation, composite
foreign-key indexes, and tenant audit events are included.

`20261029170000_inventory_valuation_methods.sql` adds business-scoped
weighted-average, FIFO batch-layer, and standard-cost inventory valuation
settings. Updates are permission-gated, audited, and reflected in the existing
valuation report. `20261029170500_inventory_valuation_settings_indexes.sql`
covers the audit foreign key.

`20261029180000_inventory_stock_alert_notifications.sql` adds durable,
branch-scoped in-app stock alert notifications. Inventory managers can refresh
alerts from the current threshold report, acknowledge them, and have them
automatically resolve when stock recovers. Anonymous access is revoked and
RLS plus authenticated grants are enabled.

`20261029190000_customer_groups.sql` adds business-scoped customer groups and
the composite customer membership foreign key. Group management and customer
assignment use the existing `customers.view` and `customers.manage` policies;
anonymous access is revoked.
`20261029200000_customer_group_pricing.sql` extends `product_prices` with a
business-scoped customer-group foreign key, scoped uniqueness, and an index for
group price resolution.
`20261029210000_loyalty_transactions.sql` adds the business-scoped loyalty
ledger, RLS read policy, and idempotent permission-checked balance adjustment
RPC.
`20261029210500_fix_loyalty_rpc_parameter_ambiguity.sql` replaces the RPC with
unambiguous target-prefixed parameters.
`20261029220000_customer_credit_adjustments.sql` adds the permission-checked,
branch-scoped, idempotent RPC for customer debit and credit adjustments.

`20261029230000_customer_specific_pricing.sql` adds business-safe direct
customer price overrides above customer-group and variant retail prices.
`20261029240000_coupons_promotions.sql` adds branch-aware fixed/percentage
coupons, usage limits, an immutable redemption ledger, and atomic sale linkage;
`20261029241000_coupon_preview.sql` adds the POS preflight preview RPC.
`20261029250000_authorized_price_overrides.sql` adds the permission-gated sale
wrapper that validates unchanged catalog prices and accepts authorized per-line
POS overrides. These migrations are applied only to `flexpos-2`.

`20261030100000_promotion_performance_report.sql` adds the branch- and
permission-scoped `get_promotion_performance_report` RPC. It aggregates coupon
redemptions, unique customers, discounts, attributed sales, campaign rows, and
daily activity for the reports page. The function is callable only by
authenticated report viewers and is applied only to `flexpos-2`.

`20261029260000_tax_inclusive_pricing.sql` updates the live price-validation
helper so gross catalog prices linked to inclusive tax rates are normalized to
the same cent-rounded net amount sent by the Flutter POS client. The client
displays the gross shelf price while authoritative totals continue to store and
calculate net subtotal plus tax. This migration is applied only to `flexpos-2`.

`20261029261000_tax_inclusive_price_precision.sql` keeps four-decimal net
precision in that validator so repeating gross-to-net conversions do not create
one-cent payment mismatches.

`20261029270000_upi_checkout_confirmation.sql` adds the UPI-only POS checkout
confirmation boundary. It grants `payments.confirm_upi` to the standard sales
roles, accepts only `settled` (Success) or `failed` (Failed), refreshes the
sale payment totals atomically, writes an immutable verification event, and
records an idempotent tenant audit event. This migration was applied only to
`flexpos-2` on 2026-10-29.

`20261029280000_custom_sale_items.sql` adds the `sales.custom_item` permission
for the standard sales roles and an idempotent, audited RPC that creates a
service product/variant for a one-off POS item. It validates the unit, optional
tax rate, and positive price before the item becomes part of the authoritative
sale line. This migration was applied only to `flexpos-2` on 2026-10-29.

`20261029281000_fix_business_onboarding_permission_seeding.sql` makes owner
permission seeding conflict-safe so onboarding remains reliable when a role
permission has already been seeded by a trigger or maintenance operation. It
was applied only to `flexpos-2` on 2026-10-29.

`20261029290000_service_charges.sql` adds the `sales.service_charge`
permission and applies a permission-gated fixed service charge at the
authoritative checkout boundary. The amount is included in payment-total
validation, persisted in `sales.service_charge_total`, and returned for receipt
reconstruction. It was applied only to `flexpos-2` on 2026-10-29.
The matching `supabase/tests/service_charges_test.sql` suite verifies exact
totals, persisted charges, settled cash, stock isolation, and owner seeding.

`20261029300000_cash_rounding.sql` adds the `sales.cash_rounding` permission
and permission-checks signed cash-rounding adjustments at authoritative
checkout. The same service-charge test suite verifies the persisted rounded
total and payment amount. It was applied only to `flexpos-2` on 2026-10-29.

`20261029301000_cash_rounding_tender_guard.sql` rejects rounded sales that do
not include a cash tender, keeping the adjustment scoped to cash or split
checkout.

`20261029310000_business_invoice_prefix.sql` patches the authoritative
`complete_sale` function so newly generated invoice numbers use the protected
business `invoice_prefix` setting, with `FP` as a defensive fallback. It was
applied only to `flexpos-2` on 2026-10-29.

`20261029320000_catalog_management_completion.sql` adds the private,
tenant-scoped `product-images` Storage bucket and policies, product image paths,
unit-conversion definitions, and bundle-component definitions. The companion
`20261029321000_catalog_policy_cleanup.sql` separates read/write policies to
avoid overlapping permissive SELECT policies. Both were applied only to
`flexpos-2` on 2026-10-29.

`20261029330000_bundle_inventory_consumption.sql` validates bundle components
as active, non-serialized inventory items and adds a deferred, security-definer
sale trigger. Selling a bundle atomically consumes the selected warehouse's
component balances and active batches with FEFO ordering, writes immutable
inventory and batch movement records, and rejects insufficient stock. It was
applied only to `flexpos-2` on 2026-10-29.

`20261029331000_bundle_parent_guard.sql` prevents direct product writes from
turning a bundle parent into a separately tracked inventory SKU, which avoids
double-depletion when its recipe components are consumed. It was applied only
to `flexpos-2` on 2026-10-29.

`20261029340000_receipt_templates_assets.sql` adds business-scoped receipt
template/logo/QR settings and the private `business-assets` Storage bucket with
tenant policies. `20261029341000_platform_devices_cashier_pin.sql` adds the
service-controlled platform-admin registry, business device registry, and
salted/rate-limited cashier PIN RPCs. Both were applied only to `flexpos-2` on
2026-10-29.

`20261029350000_purchasing_lifecycle_completion.sql` adds tenant-scoped
purchase requisitions and approvals, supplier invoices and idempotent invoice
payments, plus landed-cost allocation across purchase-order lines. Its
follow-up `20261029351000_purchasing_policy_cleanup.sql` separates read and
write RLS policies so workflow tables do not create overlapping permissive
SELECT policies. Both were applied only to `flexpos-2` on 2026-10-29.

`20261029360000_accounting_tax_expenses_completion.sql` adds tenant-scoped
chart of accounts, accounting periods, balanced journal-entry RPCs, cash/bank
account records, recurring expenses, expense approvals and attachments,
effective-dated tax profiles, GST invoice breakdowns, and GST summaries. It
also creates the private `expense-attachments` Storage bucket with
permission-gated object policies. It was applied only to `flexpos-2` on
2026-10-29.

`20261029361000_accounting_statements.sql` adds permission-gated, read-only
profit/loss, balance-sheet, and cash-flow summaries sourced from posted journal
entries. Operational-to-ledger posting is intentionally staged for a separate
validated rollout so historical sales and purchases cannot be duplicated. It
was applied only to `flexpos-2` on 2026-10-29.

`20261029362000_accounting_policy_cleanup.sql` replaces broad accounting
`for all` policies with explicit per-operation policies and keeps approval
events append-only. It was applied only to `flexpos-2` on 2026-10-29.

`20261029363000_accounting_fk_indexes.sql` adds covering indexes for the new
accounting, tax, expense-approval, and attachment foreign keys. It was applied
only to `flexpos-2` on 2026-10-29.

`20261029364000_accounting_composite_fk_indexes.sql` completes the composite
expense approval and attachment foreign-key indexes. It was applied only to
`flexpos-2` on 2026-10-29.

`20261029365000_accounting_journal_corrections.sql` adds an explicit,
permission-gated journal reversal RPC that preserves the original entry as
void and records a reason in the tenant audit log. It was applied only to
`flexpos-2` on 2026-10-29.

`20261029366000_effective_tax_profiles.sql` makes GST origin/place-of-supply
resolution honor branch/business tax profiles by effective date in both tax
invoice detail and GST summaries. It was applied only to `flexpos-2` on
2026-10-29.

`20261029367000_accounting_fiscal_years.sql` adds explicit business-scoped
fiscal-year boundaries, status, RLS, and a permission-gated creation RPC. It
was applied only to `flexpos-2` on 2026-10-29.

`20261029368000_accounting_subledgers_reconciliation_tax_notes.sql` adds the
explicit operational-to-GL bridge for sales, customer receipts, purchases,
supplier payments, expenses, and tax notes. It also adds bank-reconciliation
statement windows with auto-matching and expands tax profiles for GST, VAT,
and sales-tax regimes. Posting is idempotent and permission-gated rather than
implemented as a cross-module trigger. It was applied only to `flexpos-2`.

`20261029369000_accounting_subledger_fk_indexes.sql` adds covering indexes for
the new accounting bridge foreign keys. It was applied only to `flexpos-2`.

`20261029370000_accounting_sync_tax_notes.sql` includes posted tax notes in
the operational-to-GL sync result. It was applied only to `flexpos-2`.

`20261029371000_accounting_tax_note_summary.sql` includes posted sales tax
credit/debit notes and purchase input-tax adjustments in the GST summary and
CSV export. It was applied only to `flexpos-2`.

`20261029372000_accounting_cogs_returns_bridge.sql` adds COGS/inventory lines
to sale posting and explicit GL entries for completed sale returns and settled
refunds. It was applied only to `flexpos-2`.

`20261029373000_accounting_tender_liability_accounts.sql` adds gift-card
liability mapping for settled sale tenders. It was applied only to `flexpos-2`.

`20261030110000_industry_modules.sql` adds the entitlement-aware industry
workflow engine for restaurant, service/repair, wholesale/B2B, grocery,
fashion, electronics, pharmacy, salon, manufacturing, and rental operations.
It includes typed workflow records, line items, append-only status events, RLS,
and atomic create/transition RPCs. The security follow-ups
`20261030111000_industry_modules_security.sql`,
`20261030112000_industry_module_search_path.sql`,
`20261030113000_industry_private_execution.sql`, and
`20261030114000_industry_rpc_security.sql` tighten execute grants, search paths,
and the private authorization boundary. `20261030115000_industry_branch_access_guard.sql`
also requires the signed-in operator to have access to the selected branch.
These migrations were applied only to `flexpos-2` on 2026-10-30.

`20261030160000_enterprise_operations.sql` adds the entitlement-aware
enterprise operations registry for loyalty, workforce, approvals, dashboards,
catalog/order requests, subscriptions, SaaS administration, backup evidence,
labels, localization, forecasting, reorder suggestions, and integration
status. `20261030161000_enterprise_private_execution.sql` grants the RLS
authorization helper to authenticated sessions. Enterprise RPCs enforce
authentication, membership, feature entitlement, permission, branch access,
and audit events. Provider records store only opaque secret references; raw
credentials remain outside the public database. These migrations were applied
only to `flexpos-2` on 2026-10-30. `20261030162000_enterprise_fk_indexes.sql`
adds covering indexes for the enterprise foreign keys, and
`20261030163000_enterprise_branch_guard.sql` requires the selected branch to
belong to the target business before an enterprise operation is authorized.
`20261030164000_enterprise_secret_ref_guard.sql` rejects raw credential
values by requiring opaque `vault://`, `secret://`, or `kms://` references.

`20261030170000_hardware_operations.sql` adds the online-only hardware
registry for camera/HID scanners, thermal printers, ESC/POS, cash drawers,
label printers, scales, and customer displays. It includes entitlement-aware
RLS, branch guards, audited registration/connectivity RPCs, and indexes for
device/event history. Physical Bluetooth, USB, TCP, and serial transport is
left to a native/platform bridge; no offline cache, queue, deferred sync, or
offline sale path is created. This migration was applied only to `flexpos-2`
on 2026-10-30.

`20261030171000_hardware_policy_cleanup.sql` separates hardware read and
write policies so authenticated SELECT requests do not evaluate duplicate
permissive policies. It was applied only to `flexpos-2` on 2026-10-30.

`20261030172000_hardware_connection_guard.sql` enforces the device/transport
compatibility matrix at the database boundary, so an RPC caller cannot record
a USB scanner as a TCP device (or otherwise bypass the UI). It was applied
only to `flexpos-2` on 2026-10-30.

`20261030180000_backend_architecture_completion.sql` adds immutable
`invoice_documents` snapshots, authenticated gift-card reads, advisor-safe
policy splits, RLS-protected realtime publication membership, and bounded sales
and product keyset RPCs. `20261030181500_keyset_authorization_wrapper.sql`
keeps those readers invoker functions while exposing only their narrow
authorization decision. Both were applied only to `flexpos-2` on 2026-10-30.

`20261030183000_loyalty_sale_rules.sql` adds business-configurable loyalty
settings, automatic idempotent points for paid/partially-paid completed sales,
and a permission-gated, balance-safe redemption RPC. It was applied only to
`flexpos-2` on 2026-10-30. The `integration-health` JWT Edge Function is
deployed separately and forwards only opaque provider references to the audited
integration RPC.

## Local/live migration reconciliation (2026-10-30)

The repository currently contains **142** ordered migration files while
`supabase_list_migrations` reports **137** tracked records in `flexpos-2`.
This is known history drift, not a reason to replay the database from scratch.
The local-only names are:

- `phase2_tenants`
- `phase2_access_admin`
- `flexpos_foundation`
- `flexpos_catalog_inventory_pos`
- `flexpos_security_performance`
- `flexpos_crm`
- `harden_serial_lookup_policy`

`sales_report_breakdowns` has two local timestamped files but one live
application record. The live history also records three retry/fix names whose
local files were later renamed or consolidated:

- `harden_serial_lookup_policy_retry`
- `fix_inventory_transfer_workflow_result_audit_refs`
- `promotion_performance_unique_customers`

The live schema was
verified through the deployed RPCs and advisors, so these files must not be
blindly replayed against production. Reconciliation remains open until the
local migration ledger is deliberately rebased to the live history.
