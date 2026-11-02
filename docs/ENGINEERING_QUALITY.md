# FlexPOS engineering quality

## Substitution and testing boundaries

Every feature data repository implements
`SupabaseRepositoryContract`, which exposes the injected `SupabaseClient`
through a stable interface. Riverpod providers still construct the production
repositories, while unit tests can provide a contract-compatible fake without
coupling presentation code to concrete data classes. The contract is verified
for all 14 repositories in `test/repository_contract_test.dart`.

## Server-backed pagination

Large interactive catalog and order reads use the bounded Supabase keyset RPCs
`list_products_keyset` and `list_sales_keyset`. `CatalogRepository` exposes
`fetchProductsPage` and `fetchSalesPage`, returning `ServerPage<T>` with a
stable `(created_at, id)` cursor and a maximum page size of 100. This prevents
offset drift and keeps the client from loading an unbounded tenant dataset.
Secondary screens retain explicit server-side caps and tenant filters; reports
use aggregate RPCs rather than downloading raw ledgers.

## Performance profiling

Run `dart run tool/performance_profile.dart` from the project root to profile a
100,000-row page extraction against the 100 ms local budget. The same budget is
asserted by `test/performance_profile_test.dart`. Database keyset plans are
validated by the backend architecture pgTAP suite and the live Supabase
performance advisor. The profiler is deterministic and dependency free, so it
can run in CI or a release checklist without an offline data mode.

## Accessibility audit

Shared controls provide visible labels, tooltip/semantic names, 48 px padded
touch targets, keyboard-focusable actions, status semantics, empty/loading/
error announcements, and 200% text scaling. Automated coverage lives in
`test/accessibility_test.dart`; the audit includes authentication, dashboard,
POS, catalog, inventory, customers, purchasing, accounting, CRM, enterprise,
hardware, registers, reports, settings, and receipt flows because each uses the
same audited shell and data-list primitives. Manual release checks remain:
keyboard-only traversal, screen-reader order on the target platform, and
physical contrast validation on the deployed display.

| Audit surface | Automated gate | Release check |
| --- | --- | --- |
| Color and status | WCAG AA contrast assertions; status semantics | Verify the deployed display in light and dark themes |
| Touch and pointer input | 48 px theme minimum; labelled data-list actions | Exercise primary actions with mouse, touch, and keyboard |
| Text scaling | 200% text-scaling widget coverage | Check authentication, POS, and receipt flows at 200% |
| Navigation semantics | Semantic labels and tooltips on shared controls | Confirm screen-reader order and focus traversal on each target platform |
