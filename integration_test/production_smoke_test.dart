import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/purchasing/data/purchasing_repository.dart';
import 'package:flexpos/features/purchasing/domain/purchasing_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _email = String.fromEnvironment('FLEXPOS_TEST_EMAIL');
const _password = String.fromEnvironment('FLEXPOS_TEST_PASSWORD');
const _businessId = String.fromEnvironment('FLEXPOS_TEST_BUSINESS_ID');
const _saleId = String.fromEnvironment('FLEXPOS_TEST_SALE_ID');
const _secondEmail = String.fromEnvironment('FLEXPOS_TEST_SECOND_EMAIL');
const _secondPassword = String.fromEnvironment('FLEXPOS_TEST_SECOND_PASSWORD');
const _secondBusinessId = String.fromEnvironment(
  'FLEXPOS_TEST_SECOND_BUSINESS_ID',
);

bool get _configured =>
    _url.isNotEmpty &&
    _publishableKey.isNotEmpty &&
    _email.isNotEmpty &&
    _password.isNotEmpty &&
    _businessId.isNotEmpty;

bool get _returnFixtureConfigured => _configured && _saleId.isNotEmpty;

bool get _concurrentConfigured =>
    _configured &&
    _secondEmail.isNotEmpty &&
    _secondPassword.isNotEmpty &&
    _secondBusinessId.isNotEmpty;

late SupabaseClient _client;
late CatalogRepository _catalog;
late PurchasingRepository _purchasing;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_configured) return;
    _client = SupabaseClient(_url, _publishableKey);
    _catalog = CatalogRepository(_client);
    _purchasing = PurchasingRepository(_client);
    final response = await _client.auth.signInWithPassword(
      email: _email,
      password: _password,
    );
    expect(response.user, isNotNull);
  });

  tearDownAll(() async {
    if (_configured) await _client.auth.signOut();
  });

  testWidgets('auth signs in and exposes the authenticated user', (
    tester,
  ) async {
    expect(_client.auth.currentSession, isNotNull);
    expect(_client.auth.currentUser?.email, _email);
    await _client.auth.refreshSession();
    expect(_client.auth.currentUser?.id, isNotEmpty);
  }, skip: !_configured);

  testWidgets('products load through the production catalog repository', (
    tester,
  ) async {
    final snapshot = await _catalog.fetchSnapshot(_businessId);
    expect(
      snapshot.products,
      isNotEmpty,
      reason: 'Configure a business with at least one active product.',
    );
    expect(
      snapshot.products.every((product) => product.variantId.isNotEmpty),
      isTrue,
    );
  }, skip: !_configured);

  testWidgets('sales history loads through the production catalog repository', (
    tester,
  ) async {
    final sales = await _catalog.fetchSales(_businessId);
    expect(sales, isA<List<SaleSummary>>());
    expect(sales.every((sale) => sale.id.isNotEmpty), isTrue);
  }, skip: !_configured);

  testWidgets('returns can resolve returnable items for a fixture sale', (
    tester,
  ) async {
    final items = await _catalog.fetchReturnableSaleItems(_saleId);
    expect(items, isA<List<ReturnableSaleItem>>());
    expect(items.every((item) => item.id.isNotEmpty), isTrue);
  }, skip: !_returnFixtureConfigured);

  testWidgets(
    'suppliers and purchase orders load through purchasing repository',
    (tester) async {
      final suppliers = await _purchasing.fetchSuppliers(_businessId);
      final orders = await _purchasing.fetchOrders(_businessId);
      expect(suppliers, isA<List<Supplier>>());
      expect(orders, isA<List<PurchaseOrder>>());
      expect(suppliers.every((supplier) => supplier.id.isNotEmpty), isTrue);
      expect(orders.every((order) => order.id.isNotEmpty), isTrue);
    },
    skip: !_configured,
  );

  testWidgets(
    'two authenticated sessions can read their own tenants concurrently',
    (tester) async {
      final second = SupabaseClient(_url, _publishableKey);
      await Future.wait([
        second.auth.signInWithPassword(
          email: _secondEmail,
          password: _secondPassword,
        ),
        _client.auth.refreshSession(),
      ]);
      expect(second.auth.currentUser?.id, isNot(_client.auth.currentUser?.id));

      final reads = await Future.wait([
        _client
            .from('businesses')
            .select('id')
            .eq('id', _businessId)
            .maybeSingle(),
        second
            .from('businesses')
            .select('id')
            .eq('id', _secondBusinessId)
            .maybeSingle(),
      ]);
      expect(reads[0], isNotNull);
      expect(reads[1], isNotNull);
      await second.auth.signOut();
    },
    skip: !_concurrentConfigured,
  );
}
