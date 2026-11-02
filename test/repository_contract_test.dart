import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/crm/data/crm_repository.dart';
import 'package:flexpos/features/customers/data/customer_repository.dart';
import 'package:flexpos/features/enterprise/data/enterprise_repository.dart';
import 'package:flexpos/features/hardware/data/hardware_repository.dart';
import 'package:flexpos/features/industry/data/industry_repository.dart';
import 'package:flexpos/features/inventory/data/inventory_repository.dart';
import 'package:flexpos/features/promotions/data/promotion_repository.dart';
import 'package:flexpos/features/purchasing/data/purchasing_repository.dart';
import 'package:flexpos/features/receipts/data/receipt_repository.dart';
import 'package:flexpos/features/registers/data/register_repository.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('all feature repositories share a substitutable Supabase contract', () {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
    );
    final repositories = <SupabaseRepositoryContract>[
      AuthRepository(client),
      AccountingRepository(client),
      CatalogRepository(client),
      CrmRepository(client),
      CustomerRepository(client),
      EnterpriseRepository(client),
      HardwareRepository(client),
      IndustryRepository(client),
      InventoryRepository(client),
      PromotionRepository(client),
      PurchasingRepository(client),
      ReceiptRepository(client),
      RegisterRepository(client),
      TenantRepository(client),
    ];

    expect(repositories, hasLength(14));
    for (final repository in repositories) {
      expect(repository.client, same(client));
    }
  });
}
