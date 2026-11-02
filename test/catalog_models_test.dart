import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog product converts money and tax to integer units', () {
    final product = CatalogProduct.fromJson({
      'id': 'variant-1',
      'name': 'Default',
      'sku': 'COFFEE-1',
      'cost_price': '25.50',
      'selling_price': '40.00',
      'product_barcodes': [
        {'barcode': '890000000001'},
      ],
      'products': {
        'id': 'product-1',
        'name': 'Coffee',
        'track_inventory': true,
        'allow_fractional_quantity': false,
        'is_favorite': true,
        'categories': {'id': 'category-1', 'name': 'Drinks'},
        'tax_rates': {'rate': '18.0000'},
      },
    });

    expect(product.costMinor, 2550);
    expect(product.priceMinor, 4000);
    expect(product.taxRateBasisPoints, 1800);
    expect(product.taxInclusive, isFalse);
    expect(product.categoryId, 'category-1');
    expect(product.categoryName, 'Drinks');
    expect(product.isFavorite, isTrue);
    expect(product.searchText, contains('890000000001'));
    expect(product.searchText, contains('drinks'));
  });

  test(
    'tax-inclusive catalog prices expose gross display and net sale units',
    () {
      final product = CatalogProduct.fromJson({
        'id': 'variant-1',
        'name': 'Default',
        'sku': 'TAX-1',
        'cost_price': '50.00',
        'selling_price': '118.00',
        'product_barcodes': const [],
        'products': {
          'id': 'product-1',
          'name': 'Taxed item',
          'track_inventory': true,
          'allow_fractional_quantity': false,
          'tax_rates': {'rate': '18.0000', 'is_inclusive': true},
        },
      });

      expect(product.taxInclusive, isTrue);
      expect(product.priceMinor, 11800);
      expect(product.salePriceMinor, 10000);
      expect(product.salePriceForRpc, '100.0000');
    },
  );

  test('tax-inclusive repeating prices keep four-decimal RPC precision', () {
    const product = CatalogProduct(
      productId: 'product-1',
      variantId: 'variant-1',
      name: 'Taxed item',
      variantName: 'Default',
      sku: 'TAX-1',
      priceMinor: 10000,
      costMinor: 5000,
      taxRateBasisPoints: 1800,
      taxInclusive: true,
      trackInventory: true,
      allowFractionalQuantity: false,
      barcodes: [],
    );

    expect(product.salePriceMinor, 8475);
    expect(product.salePriceForRpc, '84.7458');
  });

  test('catalog product supports an exact per-line price override', () {
    const product = CatalogProduct(
      productId: 'product-1',
      variantId: 'variant-1',
      name: 'Coffee',
      variantName: 'Default',
      sku: 'COFFEE-1',
      priceMinor: 4000,
      costMinor: 2500,
      taxRateBasisPoints: 1800,
      trackInventory: true,
      allowFractionalQuantity: false,
      barcodes: [],
    );

    expect(product.copyWith(priceMinor: 3250).priceMinor, 3250);
    expect(product.copyWith().priceMinor, 4000);
  });

  test('snapshot returns available stock per warehouse', () {
    const snapshot = CatalogSnapshot(
      units: [],
      categories: [],
      brands: [],
      taxRates: [],
      warehouses: [],
      registers: [],
      products: [],
      balances: [
        StockBalance(
          variantId: 'variant-1',
          warehouseId: 'warehouse-1',
          quantity: 12,
          reserved: 2,
          reorderPoint: 1,
        ),
        StockBalance(
          variantId: 'variant-1',
          warehouseId: 'warehouse-2',
          quantity: 5,
          reserved: 1,
          reorderPoint: 1,
        ),
      ],
    );

    expect(snapshot.stockFor('variant-1'), 14);
    expect(snapshot.stockForWarehouse('variant-1', 'warehouse-1'), 10);
  });

  test('direct customer price takes precedence over group price', () {
    const product = CatalogProduct(
      productId: 'product-1',
      variantId: 'variant-1',
      name: 'Coffee',
      variantName: 'Default',
      sku: 'COFFEE-1',
      priceMinor: 4000,
      costMinor: 2500,
      taxRateBasisPoints: 1800,
      trackInventory: true,
      allowFractionalQuantity: false,
      barcodes: [],
    );
    const snapshot = CatalogSnapshot(
      units: [],
      categories: [],
      brands: [],
      taxRates: [],
      warehouses: [],
      registers: [],
      products: [product],
      balances: [],
      prices: [
        CatalogPrice(
          variantId: 'variant-1',
          amountMinor: 3500,
          priceType: 'customer_group',
          customerGroupId: 'group-1',
        ),
        CatalogPrice(
          variantId: 'variant-1',
          amountMinor: 3200,
          priceType: 'customer',
          customerId: 'customer-1',
        ),
      ],
    );

    final effective = snapshot.withEffectivePrices(
      customerGroupId: 'group-1',
      customerId: 'customer-1',
      branchId: 'branch-1',
    );

    expect(effective.products.single.priceMinor, 3200);
  });

  test('group price falls back to retail when no customer override exists', () {
    const product = CatalogProduct(
      productId: 'product-1',
      variantId: 'variant-1',
      name: 'Coffee',
      variantName: 'Default',
      sku: 'COFFEE-1',
      priceMinor: 4000,
      costMinor: 2500,
      taxRateBasisPoints: 1800,
      trackInventory: true,
      allowFractionalQuantity: false,
      barcodes: [],
    );
    const snapshot = CatalogSnapshot(
      units: [],
      categories: [],
      brands: [],
      taxRates: [],
      warehouses: [],
      registers: [],
      products: [product],
      balances: [],
      prices: [
        CatalogPrice(
          variantId: 'variant-1',
          amountMinor: 3500,
          priceType: 'customer_group',
          customerGroupId: 'group-1',
        ),
      ],
    );

    final effective = snapshot.withEffectivePrices(
      customerGroupId: null,
      customerId: 'customer-1',
      branchId: 'branch-1',
    );

    expect(effective.products.single.priceMinor, 4000);
  });

  test('held POS cart restores its persisted sale state', () {
    final cart = HeldPosCart.fromJson({
      'id': 'held-1',
      'business_id': 'business-1',
      'branch_id': 'branch-1',
      'warehouse_id': 'warehouse-1',
      'customer_id': 'customer-1',
      'label': 'Lunch counter',
      'payment_method': 'wallet',
      'order_discount': '12.50',
      'updated_at': '2026-10-22T10:30:00Z',
      'held_pos_cart_items': [
        {'variant_id': 'variant-1', 'quantity': '2.000000'},
        {'variant_id': 'variant-2', 'quantity': 3},
      ],
    });

    expect(cart.label, 'Lunch counter');
    expect(cart.customerId, 'customer-1');
    expect(cart.paymentMethod, 'wallet');
    expect(cart.orderDiscountMinor, 1250);
    expect(cart.itemCount, 5);
    expect(cart.quantitiesByVariant, {'variant-1': 2, 'variant-2': 3});
  });

  test('POS draft restores editable sale state', () {
    final draft = PosDraft.fromJson({
      'id': 'draft-1',
      'business_id': 'business-1',
      'branch_id': 'branch-1',
      'warehouse_id': 'warehouse-1',
      'customer_id': null,
      'title': 'Tomorrow order',
      'payment_method': 'cash',
      'order_discount': '5.25',
      'updated_at': '2026-10-22T11:00:00Z',
      'pos_draft_items': [
        {'variant_id': 'variant-1', 'quantity': '4.000000'},
      ],
    });

    expect(draft.title, 'Tomorrow order');
    expect(draft.customerId, isNull);
    expect(draft.orderDiscountMinor, 525);
    expect(draft.itemCount, 4);
    expect(draft.quantitiesByVariant, {'variant-1': 4});
  });

  test('sales quotation restores its commercial snapshot', () {
    final quote = SalesQuote.fromJson({
      'id': 'quote-1',
      'business_id': 'business-1',
      'branch_id': 'branch-1',
      'warehouse_id': 'warehouse-1',
      'customer_id': 'customer-1',
      'quote_number': 'QT-20261022120000-ABC12345',
      'title': 'Cafe opening order',
      'status': 'open',
      'valid_until': '2099-11-21',
      'subtotal': '400.00',
      'discount_total': '25.00',
      'tax_total': '67.50',
      'grand_total': '442.50',
      'updated_at': '2026-10-22T12:00:00Z',
      'sales_quote_items': [
        {
          'variant_id': 'variant-1',
          'quantity': '2.000000',
          'unit_price': '200.0000',
          'tax_rate': '18.0000',
          'discount_amount': '25.00',
          'line_total': '442.50',
        },
      ],
    });

    expect(quote.quoteNumber, 'QT-20261022120000-ABC12345');
    expect(quote.itemCount, 2);
    expect(quote.quantitiesByVariant, {'variant-1': 2});
    expect(quote.discountTotalMinor, 2500);
    expect(quote.taxTotalMinor, 6750);
    expect(quote.grandTotalMinor, 44250);
    expect(quote.items.single.unitPriceMinor, 20000);
    expect(quote.items.single.taxRateBasisPoints, 1800);
    expect(quote.isExpired, isFalse);
  });

  test('sales order restores its reservation and committed totals', () {
    final order = SalesOrder.fromJson({
      'id': 'order-1',
      'business_id': 'business-1',
      'branch_id': 'branch-1',
      'warehouse_id': 'warehouse-1',
      'customer_id': 'customer-1',
      'order_number': 'SO-20261022130000-ABC12345',
      'title': 'Reserved catering order',
      'status': 'open',
      'requested_delivery_on': '2099-11-21',
      'subtotal': '400.00',
      'order_discount': '25.00',
      'discount_total': '25.00',
      'tax_total': '72.00',
      'grand_total': '447.00',
      'updated_at': '2026-10-22T13:00:00Z',
      'sales_order_items': [
        {
          'variant_id': 'variant-1',
          'quantity': '2.000000',
          'reserved_quantity': '2.000000',
          'track_inventory': true,
          'unit_price': '200.0000',
          'tax_rate': '18.0000',
          'discount_amount': '0.00',
          'line_total': '472.00',
        },
      ],
    });

    expect(order.orderNumber, 'SO-20261022130000-ABC12345');
    expect(order.itemCount, 2);
    expect(order.quantitiesByVariant, {'variant-1': 2});
    expect(order.reservedByVariant, {'variant-1': 2});
    expect(order.orderDiscountMinor, 2500);
    expect(order.grandTotalMinor, 44700);
    expect(order.items.single.trackInventory, isTrue);
    expect(order.isOverdue, isFalse);
  });

  test(
    'gift-card models preserve exact balance, status, and bearer number',
    () {
      final details = GiftCardDetails.fromJson({
        'gift_card_id': 'gift-card-1',
        'last_four': 'CDEF',
        'balance': '90.25',
        'currency_code': 'INR',
        'status': 'active',
        'expires_at': '2027-10-23T18:29:59Z',
        'customer_id': 'customer-1',
      });
      final issued = IssuedGiftCard.fromJson({
        'gift_card_id': 'gift-card-1',
        'gift_card_number': 'GC-1234-5678-90AB-CDEF-1234',
        'balance': 150,
        'currency_code': 'INR',
        'expires_at': '2027-10-23T18:29:59Z',
        'customer_id': null,
      });

      expect(details.lastFour, 'CDEF');
      expect(details.balanceMinor, 9025);
      expect(details.isActive, isTrue);
      expect(details.customerId, 'customer-1');
      expect(issued.number, 'GC-1234-5678-90AB-CDEF-1234');
      expect(issued.balanceMinor, 15000);
      expect(issued.expiresAt, isNotNull);
    },
  );

  test('sale summary exposes partial refunds and exact net total', () {
    final sale = SaleSummary.fromJson({
      'id': 'sale-1',
      'branch_id': 'branch-1',
      'invoice_number': 'FP-1',
      'grand_total': '400.00',
      'payment_status': 'partially_refunded',
      'status': 'partially_refunded',
      'completed_at': '2026-10-20T10:00:00Z',
      'sale_returns': [
        {'refund_total': '75.25'},
        {'refund_total': '24.75'},
      ],
      'credit_notes': [
        {
          'id': 'credit-note-1',
          'credit_note_number': 'CN-1',
          'issued_amount': '100.00',
          'expires_at': '2027-10-20T10:00:00Z',
          'credit_note_redemptions': [
            {'amount': '35.50'},
          ],
        },
      ],
      'payments': [
        {
          'id': 'payment-1',
          'payment_method': 'upi',
          'status': 'pending',
          'amount': '125.50',
          'reference': 'UPI-1001',
          'provider': 'demo_pay',
          'created_at': '2026-10-20T10:00:00Z',
        },
        {
          'id': 'payment-2',
          'payment_method': 'cash',
          'status': 'settled',
          'amount': '274.50',
          'reference': null,
          'provider': null,
          'created_at': '2026-10-20T10:00:00Z',
        },
      ],
    });

    expect(sale.branchId, 'branch-1');
    expect(sale.refundedTotalMinor, 10000);
    expect(sale.netTotalMinor, 30000);
    expect(sale.creditNotes.single.number, 'CN-1');
    expect(sale.creditNotes.single.availableAmountMinor, 6450);
    expect(sale.payments, hasLength(2));
    expect(sale.pendingExternalPayments.single.methodLabel, 'UPI');
    expect(sale.pendingExternalPayments.single.amountMinor, 12550);
    expect(sale.pendingExternalPayments.single.provider, 'demo_pay');
    expect(sale.canReturn, isTrue);
  });

  test('payment summary identifies only reconcilable external tenders', () {
    final card = PaymentSummary.fromJson({
      'id': 'payment-card',
      'payment_method': 'card',
      'status': 'pending',
      'amount': '42.75',
      'reference': ' CARD-42 ',
      'provider': '',
      'created_at': '2026-10-23T10:00:00Z',
    });
    final giftCard = PaymentSummary.fromJson({
      'id': 'payment-gift',
      'payment_method': 'gift_card',
      'status': 'settled',
      'amount': 42.75,
      'reference': null,
      'provider': 'gift_card',
      'created_at': '2026-10-23T10:00:00Z',
    });

    expect(card.isExternal, isTrue);
    expect(card.methodLabel, 'Card');
    expect(card.amountMinor, 4275);
    expect(card.reference, 'CARD-42');
    expect(card.provider, isNull);
    expect(giftCard.isExternal, isFalse);
    expect(giftCard.methodLabel, 'Gift card');
  });

  test('sale-history filter has stable equality and inclusive local dates', () {
    final first = SaleHistoryFilter(
      businessId: 'business-1',
      search: 'FP-100',
      status: SaleHistoryStatusFilter.paid,
      from: DateTime(2026, 10, 1),
      through: DateTime(2026, 10, 20),
    );
    final same = SaleHistoryFilter(
      businessId: 'business-1',
      search: 'FP-100',
      status: SaleHistoryStatusFilter.paid,
      from: DateTime(2026, 10, 1),
      through: DateTime(2026, 10, 20),
    );

    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first.isActive, isTrue);
    expect(first.fromInclusiveUtc, DateTime(2026, 10, 1).toUtc());
    expect(first.throughExclusiveUtc, DateTime(2026, 10, 21).toUtc());
  });

  test('returnable sale item computes remaining fractional quantity', () {
    final item = ReturnableSaleItem.fromJson({
      'id': 'item-1',
      'product_name': 'Coffee beans',
      'variant_name': 'Default',
      'sku': 'COFFEE-1',
      'quantity': '2.500000',
      'line_total': '250.00',
    }, 0.75);

    expect(item.remainingQuantity, 1.75);
    expect(item.lineTotalMinor, 25000);
  });

  test('sale summary retains editable customer and note metadata', () {
    final sale = SaleSummary.fromJson({
      'id': 'sale-1',
      'branch_id': 'branch-1',
      'customer_id': 'customer-1',
      'notes': 'Deliver before noon',
      'invoice_number': 'INV-1',
      'grand_total': '150.00',
      'payment_status': 'paid',
      'status': 'completed',
      'completed_at': '2026-10-22T11:00:00Z',
      'sale_returns': const [],
      'credit_notes': const [],
      'payments': const [],
    });

    expect(sale.customerId, 'customer-1');
    expect(sale.notes, 'Deliver before noon');
  });
}
