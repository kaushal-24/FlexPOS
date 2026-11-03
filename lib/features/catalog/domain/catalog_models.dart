class CatalogOption {
  const CatalogOption({
    required this.id,
    required this.name,
    this.symbol,
    this.precision = 0,
  });

  factory CatalogOption.fromJson(Map<String, dynamic> json) => CatalogOption(
    id: json['id'] as String,
    name: json['name'] as String,
    symbol: json['symbol'] as String?,
    precision: (json['precision'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final String? symbol;
  final int precision;
}

class WarehouseOption extends CatalogOption {
  const WarehouseOption({
    required super.id,
    required super.name,
    required this.branchId,
  });

  factory WarehouseOption.fromJson(Map<String, dynamic> json) =>
      WarehouseOption(
        id: json['id'] as String,
        name: json['name'] as String,
        branchId: json['branch_id'] as String,
      );

  final String branchId;
}

class RegisterOption extends CatalogOption {
  const RegisterOption({
    required super.id,
    required super.name,
    required this.branchId,
  });

  factory RegisterOption.fromJson(Map<String, dynamic> json) => RegisterOption(
    id: json['id'] as String,
    name: json['name'] as String,
    branchId: json['branch_id'] as String,
  );

  final String branchId;
}

class TaxRateOption extends CatalogOption {
  const TaxRateOption({
    required super.id,
    required super.name,
    required this.rateBasisPoints,
    this.isInclusive = false,
  });

  factory TaxRateOption.fromJson(Map<String, dynamic> json) => TaxRateOption(
    id: json['id'] as String,
    name: json['name'] as String,
    rateBasisPoints: _basisPoints(json['rate']),
    isInclusive: json['is_inclusive'] as bool? ?? false,
  );

  final int rateBasisPoints;
  final bool isInclusive;
}

class CatalogProduct {
  const CatalogProduct({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.variantName,
    required this.sku,
    required this.priceMinor,
    required this.costMinor,
    required this.taxRateBasisPoints,
    required this.trackInventory,
    required this.allowFractionalQuantity,
    required this.barcodes,
    this.trackingMode = 'none',
    this.productType = 'goods',
    this.imagePath,
    this.attributes = const {},
    this.categoryId,
    this.categoryName,
    this.isFavorite = false,
    this.taxInclusive = false,
  });

  factory CatalogProduct.fromJson(Map<String, dynamic> json) {
    final product = Map<String, dynamic>.from(json['products'] as Map);
    final tax = product['tax_rates'] == null
        ? null
        : Map<String, dynamic>.from(product['tax_rates'] as Map);
    final category = product['categories'] == null
        ? null
        : Map<String, dynamic>.from(product['categories'] as Map);
    return CatalogProduct(
      productId: product['id'] as String,
      variantId: json['id'] as String,
      name: product['name'] as String,
      variantName: json['name'] as String,
      sku: json['sku'] as String,
      priceMinor: _minorUnits(json['selling_price']),
      costMinor: _minorUnits(json['cost_price']),
      taxRateBasisPoints: tax == null ? 0 : _basisPoints(tax['rate']),
      taxInclusive: tax?['is_inclusive'] as bool? ?? false,
      trackInventory: product['track_inventory'] as bool? ?? true,
      allowFractionalQuantity:
          product['allow_fractional_quantity'] as bool? ?? false,
      trackingMode: json['tracking_mode'] as String? ?? 'none',
      productType: product['product_type'] as String? ?? 'goods',
      imagePath: product['image_path'] as String?,
      attributes: _attributes(product['attributes']),
      categoryId: category?['id'] as String?,
      categoryName: category?['name'] as String?,
      isFavorite: product['is_favorite'] as bool? ?? false,
      barcodes: (json['product_barcodes'] as List? ?? const [])
          .map(
            (value) =>
                Map<String, dynamic>.from(value as Map)['barcode'] as String,
          )
          .toList(growable: false),
    );
  }

  final String productId;
  final String variantId;
  final String name;
  final String variantName;
  final String sku;
  final int priceMinor;
  final int costMinor;
  final int taxRateBasisPoints;

  /// Whether [priceMinor] is a gross shelf price that already includes tax.
  final bool taxInclusive;
  final bool trackInventory;
  final bool allowFractionalQuantity;
  final String trackingMode;
  final String productType;
  final String? imagePath;
  final Map<String, String> attributes;
  final String? categoryId;
  final String? categoryName;
  final bool isFavorite;
  final List<String> barcodes;

  /// The tax-exclusive unit price sent to authoritative pricing RPCs.
  ///
  /// The catalog and POS continue to display [priceMinor] so cashiers see the
  /// shelf price. Inclusive prices are split into net and tax using integer
  /// minor-unit rounding before they are used for totals or persisted sales.
  int get salePriceMinor {
    if (!taxInclusive || taxRateBasisPoints <= 0) return priceMinor;
    return priceMinor - taxInclusiveTaxMinor;
  }

  /// The embedded tax for one gross-priced unit, rounded to cents.
  int get taxInclusiveTaxMinor {
    if (!taxInclusive || taxRateBasisPoints <= 0) return 0;
    return taxInclusiveTaxMinorForQuantity(1);
  }

  int taxInclusiveTaxMinorForQuantity(int quantity) {
    if (quantity <= 0 || !taxInclusive || taxRateBasisPoints <= 0) return 0;
    return ((priceMinor * quantity * taxRateBasisPoints) /
            (10000 + taxRateBasisPoints))
        .round();
  }

  /// The exact cent-rounded net amount accepted by the sale RPC.
  ///
  /// Four decimal places are retained for inclusive prices so the database
  /// can reproduce a gross shelf total without a one-cent drift caused by
  /// rounding the net unit price before calculating tax.
  String get salePriceForRpc {
    if (!taxInclusive || taxRateBasisPoints <= 0) {
      return (priceMinor / 100).toStringAsFixed(2);
    }
    final denominator = 10000 + taxRateBasisPoints;
    final scaled =
        ((priceMinor * 100 * 10000) + (denominator ~/ 2)) ~/ denominator;
    final whole = scaled ~/ 10000;
    final fraction = (scaled % 10000).toString().padLeft(4, '0');
    return '$whole.$fraction';
  }

  CatalogProduct copyWith({int? priceMinor}) => CatalogProduct(
    productId: productId,
    variantId: variantId,
    name: name,
    variantName: variantName,
    sku: sku,
    priceMinor: priceMinor ?? this.priceMinor,
    costMinor: costMinor,
    taxRateBasisPoints: taxRateBasisPoints,
    taxInclusive: taxInclusive,
    trackInventory: trackInventory,
    allowFractionalQuantity: allowFractionalQuantity,
    trackingMode: trackingMode,
    productType: productType,
    imagePath: imagePath,
    attributes: attributes,
    categoryId: categoryId,
    categoryName: categoryName,
    isFavorite: isFavorite,
    barcodes: barcodes,
  );

  String get searchText =>
      '$name $variantName $sku ${categoryName ?? ''} ${barcodes.join(' ')}'
          .toLowerCase();
}

class UnitConversion {
  const UnitConversion({
    required this.id,
    required this.fromUnitId,
    required this.toUnitId,
    required this.multiplier,
  });

  factory UnitConversion.fromJson(Map<String, dynamic> json) => UnitConversion(
    id: json['id'] as String,
    fromUnitId: json['from_unit_id'] as String,
    toUnitId: json['to_unit_id'] as String,
    multiplier: _decimal(json['multiplier']),
  );

  final String id;
  final String fromUnitId;
  final String toUnitId;
  final double multiplier;
}

class BundleComponent {
  const BundleComponent({
    required this.id,
    required this.bundleVariantId,
    required this.componentVariantId,
    required this.quantity,
  });

  factory BundleComponent.fromJson(Map<String, dynamic> json) =>
      BundleComponent(
        id: json['id'] as String,
        bundleVariantId: json['bundle_variant_id'] as String,
        componentVariantId: json['component_variant_id'] as String,
        quantity: _decimal(json['quantity']),
      );

  final String id;
  final String bundleVariantId;
  final String componentVariantId;
  final double quantity;
}

class CatalogPrice {
  const CatalogPrice({
    required this.variantId,
    required this.amountMinor,
    required this.priceType,
    this.branchId,
    this.customerGroupId,
    this.customerId,
    this.minimumQuantity = 1,
    this.validFrom,
    this.validTo,
  });

  factory CatalogPrice.fromJson(Map<String, dynamic> json) => CatalogPrice(
    variantId: json['variant_id'] as String,
    amountMinor: _minorUnits(json['amount']),
    priceType: json['price_type'] as String? ?? 'retail',
    branchId: json['branch_id'] as String?,
    customerGroupId: json['customer_group_id'] as String?,
    customerId: json['customer_id'] as String?,
    minimumQuantity: _decimal(json['minimum_quantity']),
    validFrom: _dateTime(json['valid_from']),
    validTo: _dateTime(json['valid_to']),
  );

  final String variantId;
  final int amountMinor;
  final String priceType;
  final String? branchId;
  final String? customerGroupId;
  final String? customerId;
  final double minimumQuantity;
  final DateTime? validFrom;
  final DateTime? validTo;

  bool isActiveAt(DateTime now) =>
      (validFrom == null || !now.isBefore(validFrom!)) &&
      (validTo == null || now.isBefore(validTo!));
}

class StockBalance {
  const StockBalance({
    required this.variantId,
    required this.warehouseId,
    required this.quantity,
    required this.reserved,
    required this.reorderPoint,
  });

  factory StockBalance.fromJson(Map<String, dynamic> json) => StockBalance(
    variantId: json['variant_id'] as String,
    warehouseId: json['warehouse_id'] as String,
    quantity: _decimal(json['quantity_on_hand']),
    reserved: _decimal(json['quantity_reserved']),
    reorderPoint: _decimal(json['reorder_point']),
  );

  final String variantId;
  final String warehouseId;
  final double quantity;
  final double reserved;
  final double reorderPoint;
}

class CatalogSnapshot {
  const CatalogSnapshot({
    required this.units,
    required this.categories,
    required this.brands,
    required this.taxRates,
    required this.warehouses,
    required this.registers,
    required this.products,
    required this.balances,
    this.prices = const [],
    this.unitConversions = const [],
    this.bundleComponents = const [],
  });

  static const empty = CatalogSnapshot(
    units: [],
    categories: [],
    brands: [],
    taxRates: [],
    warehouses: [],
    registers: [],
    products: [],
    balances: [],
    prices: [],
    unitConversions: [],
    bundleComponents: [],
  );

  final List<CatalogOption> units;
  final List<CatalogOption> categories;
  final List<CatalogOption> brands;
  final List<TaxRateOption> taxRates;
  final List<WarehouseOption> warehouses;
  final List<RegisterOption> registers;
  final List<CatalogProduct> products;
  final List<StockBalance> balances;
  final List<CatalogPrice> prices;
  final List<UnitConversion> unitConversions;
  final List<BundleComponent> bundleComponents;

  CatalogSnapshot withEffectivePrices({
    required String? customerGroupId,
    String? customerId,
    required String branchId,
  }) {
    final now = DateTime.now().toUtc();
    final effectiveProducts = products
        .map((product) {
          final directCandidates = prices.where(
            (price) =>
                price.variantId == product.variantId &&
                price.priceType == 'customer' &&
                price.customerId == customerId &&
                (price.branchId == null || price.branchId == branchId) &&
                price.minimumQuantity <= 1 &&
                price.isActiveAt(now),
          );
          final candidates = prices.where(
            (price) =>
                price.variantId == product.variantId &&
                price.priceType == 'customer_group' &&
                price.customerGroupId == customerGroupId &&
                (price.branchId == null || price.branchId == branchId) &&
                price.minimumQuantity <= 1 &&
                price.isActiveAt(now),
          );
          final groupSelected = candidates.isEmpty
              ? null
              : candidates.reduce((current, candidate) {
                  final currentBranch = current.branchId == branchId ? 1 : 0;
                  final candidateBranch = candidate.branchId == branchId
                      ? 1
                      : 0;
                  if (candidateBranch != currentBranch) {
                    return candidateBranch > currentBranch
                        ? candidate
                        : current;
                  }
                  final currentStart =
                      current.validFrom?.millisecondsSinceEpoch ?? 0;
                  final candidateStart =
                      candidate.validFrom?.millisecondsSinceEpoch ?? 0;
                  return candidateStart >= currentStart ? candidate : current;
                });
          final selected = directCandidates.isEmpty
              ? groupSelected
              : directCandidates.reduce((current, candidate) {
                  final currentBranch = current.branchId == branchId ? 1 : 0;
                  final candidateBranch = candidate.branchId == branchId
                      ? 1
                      : 0;
                  if (candidateBranch != currentBranch) {
                    return candidateBranch > currentBranch
                        ? candidate
                        : current;
                  }
                  final currentStart =
                      current.validFrom?.millisecondsSinceEpoch ?? 0;
                  final candidateStart =
                      candidate.validFrom?.millisecondsSinceEpoch ?? 0;
                  return candidateStart >= currentStart ? candidate : current;
                });
          return selected == null
              ? product
              : product.copyWith(priceMinor: selected.amountMinor);
        })
        .toList(growable: false);
    return CatalogSnapshot(
      units: units,
      categories: categories,
      brands: brands,
      taxRates: taxRates,
      warehouses: warehouses,
      registers: registers,
      products: effectiveProducts,
      balances: balances,
      prices: prices,
      unitConversions: unitConversions,
      bundleComponents: bundleComponents,
    );
  }

  double stockFor(String variantId) => balances
      .where((balance) => balance.variantId == variantId)
      .fold(0, (total, balance) => total + balance.quantity - balance.reserved);

  double stockForWarehouse(String variantId, String warehouseId) => balances
      .where(
        (balance) =>
            balance.variantId == variantId &&
            balance.warehouseId == warehouseId,
      )
      .fold(0, (total, balance) => total + balance.quantity - balance.reserved);

  /// Returns the configured low-stock threshold across all warehouses for a SKU.
  /// Thresholds are stored per warehouse; this aggregate mirrors the total
  /// available stock shown on the inventory list.
  double reorderPointFor(String variantId) => balances
      .where((balance) => balance.variantId == variantId)
      .fold(0, (total, balance) => total + balance.reorderPoint);

  /// Selects the warehouse that actually contains the most usable stock.
  ///
  /// Warehouse rows are business-scoped and may include empty branch
  /// locations (for example, a newly-created backroom). Using the first row
  /// alphabetically therefore makes a stocked SKU appear as zero in POS and
  /// exchange/purchase dialogs. Callers can optionally pass a branch or a
  /// variant to keep the choice local to their workflow.
  WarehouseOption? bestWarehouse({
    Iterable<WarehouseOption>? candidates,
    String? preferredBranchId,
    String? variantId,
  }) {
    final available = (candidates ?? warehouses).toList(growable: false);
    if (available.isEmpty) return null;
    final branchCandidates = preferredBranchId == null
        ? available
        : available
              .where((warehouse) => warehouse.branchId == preferredBranchId)
              .toList(growable: false);
    final ranked = (branchCandidates.isEmpty ? available : branchCandidates)
        .toList(growable: true);

    double usable(WarehouseOption warehouse) {
      if (variantId != null) {
        return stockForWarehouse(variantId, warehouse.id);
      }
      return products.fold(
        0.0,
        (total, product) =>
            total +
            (product.trackInventory
                ? stockForWarehouse(product.variantId, warehouse.id)
                : 0),
      );
    }

    int coverage(WarehouseOption warehouse) {
      if (variantId != null) return usable(warehouse) > 0 ? 1 : 0;
      return products.fold(
        0,
        (count, product) =>
            count +
            (product.trackInventory &&
                    stockForWarehouse(product.variantId, warehouse.id) > 0
                ? 1
                : 0),
      );
    }

    ranked.sort((left, right) {
      final coverageComparison = coverage(right).compareTo(coverage(left));
      if (coverageComparison != 0) return coverageComparison;
      final usableComparison = usable(right).compareTo(usable(left));
      if (usableComparison != 0) return usableComparison;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return ranked.first;
  }
}

DateTime? _dateTime(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : DateTime.tryParse(text)?.toUtc();
}

class HeldPosCartItem {
  const HeldPosCartItem({required this.variantId, required this.quantity});

  factory HeldPosCartItem.fromJson(Map<String, dynamic> json) =>
      HeldPosCartItem(
        variantId: json['variant_id'] as String,
        quantity: _decimal(json['quantity']).round(),
      );

  final String variantId;
  final int quantity;
}

class HeldPosCart {
  const HeldPosCart({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.warehouseId,
    required this.label,
    required this.paymentMethod,
    required this.orderDiscountMinor,
    required this.items,
    required this.updatedAt,
    this.customerId,
  });

  factory HeldPosCart.fromJson(Map<String, dynamic> json) => HeldPosCart(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    branchId: json['branch_id'] as String,
    warehouseId: json['warehouse_id'] as String,
    customerId: json['customer_id'] as String?,
    label: json['label'] as String,
    paymentMethod: json['payment_method'] as String,
    orderDiscountMinor: _minorUnits(json['order_discount']),
    items: (json['held_pos_cart_items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => HeldPosCartItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String businessId;
  final String branchId;
  final String warehouseId;
  final String? customerId;
  final String label;
  final String paymentMethod;
  final int orderDiscountMinor;
  final List<HeldPosCartItem> items;
  final DateTime updatedAt;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  Map<String, int> get quantitiesByVariant => {
    for (final item in items) item.variantId: item.quantity,
  };
}

class PosDraftItem {
  const PosDraftItem({required this.variantId, required this.quantity});

  factory PosDraftItem.fromJson(Map<String, dynamic> json) => PosDraftItem(
    variantId: json['variant_id'] as String,
    quantity: _decimal(json['quantity']).round(),
  );

  final String variantId;
  final int quantity;
}

class PosDraft {
  const PosDraft({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.warehouseId,
    required this.title,
    required this.paymentMethod,
    required this.orderDiscountMinor,
    required this.items,
    required this.updatedAt,
    this.customerId,
  });

  factory PosDraft.fromJson(Map<String, dynamic> json) => PosDraft(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    branchId: json['branch_id'] as String,
    warehouseId: json['warehouse_id'] as String,
    customerId: json['customer_id'] as String?,
    title: json['title'] as String,
    paymentMethod: json['payment_method'] as String,
    orderDiscountMinor: _minorUnits(json['order_discount']),
    items: (json['pos_draft_items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => PosDraftItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String businessId;
  final String branchId;
  final String warehouseId;
  final String? customerId;
  final String title;
  final String paymentMethod;
  final int orderDiscountMinor;
  final List<PosDraftItem> items;
  final DateTime updatedAt;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  Map<String, int> get quantitiesByVariant => {
    for (final item in items) item.variantId: item.quantity,
  };
}

class SalesQuoteItem {
  const SalesQuoteItem({
    required this.variantId,
    required this.quantity,
    required this.unitPriceMinor,
    required this.taxRateBasisPoints,
    required this.discountMinor,
    required this.lineTotalMinor,
  });

  factory SalesQuoteItem.fromJson(Map<String, dynamic> json) => SalesQuoteItem(
    variantId: json['variant_id'] as String,
    quantity: _decimal(json['quantity']).round(),
    unitPriceMinor: _minorUnits(json['unit_price']),
    taxRateBasisPoints: _basisPoints(json['tax_rate']),
    discountMinor: _minorUnits(json['discount_amount']),
    lineTotalMinor: _minorUnits(json['line_total']),
  );

  final String variantId;
  final int quantity;
  final int unitPriceMinor;
  final int taxRateBasisPoints;
  final int discountMinor;
  final int lineTotalMinor;
}

class SalesQuote {
  const SalesQuote({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.warehouseId,
    required this.quoteNumber,
    required this.title,
    required this.status,
    required this.validUntil,
    required this.subtotalMinor,
    required this.discountTotalMinor,
    required this.taxTotalMinor,
    required this.grandTotalMinor,
    required this.items,
    required this.updatedAt,
    this.customerId,
  });

  factory SalesQuote.fromJson(Map<String, dynamic> json) => SalesQuote(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    branchId: json['branch_id'] as String,
    warehouseId: json['warehouse_id'] as String,
    customerId: json['customer_id'] as String?,
    quoteNumber: json['quote_number'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    validUntil: DateTime.parse(json['valid_until'] as String),
    subtotalMinor: _minorUnits(json['subtotal']),
    discountTotalMinor: _minorUnits(json['discount_total']),
    taxTotalMinor: _minorUnits(json['tax_total']),
    grandTotalMinor: _minorUnits(json['grand_total']),
    items: (json['sales_quote_items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SalesQuoteItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String businessId;
  final String branchId;
  final String warehouseId;
  final String? customerId;
  final String quoteNumber;
  final String title;
  final String status;
  final DateTime validUntil;
  final int subtotalMinor;
  final int discountTotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;
  final List<SalesQuoteItem> items;
  final DateTime updatedAt;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  Map<String, int> get quantitiesByVariant => {
    for (final item in items) item.variantId: item.quantity,
  };

  bool get isExpired {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(validUntil.year, validUntil.month, validUntil.day);
    return expiry.isBefore(today);
  }
}

class SalesOrderItem {
  const SalesOrderItem({
    required this.variantId,
    required this.quantity,
    required this.reservedQuantity,
    required this.trackInventory,
    required this.unitPriceMinor,
    required this.taxRateBasisPoints,
    required this.discountMinor,
    required this.lineTotalMinor,
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) => SalesOrderItem(
    variantId: json['variant_id'] as String,
    quantity: _decimal(json['quantity']).round(),
    reservedQuantity: _decimal(json['reserved_quantity']).round(),
    trackInventory: json['track_inventory'] as bool? ?? false,
    unitPriceMinor: _minorUnits(json['unit_price']),
    taxRateBasisPoints: _basisPoints(json['tax_rate']),
    discountMinor: _minorUnits(json['discount_amount']),
    lineTotalMinor: _minorUnits(json['line_total']),
  );

  final String variantId;
  final int quantity;
  final int reservedQuantity;
  final bool trackInventory;
  final int unitPriceMinor;
  final int taxRateBasisPoints;
  final int discountMinor;
  final int lineTotalMinor;
}

class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.warehouseId,
    required this.orderNumber,
    required this.title,
    required this.status,
    required this.requestedDeliveryOn,
    required this.subtotalMinor,
    required this.orderDiscountMinor,
    required this.discountTotalMinor,
    required this.taxTotalMinor,
    required this.grandTotalMinor,
    required this.items,
    required this.updatedAt,
    this.customerId,
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) => SalesOrder(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    branchId: json['branch_id'] as String,
    warehouseId: json['warehouse_id'] as String,
    customerId: json['customer_id'] as String?,
    orderNumber: json['order_number'] as String,
    title: json['title'] as String,
    status: json['status'] as String,
    requestedDeliveryOn: DateTime.parse(
      json['requested_delivery_on'] as String,
    ),
    subtotalMinor: _minorUnits(json['subtotal']),
    orderDiscountMinor: _minorUnits(json['order_discount']),
    discountTotalMinor: _minorUnits(json['discount_total']),
    taxTotalMinor: _minorUnits(json['tax_total']),
    grandTotalMinor: _minorUnits(json['grand_total']),
    items: (json['sales_order_items'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => SalesOrderItem.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String id;
  final String businessId;
  final String branchId;
  final String warehouseId;
  final String? customerId;
  final String orderNumber;
  final String title;
  final String status;
  final DateTime requestedDeliveryOn;
  final int subtotalMinor;
  final int orderDiscountMinor;
  final int discountTotalMinor;
  final int taxTotalMinor;
  final int grandTotalMinor;
  final List<SalesOrderItem> items;
  final DateTime updatedAt;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  Map<String, int> get quantitiesByVariant => {
    for (final item in items) item.variantId: item.quantity,
  };

  Map<String, int> get reservedByVariant => {
    for (final item in items)
      if (item.reservedQuantity > 0) item.variantId: item.reservedQuantity,
  };

  bool get isOverdue {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final delivery = DateTime(
      requestedDeliveryOn.year,
      requestedDeliveryOn.month,
      requestedDeliveryOn.day,
    );
    return delivery.isBefore(today);
  }
}

class GiftCardDetails {
  const GiftCardDetails({
    required this.id,
    required this.lastFour,
    required this.balanceMinor,
    required this.currencyCode,
    required this.status,
    this.expiresAt,
    this.customerId,
  });

  factory GiftCardDetails.fromJson(Map<String, dynamic> json) =>
      GiftCardDetails(
        id: json['gift_card_id'] as String,
        lastFour: json['last_four'] as String,
        balanceMinor: _minorUnits(json['balance']),
        currencyCode: json['currency_code'] as String,
        status: json['status'] as String,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toLocal(),
        customerId: json['customer_id'] as String?,
      );

  final String id;
  final String lastFour;
  final int balanceMinor;
  final String currencyCode;
  final String status;
  final DateTime? expiresAt;
  final String? customerId;

  bool get isActive => status == 'active' && balanceMinor > 0;
}

class IssuedGiftCard {
  const IssuedGiftCard({
    required this.id,
    required this.number,
    required this.balanceMinor,
    required this.currencyCode,
    this.expiresAt,
    this.customerId,
  });

  factory IssuedGiftCard.fromJson(Map<String, dynamic> json) => IssuedGiftCard(
    id: json['gift_card_id'] as String,
    number: json['gift_card_number'] as String,
    balanceMinor: _minorUnits(json['balance']),
    currencyCode: json['currency_code'] as String,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String).toLocal(),
    customerId: json['customer_id'] as String?,
  );

  final String id;
  final String number;
  final int balanceMinor;
  final String currencyCode;
  final DateTime? expiresAt;
  final String? customerId;
}

class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.branchId,
    required this.customerId,
    required this.notes,
    required this.invoiceNumber,
    required this.grandTotalMinor,
    required this.paymentStatus,
    required this.status,
    required this.refundedTotalMinor,
    required this.creditNotes,
    required this.payments,
    required this.completedAt,
  });

  factory SaleSummary.fromJson(Map<String, dynamic> json) {
    final returns = (json['sale_returns'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => _minorUnits(row['refund_total']))
        .fold(0, (total, value) => total + value);
    return SaleSummary(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      customerId: json['customer_id'] as String?,
      notes: json['notes'] as String?,
      invoiceNumber: json['invoice_number'] as String,
      grandTotalMinor: _minorUnits(json['grand_total']),
      paymentStatus: json['payment_status'] as String,
      status: json['status'] as String,
      refundedTotalMinor: returns,
      creditNotes: (json['credit_notes'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (row) => CreditNoteSummary.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false),
      payments: (json['payments'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => PaymentSummary.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
      completedAt: DateTime.parse(json['completed_at'] as String).toLocal(),
    );
  }

  final String id;
  final String branchId;
  final String? customerId;
  final String? notes;
  final String invoiceNumber;
  final int grandTotalMinor;
  final String paymentStatus;
  final String status;
  final int refundedTotalMinor;
  final List<CreditNoteSummary> creditNotes;
  final List<PaymentSummary> payments;
  final DateTime completedAt;

  bool get canReturn => status == 'completed' || status == 'partially_refunded';
  int get netTotalMinor => grandTotalMinor - refundedTotalMinor;
  List<PaymentSummary> get pendingExternalPayments => payments
      .where((payment) => payment.isExternal && payment.status == 'pending')
      .toList(growable: false);
}

class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.method,
    required this.status,
    required this.amountMinor,
    required this.createdAt,
    this.reference,
    this.provider,
  });

  factory PaymentSummary.fromJson(Map<String, dynamic> json) => PaymentSummary(
    id: json['id'] as String,
    method: json['payment_method'] as String,
    status: json['status'] as String,
    amountMinor: _minorUnits(json['amount']),
    reference: _optionalString(json['reference']),
    provider: _optionalString(json['provider']),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String method;
  final String status;
  final int amountMinor;
  final String? reference;
  final String? provider;
  final DateTime createdAt;

  bool get isExternal => const {
    'upi',
    'razorpay',
    'card',
    'bank_transfer',
    'wallet',
  }.contains(method);

  String get methodLabel => provider == 'razorpay_upi'
      ? 'Razorpay'
      : switch (method) {
          'upi' => 'UPI',
          'razorpay' => 'Razorpay',
          'card' => 'Card',
          'bank_transfer' => 'Bank transfer',
          'wallet' => 'Wallet',
          'gift_card' => 'Gift card',
          'customer_credit' => 'Customer credit',
          'credit_note' => 'Credit note',
          _ => 'Cash',
        };
}

class CreditNoteSummary {
  const CreditNoteSummary({
    required this.id,
    required this.number,
    required this.issuedAmountMinor,
    required this.redeemedAmountMinor,
    required this.expiresAt,
  });

  factory CreditNoteSummary.fromJson(Map<String, dynamic> json) {
    final redeemed = (json['credit_note_redemptions'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => _minorUnits(row['amount']))
        .fold(0, (total, value) => total + value);
    return CreditNoteSummary(
      id: json['id'] as String,
      number: json['credit_note_number'] as String,
      issuedAmountMinor: _minorUnits(json['issued_amount']),
      redeemedAmountMinor: redeemed,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }

  final String id;
  final String number;
  final int issuedAmountMinor;
  final int redeemedAmountMinor;
  final DateTime expiresAt;

  int get availableAmountMinor => issuedAmountMinor - redeemedAmountMinor;
  bool get isRedeemed => availableAmountMinor <= 0;
  bool get isExpired => !DateTime.now().isBefore(expiresAt);
}

enum SaleHistoryStatusFilter {
  all('All statuses'),
  paid('Paid'),
  pending('Pending'),
  partiallyRefunded('Partially refunded'),
  refunded('Refunded');

  const SaleHistoryStatusFilter(this.label);

  final String label;
}

class SaleHistoryFilter {
  const SaleHistoryFilter({
    required this.businessId,
    this.search = '',
    this.status = SaleHistoryStatusFilter.all,
    this.from,
    this.through,
  });

  final String businessId;
  final String search;
  final SaleHistoryStatusFilter status;
  final DateTime? from;
  final DateTime? through;

  bool get isActive =>
      search.trim().isNotEmpty ||
      status != SaleHistoryStatusFilter.all ||
      from != null ||
      through != null;

  DateTime? get fromInclusiveUtc => from == null
      ? null
      : DateTime(from!.year, from!.month, from!.day).toUtc();

  DateTime? get throughExclusiveUtc => through == null
      ? null
      : DateTime(through!.year, through!.month, through!.day + 1).toUtc();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleHistoryFilter &&
          businessId == other.businessId &&
          search == other.search &&
          status == other.status &&
          from == other.from &&
          through == other.through;

  @override
  int get hashCode => Object.hash(businessId, search, status, from, through);
}

class ReturnableSaleItem {
  const ReturnableSaleItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.soldQuantity,
    required this.returnedQuantity,
    required this.lineTotalMinor,
  });

  factory ReturnableSaleItem.fromJson(
    Map<String, dynamic> json,
    double returnedQuantity,
  ) => ReturnableSaleItem(
    id: json['id'] as String,
    productName: json['product_name'] as String,
    variantName: json['variant_name'] as String,
    sku: json['sku'] as String,
    soldQuantity: _decimal(json['quantity']),
    returnedQuantity: returnedQuantity,
    lineTotalMinor: _minorUnits(json['line_total']),
  );

  final String id;
  final String productName;
  final String variantName;
  final String sku;
  final double soldQuantity;
  final double returnedQuantity;
  final int lineTotalMinor;

  double get remainingQuantity => soldQuantity - returnedQuantity;
}

class SerializedSaleReturnUnit {
  const SerializedSaleReturnUnit({
    required this.id,
    required this.saleItemId,
    required this.identifier,
    required this.trackingMode,
    required this.status,
  });

  factory SerializedSaleReturnUnit.fromJson(Map<String, dynamic> json) =>
      SerializedSaleReturnUnit(
        id: json['id'] as String,
        saleItemId: json['sale_item_id'] as String,
        identifier: json['identifier'] as String,
        trackingMode: json['tracking_mode'] as String,
        status: json['status'] as String,
      );

  final String id;
  final String saleItemId;
  final String identifier;
  final String trackingMode;
  final String status;
}

int _minorUnits(Object? value) => (_decimal(value) * 100).round();
int _basisPoints(Object? value) => (_decimal(value) * 100).round();
String? _optionalString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

Map<String, String> _attributes(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key.toString().trim().isNotEmpty &&
          entry.value != null &&
          entry.value.toString().trim().isNotEmpty)
        entry.key.toString().trim(): entry.value.toString().trim(),
  };
}

double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
