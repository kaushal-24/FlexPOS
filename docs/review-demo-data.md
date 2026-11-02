# FlexPOS review demo data

The live `flexpos-2` project contains a separate business named **FlexPOS Review Demo** for presentations and final reviews.

- Business ID: `9a4c0000-0000-4000-8000-000000000001`
- Slug: `flexpos-review-demo`
- Branches: Koramangala Flagship and Indiranagar Express
- Demo staff: the existing owner, cashier, and branch-manager profiles already present in `flexpos-2`

The dataset is realistic but synthetic. Names, phone numbers, emails, GSTINs, invoice numbers, payment references, and provider identifiers are demo-only values; no real customer or supplier data was imported.

Seed files:

- `supabase/seeds/20261103_review_demo_data.sql` — tenant, branches, roles, catalog, warehouses, stock, customers, suppliers, registers, shifts, and promotion.
- `supabase/seeds/20261103_review_demo_transactions.sql` — sales, payments, cash movements, expenses, purchase orders, and goods receipt.
- `supabase/seeds/20261103_review_demo_modules.sql` — CRM, sales targets, stock notifications, customer ledger, accounting, industry workflows, enterprise records, integrations, hardware, and audit events.

The seed uses deterministic IDs and upserts so it can be re-run for the same demo tenant. It does not modify the existing `FlexPOS` or `Al Hamza` businesses.

For a presentation, switch the business selector to **FlexPOS Review Demo** and use the two branches to show multi-branch behavior. Razorpay rows are explicitly marked test/demo mode and do not contain live credentials.

## Showcase review businesses (2026-11-03)

Two additional presentation tenants were added to the same `flexpos-2` project:

- **FlexPOS Showcase Retail** (`7b000000-0000-4000-8000-000000000001`) — Bengaluru, four branches.
- **FlexPOS Showcase Cafe** (`7b000000-0000-4000-8000-000000000002`) — Pune, four branches.

Each showcase tenant has 124 catalog products (with existing product-image assets), variants and barcodes, customers, suppliers, sales, payments, purchase orders, expenses, CRM records, promotions, stock alerts, accounting entries, industry workflows, enterprise records, integrations, hardware devices, audit history, and staff-invitation examples. Optional screens also have sample price lists, held carts, POS drafts, quotes, orders, gift cards, returns/refunds/exchanges, credit notes, customer receipts, requisitions, supplier invoices, landed costs, recurring expenses, sales targets, reconciliations, tax notes, serial units, batches, transfers, stocktakes, stock-loss events, workflow events, invoice documents, business devices, subledger postings, and register cash movements.

The deterministic seed files are:

- `supabase/seeds/20261103_showcase_dataset_core.sql`
- `supabase/seeds/20261103_showcase_dataset_activity.sql`
- `supabase/seeds/20261103_showcase_dataset_extended.sql`
- `supabase/seeds/20261103_showcase_dataset_extended2.sql`
- `supabase/seeds/20261103_showcase_dataset_extended3.sql`
- `supabase/seeds/20261103_showcase_dataset_extended4.sql`
- `supabase/seeds/20261103_showcase_dataset_aux.sql`
- `supabase/seeds/20261103_showcase_dataset_serial_links.sql`

All records are synthetic review data. The three existing authenticated project users are reused for demo memberships and role assignments; no passwords or new auth identities were created. The existing production `FlexPOS` business, the ap-south-1 project, and `Al Hamza` were not modified.
