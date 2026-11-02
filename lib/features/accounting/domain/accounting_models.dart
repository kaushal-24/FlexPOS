class ReportPeriod {
  factory ReportPeriod({required DateTime start, required DateTime end}) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError.value(end, 'end', 'Must not be before start.');
    }
    return ReportPeriod._(normalizedStart, normalizedEnd);
  }

  factory ReportPeriod.lastDays(int days, {DateTime? now}) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'Must be at least one.');
    }
    final current = now ?? DateTime.now();
    final end = DateTime(current.year, current.month, current.day);
    return ReportPeriod(
      start: end.subtract(Duration(days: days - 1)),
      end: end,
    );
  }

  const ReportPeriod._(this.start, this.end);

  final DateTime start;
  final DateTime end;

  int get dayCount => end.difference(start).inDays + 1;

  DateTime get startUtc => DateTime(start.year, start.month, start.day).toUtc();

  DateTime get endExclusiveUtc =>
      DateTime(end.year, end.month, end.day + 1).toUtc();

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class AccountingDashboard {
  const AccountingDashboard({
    required this.salesTotalMinor,
    required this.taxTotalMinor,
    required this.expensesTotalMinor,
    required this.outstandingReceivablesMinor,
    required this.orderCount,
    required this.lowStockCount,
    required this.dailySales,
    required this.paymentBreakdown,
    this.branchBreakdown = const [],
    this.employeeBreakdown = const [],
    this.productBreakdown = const [],
    this.categoryBreakdown = const [],
    this.grossProfitMinor,
    this.netProfitMinor,
    this.netProfitMargin,
  });

  factory AccountingDashboard.fromJson(Map<String, dynamic> json) {
    return AccountingDashboard(
      salesTotalMinor: _minorUnits(json['sales_total']),
      taxTotalMinor: _minorUnits(json['tax_total']),
      expensesTotalMinor: _minorUnits(json['expenses_total']),
      outstandingReceivablesMinor: _minorUnits(json['outstanding_receivables']),
      orderCount: _wholeNumber(json['order_count']),
      lowStockCount: _wholeNumber(json['low_stock_count']),
      grossProfitMinor: json['gross_profit'] == null
          ? null
          : _minorUnits(json['gross_profit']),
      netProfitMinor: json['net_profit'] == null
          ? null
          : _minorUnits(json['net_profit']),
      netProfitMargin: json['net_profit_margin'] == null
          ? null
          : _decimal(json['net_profit_margin']),
      dailySales: (json['daily_sales'] as List? ?? const [])
          .map(
            (value) => DailySalesPoint.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false),
      paymentBreakdown: (json['payment_breakdown'] as List? ?? const [])
          .map(
            (value) =>
                PaymentTotal.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList(growable: false),
      branchBreakdown: _breakdownItems(json['branch_breakdown']),
      employeeBreakdown: _breakdownItems(json['employee_breakdown']),
      productBreakdown: _breakdownItems(json['product_breakdown']),
      categoryBreakdown: _breakdownItems(json['category_breakdown']),
    );
  }

  final int salesTotalMinor;
  final int taxTotalMinor;
  final int expensesTotalMinor;
  final int outstandingReceivablesMinor;
  final int orderCount;
  final int lowStockCount;
  final int? grossProfitMinor;
  final int? netProfitMinor;
  final double? netProfitMargin;
  final List<DailySalesPoint> dailySales;
  final List<PaymentTotal> paymentBreakdown;
  final List<SalesBreakdownItem> branchBreakdown;
  final List<SalesBreakdownItem> employeeBreakdown;
  final List<SalesBreakdownItem> productBreakdown;
  final List<SalesBreakdownItem> categoryBreakdown;
}

class SalesBreakdownItem {
  const SalesBreakdownItem({
    required this.name,
    required this.totalMinor,
    this.id,
    this.orderCount = 0,
    this.quantity = 0,
  });

  factory SalesBreakdownItem.fromJson(Map<String, dynamic> json) =>
      SalesBreakdownItem(
        id: json['id'] as String?,
        name: json['name'] as String,
        totalMinor: _minorUnits(json['total']),
        orderCount: _wholeNumber(json['orders']),
        quantity: _decimal(json['quantity']),
      );

  final String? id;
  final String name;
  final int totalMinor;
  final int orderCount;
  final double quantity;
}

class InventoryValuationReport {
  const InventoryValuationReport({
    required this.totalValueMinor,
    required this.onHandQuantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.skuCount,
    required this.lowStockCount,
    required this.byWarehouse,
    required this.byCategory,
    this.valuationMethod = 'weighted_average',
    this.standardCost,
  });

  factory InventoryValuationReport.fromJson(Map<String, dynamic> json) =>
      InventoryValuationReport(
        valuationMethod: json['method'] as String? ?? 'weighted_average',
        standardCost: json['standard_cost'] == null
            ? null
            : _decimal(json['standard_cost']),
        totalValueMinor: _minorUnits(json['total_value']),
        onHandQuantity: _decimal(json['on_hand_quantity']),
        reservedQuantity: _decimal(json['reserved_quantity']),
        availableQuantity: _decimal(json['available_quantity']),
        skuCount: _wholeNumber(json['sku_count']),
        lowStockCount: _wholeNumber(json['low_stock_count']),
        byWarehouse: _valuationGroups(json['by_warehouse']),
        byCategory: _valuationGroups(json['by_category']),
      );

  final String valuationMethod;
  final double? standardCost;
  final int totalValueMinor;
  final double onHandQuantity;
  final double reservedQuantity;
  final double availableQuantity;
  final int skuCount;
  final int lowStockCount;
  final List<InventoryValuationGroup> byWarehouse;
  final List<InventoryValuationGroup> byCategory;
}

class InventoryValuationGroup {
  const InventoryValuationGroup({
    required this.name,
    required this.totalValueMinor,
    required this.onHandQuantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.skuCount,
    required this.lowStockCount,
    this.id,
  });

  factory InventoryValuationGroup.fromJson(Map<String, dynamic> json) =>
      InventoryValuationGroup(
        id: json['id'] as String?,
        name: json['name'] as String,
        totalValueMinor: _minorUnits(json['total_value']),
        onHandQuantity: _decimal(json['on_hand_quantity']),
        reservedQuantity: _decimal(json['reserved_quantity']),
        availableQuantity: _decimal(json['available_quantity']),
        skuCount: _wholeNumber(json['sku_count']),
        lowStockCount: _wholeNumber(json['low_stock_count']),
      );

  final String? id;
  final String name;
  final int totalValueMinor;
  final double onHandQuantity;
  final double reservedQuantity;
  final double availableQuantity;
  final int skuCount;
  final int lowStockCount;
}

class InventoryAgeingReport {
  const InventoryAgeingReport({
    required this.asOfDate,
    required this.method,
    required this.totalQuantity,
    required this.totalValueMinor,
    required this.trackedQuantity,
    required this.untrackedQuantity,
    required this.buckets,
    required this.byWarehouse,
    required this.byCategory,
    this.oldestAgeDays,
  });

  factory InventoryAgeingReport.fromJson(Map<String, dynamic> json) {
    final parsedBuckets = (json['buckets'] as List? ?? const [])
        .map(
          (row) => InventoryAgeBucket.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
    final bucketsByKey = {
      for (final bucket in parsedBuckets) bucket.key: bucket,
    };
    const standardBuckets = [
      ('0_30', '0-30 days'),
      ('31_60', '31-60 days'),
      ('61_90', '61-90 days'),
      ('91_180', '91-180 days'),
      ('181_plus', '181+ days'),
    ];
    return InventoryAgeingReport(
      asOfDate: DateTime.parse(json['as_of_date'] as String),
      method: json['method'] as String,
      totalQuantity: _decimal(json['total_quantity']),
      totalValueMinor: _minorUnits(json['total_value']),
      trackedQuantity: _decimal(json['tracked_quantity']),
      untrackedQuantity: _decimal(json['untracked_quantity']),
      oldestAgeDays: json['oldest_age_days'] == null
          ? null
          : _wholeNumber(json['oldest_age_days']),
      buckets: [
        for (final definition in standardBuckets)
          bucketsByKey[definition.$1] ??
              InventoryAgeBucket.empty(
                key: definition.$1,
                label: definition.$2,
              ),
        ?bucketsByKey['untracked'],
      ],
      byWarehouse: _ageingGroups(json['by_warehouse']),
      byCategory: _ageingGroups(json['by_category']),
    );
  }

  final DateTime asOfDate;
  final String method;
  final double totalQuantity;
  final int totalValueMinor;
  final double trackedQuantity;
  final double untrackedQuantity;
  final int? oldestAgeDays;
  final List<InventoryAgeBucket> buckets;
  final List<InventoryAgeingGroup> byWarehouse;
  final List<InventoryAgeingGroup> byCategory;
}

class InventoryAgeBucket {
  const InventoryAgeBucket({
    required this.key,
    required this.label,
    required this.quantity,
    required this.totalValueMinor,
    required this.skuCount,
  });

  const InventoryAgeBucket.empty({required this.key, required this.label})
    : quantity = 0,
      totalValueMinor = 0,
      skuCount = 0;

  factory InventoryAgeBucket.fromJson(Map<String, dynamic> json) =>
      InventoryAgeBucket(
        key: json['key'] as String,
        label: json['label'] as String,
        quantity: _decimal(json['quantity']),
        totalValueMinor: _minorUnits(json['total_value']),
        skuCount: _wholeNumber(json['sku_count']),
      );

  final String key;
  final String label;
  final double quantity;
  final int totalValueMinor;
  final int skuCount;
}

class InventoryAgeingGroup {
  const InventoryAgeingGroup({
    required this.name,
    required this.quantity,
    required this.totalValueMinor,
    required this.skuCount,
    required this.olderThan90Quantity,
    this.id,
    this.oldestAgeDays,
  });

  factory InventoryAgeingGroup.fromJson(Map<String, dynamic> json) =>
      InventoryAgeingGroup(
        id: json['id'] as String?,
        name: json['name'] as String,
        quantity: _decimal(json['quantity']),
        totalValueMinor: _minorUnits(json['total_value']),
        skuCount: _wholeNumber(json['sku_count']),
        oldestAgeDays: json['oldest_age_days'] == null
            ? null
            : _wholeNumber(json['oldest_age_days']),
        olderThan90Quantity: _decimal(json['older_than_90_quantity']),
      );

  final String? id;
  final String name;
  final double quantity;
  final int totalValueMinor;
  final int skuCount;
  final int? oldestAgeDays;
  final double olderThan90Quantity;
}

class DeadStockReport {
  const DeadStockReport({
    required this.asOfDate,
    required this.inactivityDays,
    required this.stockPositionCount,
    required this.stockedSkuCount,
    required this.deadPositionCount,
    required this.deadSkuCount,
    required this.neverSoldSkuCount,
    required this.totalQuantity,
    required this.totalValueMinor,
    required this.deadQuantity,
    required this.deadReservedQuantity,
    required this.deadValueMinor,
    required this.items,
    required this.byWarehouse,
    required this.byCategory,
    this.deadValueRate,
  });

  factory DeadStockReport.fromJson(Map<String, dynamic> json) =>
      DeadStockReport(
        asOfDate: DateTime.parse(json['as_of_date'] as String),
        inactivityDays: _wholeNumber(json['inactivity_days']),
        stockPositionCount: _wholeNumber(json['stock_position_count']),
        stockedSkuCount: _wholeNumber(json['stocked_sku_count']),
        deadPositionCount: _wholeNumber(json['dead_position_count']),
        deadSkuCount: _wholeNumber(json['dead_sku_count']),
        neverSoldSkuCount: _wholeNumber(json['never_sold_sku_count']),
        totalQuantity: _decimal(json['total_quantity']),
        totalValueMinor: _minorUnits(json['total_value']),
        deadQuantity: _decimal(json['dead_quantity']),
        deadReservedQuantity: _decimal(json['dead_reserved_quantity']),
        deadValueMinor: _minorUnits(json['dead_value']),
        deadValueRate: _nullableDecimal(json['dead_value_rate']),
        items: _deadStockItems(json['items']),
        byWarehouse: _deadStockGroups(json['by_warehouse']),
        byCategory: _deadStockGroups(json['by_category']),
      );

  final DateTime asOfDate;
  final int inactivityDays;
  final int stockPositionCount;
  final int stockedSkuCount;
  final int deadPositionCount;
  final int deadSkuCount;
  final int neverSoldSkuCount;
  final double totalQuantity;
  final int totalValueMinor;
  final double deadQuantity;
  final double deadReservedQuantity;
  final int deadValueMinor;
  final double? deadValueRate;
  final List<DeadStockItem> items;
  final List<DeadStockGroup> byWarehouse;
  final List<DeadStockGroup> byCategory;
}

class DeadStockItem {
  const DeadStockItem({
    required this.warehouseId,
    required this.warehouseName,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.categoryName,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.availableQuantity,
    required this.averageCostMinor,
    required this.stockValueMinor,
    required this.neverSold,
    this.lastSaleAt,
    this.daysSinceLastSale,
    this.lastInboundAt,
    this.daysSinceInbound,
  });

  factory DeadStockItem.fromJson(Map<String, dynamic> json) => DeadStockItem(
    warehouseId: json['warehouse_id'] as String,
    warehouseName: json['warehouse_name'] as String,
    variantId: json['variant_id'] as String,
    productName: json['product_name'] as String,
    variantName: json['variant_name'] as String,
    sku: json['sku'] as String,
    categoryName: json['category_name'] as String,
    quantityOnHand: _decimal(json['quantity_on_hand']),
    quantityReserved: _decimal(json['quantity_reserved']),
    availableQuantity: _decimal(json['available_quantity']),
    averageCostMinor: _minorUnits(json['average_cost']),
    stockValueMinor: _minorUnits(json['stock_value']),
    neverSold: json['never_sold'] as bool,
    lastSaleAt: json['last_sale_at'] == null
        ? null
        : DateTime.parse(json['last_sale_at'] as String),
    daysSinceLastSale: json['days_since_last_sale'] == null
        ? null
        : _wholeNumber(json['days_since_last_sale']),
    lastInboundAt: json['last_inbound_at'] == null
        ? null
        : DateTime.parse(json['last_inbound_at'] as String),
    daysSinceInbound: json['days_since_inbound'] == null
        ? null
        : _wholeNumber(json['days_since_inbound']),
  );

  final String warehouseId;
  final String warehouseName;
  final String variantId;
  final String productName;
  final String variantName;
  final String sku;
  final String categoryName;
  final double quantityOnHand;
  final double quantityReserved;
  final double availableQuantity;
  final int averageCostMinor;
  final int stockValueMinor;
  final bool neverSold;
  final DateTime? lastSaleAt;
  final int? daysSinceLastSale;
  final DateTime? lastInboundAt;
  final int? daysSinceInbound;
}

class DeadStockGroup {
  const DeadStockGroup({
    required this.name,
    required this.positionCount,
    required this.skuCount,
    required this.neverSoldSkuCount,
    required this.quantity,
    required this.totalValueMinor,
    this.id,
  });

  factory DeadStockGroup.fromJson(Map<String, dynamic> json) => DeadStockGroup(
    id: json['id'] as String?,
    name: json['name'] as String,
    positionCount: _wholeNumber(json['position_count']),
    skuCount: _wholeNumber(json['sku_count']),
    neverSoldSkuCount: _wholeNumber(json['never_sold_sku_count']),
    quantity: _decimal(json['quantity']),
    totalValueMinor: _minorUnits(json['total_value']),
  );

  final String? id;
  final String name;
  final int positionCount;
  final int skuCount;
  final int neverSoldSkuCount;
  final double quantity;
  final int totalValueMinor;
}

class AbcInventoryReport {
  const AbcInventoryReport({
    required this.periodStart,
    required this.periodEnd,
    required this.method,
    required this.aThreshold,
    required this.bThreshold,
    required this.productCount,
    required this.netQuantity,
    required this.netSalesMinor,
    required this.inventoryQuantity,
    required this.inventoryValueMinor,
    required this.classes,
    required this.products,
  });

  factory AbcInventoryReport.fromJson(Map<String, dynamic> json) =>
      AbcInventoryReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        method: json['method'] as String,
        aThreshold: _decimal(json['a_threshold']),
        bThreshold: _decimal(json['b_threshold']),
        productCount: _wholeNumber(json['product_count']),
        netQuantity: _decimal(json['net_quantity']),
        netSalesMinor: _minorUnits(json['net_sales']),
        inventoryQuantity: _decimal(json['inventory_quantity']),
        inventoryValueMinor: _minorUnits(json['inventory_value']),
        classes: _abcInventoryClasses(json['classes']),
        products: _abcInventoryProducts(json['products']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final String method;
  final double aThreshold;
  final double bThreshold;
  final int productCount;
  final double netQuantity;
  final int netSalesMinor;
  final double inventoryQuantity;
  final int inventoryValueMinor;
  final List<AbcInventoryClass> classes;
  final List<AbcInventoryProduct> products;
}

class AbcInventoryClass {
  const AbcInventoryClass({
    required this.abcClass,
    required this.label,
    required this.productCount,
    required this.netQuantity,
    required this.netSalesMinor,
    required this.inventoryQuantity,
    required this.inventoryValueMinor,
    required this.contributionRate,
  });

  factory AbcInventoryClass.fromJson(Map<String, dynamic> json) =>
      AbcInventoryClass(
        abcClass: json['class'] as String,
        label: json['label'] as String,
        productCount: _wholeNumber(json['product_count']),
        netQuantity: _decimal(json['net_quantity']),
        netSalesMinor: _minorUnits(json['net_sales']),
        inventoryQuantity: _decimal(json['inventory_quantity']),
        inventoryValueMinor: _minorUnits(json['inventory_value']),
        contributionRate: _decimal(json['contribution_rate']),
      );

  final String abcClass;
  final String label;
  final int productCount;
  final double netQuantity;
  final int netSalesMinor;
  final double inventoryQuantity;
  final int inventoryValueMinor;
  final double contributionRate;
}

class AbcInventoryProduct {
  const AbcInventoryProduct({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.abcClass,
    required this.netQuantity,
    required this.netSalesMinor,
    required this.contributionRate,
    required this.cumulativeContributionRate,
    required this.inventoryQuantity,
    required this.inventoryValueMinor,
    this.categoryId,
  });

  factory AbcInventoryProduct.fromJson(Map<String, dynamic> json) =>
      AbcInventoryProduct(
        productId: json['product_id'] as String,
        productName: json['product_name'] as String,
        categoryId: json['category_id'] as String?,
        categoryName: json['category_name'] as String,
        abcClass: json['class'] as String,
        netQuantity: _decimal(json['net_quantity']),
        netSalesMinor: _minorUnits(json['net_sales']),
        contributionRate: _decimal(json['contribution_rate']),
        cumulativeContributionRate: _decimal(
          json['cumulative_contribution_rate'],
        ),
        inventoryQuantity: _decimal(json['inventory_quantity']),
        inventoryValueMinor: _minorUnits(json['inventory_value']),
      );

  final String productId;
  final String productName;
  final String? categoryId;
  final String categoryName;
  final String abcClass;
  final double netQuantity;
  final int netSalesMinor;
  final double contributionRate;
  final double cumulativeContributionRate;
  final double inventoryQuantity;
  final int inventoryValueMinor;
}

class InventoryTurnoverReport {
  const InventoryTurnoverReport({
    required this.periodStart,
    required this.periodEnd,
    required this.periodDays,
    required this.method,
    required this.netCogsMinor,
    required this.netUnitsSold,
    required this.beginningInventoryValueMinor,
    required this.endingInventoryValueMinor,
    required this.averageInventoryValueMinor,
    required this.byProduct,
    required this.byCategory,
    this.turnoverRatio,
    this.daysOnHand,
  });

  factory InventoryTurnoverReport.fromJson(Map<String, dynamic> json) =>
      InventoryTurnoverReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        periodDays: _wholeNumber(json['period_days']),
        method: json['method'] as String,
        netCogsMinor: _minorUnits(json['net_cogs']),
        netUnitsSold: _decimal(json['net_units_sold']),
        beginningInventoryValueMinor: _minorUnits(
          json['beginning_inventory_value'],
        ),
        endingInventoryValueMinor: _minorUnits(json['ending_inventory_value']),
        averageInventoryValueMinor: _minorUnits(
          json['average_inventory_value'],
        ),
        turnoverRatio: json['turnover_ratio'] == null
            ? null
            : _decimal(json['turnover_ratio']),
        daysOnHand: json['days_on_hand'] == null
            ? null
            : _decimal(json['days_on_hand']),
        byProduct: _turnoverGroups(json['by_product']),
        byCategory: _turnoverGroups(json['by_category']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int periodDays;
  final String method;
  final int netCogsMinor;
  final double netUnitsSold;
  final int beginningInventoryValueMinor;
  final int endingInventoryValueMinor;
  final int averageInventoryValueMinor;
  final double? turnoverRatio;
  final double? daysOnHand;
  final List<InventoryTurnoverGroup> byProduct;
  final List<InventoryTurnoverGroup> byCategory;
}

class InventoryTurnoverGroup {
  const InventoryTurnoverGroup({
    required this.name,
    required this.beginningQuantity,
    required this.endingQuantity,
    required this.beginningInventoryValueMinor,
    required this.endingInventoryValueMinor,
    required this.averageInventoryValueMinor,
    required this.netUnitsSold,
    required this.netCogsMinor,
    this.id,
    this.turnoverRatio,
    this.daysOnHand,
  });

  factory InventoryTurnoverGroup.fromJson(Map<String, dynamic> json) =>
      InventoryTurnoverGroup(
        id: json['id'] as String?,
        name: json['name'] as String,
        beginningQuantity: _decimal(json['beginning_quantity']),
        endingQuantity: _decimal(json['ending_quantity']),
        beginningInventoryValueMinor: _minorUnits(
          json['beginning_inventory_value'],
        ),
        endingInventoryValueMinor: _minorUnits(json['ending_inventory_value']),
        averageInventoryValueMinor: _minorUnits(
          json['average_inventory_value'],
        ),
        netUnitsSold: _decimal(json['net_units_sold']),
        netCogsMinor: _minorUnits(json['net_cogs']),
        turnoverRatio: json['turnover_ratio'] == null
            ? null
            : _decimal(json['turnover_ratio']),
        daysOnHand: json['days_on_hand'] == null
            ? null
            : _decimal(json['days_on_hand']),
      );

  final String? id;
  final String name;
  final double beginningQuantity;
  final double endingQuantity;
  final int beginningInventoryValueMinor;
  final int endingInventoryValueMinor;
  final int averageInventoryValueMinor;
  final double netUnitsSold;
  final int netCogsMinor;
  final double? turnoverRatio;
  final double? daysOnHand;
}

class StockAlertReport {
  const StockAlertReport({
    required this.generatedAt,
    required this.alertCount,
    required this.affectedSkuCount,
    required this.outOfStockCount,
    required this.belowSafetyStockCount,
    required this.reorderPointCount,
    required this.unconfiguredThresholdCount,
    required this.suggestedOrderQuantity,
    required this.estimatedReorderCostMinor,
    required this.items,
    required this.byWarehouse,
    required this.byCategory,
  });

  factory StockAlertReport.fromJson(Map<String, dynamic> json) =>
      StockAlertReport(
        generatedAt: DateTime.parse(json['generated_at'] as String).toLocal(),
        alertCount: _wholeNumber(json['alert_count']),
        affectedSkuCount: _wholeNumber(json['affected_sku_count']),
        outOfStockCount: _wholeNumber(json['out_of_stock_count']),
        belowSafetyStockCount: _wholeNumber(json['below_safety_stock_count']),
        reorderPointCount: _wholeNumber(json['reorder_point_count']),
        unconfiguredThresholdCount: _wholeNumber(
          json['unconfigured_threshold_count'],
        ),
        suggestedOrderQuantity: _decimal(json['suggested_order_quantity']),
        estimatedReorderCostMinor: _minorUnits(json['estimated_reorder_cost']),
        items: _stockAlertItems(json['items']),
        byWarehouse: _stockAlertGroups(json['by_warehouse']),
        byCategory: _stockAlertGroups(json['by_category']),
      );

  final DateTime generatedAt;
  final int alertCount;
  final int affectedSkuCount;
  final int outOfStockCount;
  final int belowSafetyStockCount;
  final int reorderPointCount;
  final int unconfiguredThresholdCount;
  final double suggestedOrderQuantity;
  final int estimatedReorderCostMinor;
  final List<StockAlertItem> items;
  final List<StockAlertGroup> byWarehouse;
  final List<StockAlertGroup> byCategory;
}

class StockAlertItem {
  const StockAlertItem({
    required this.variantId,
    required this.productId,
    required this.warehouseId,
    required this.branchId,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.warehouseName,
    required this.branchName,
    required this.categoryName,
    required this.severity,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.availableQuantity,
    required this.reorderPoint,
    required this.safetyStock,
    required this.targetStock,
    required this.thresholdConfigured,
    required this.suggestedOrderQuantity,
    required this.averageCostMinor,
    required this.suggestedOrderCostMinor,
    required this.updatedAt,
    this.categoryId,
  });

  factory StockAlertItem.fromJson(Map<String, dynamic> json) => StockAlertItem(
    variantId: json['variant_id'] as String,
    productId: json['product_id'] as String,
    categoryId: json['category_id'] as String?,
    warehouseId: json['warehouse_id'] as String,
    branchId: json['branch_id'] as String,
    productName: json['product_name'] as String,
    variantName: json['variant_name'] as String,
    sku: json['sku'] as String,
    warehouseName: json['warehouse_name'] as String,
    branchName: json['branch_name'] as String,
    categoryName: json['category_name'] as String,
    severity: json['severity'] as String,
    quantityOnHand: _decimal(json['quantity_on_hand']),
    quantityReserved: _decimal(json['quantity_reserved']),
    availableQuantity: _decimal(json['available_quantity']),
    reorderPoint: _decimal(json['reorder_point']),
    safetyStock: _decimal(json['safety_stock']),
    targetStock: _decimal(json['target_stock']),
    thresholdConfigured: json['threshold_configured'] as bool,
    suggestedOrderQuantity: _decimal(json['suggested_order_quantity']),
    averageCostMinor: _minorUnits(json['average_cost']),
    suggestedOrderCostMinor: _minorUnits(json['suggested_order_cost']),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
  );

  final String variantId;
  final String productId;
  final String? categoryId;
  final String warehouseId;
  final String branchId;
  final String productName;
  final String variantName;
  final String sku;
  final String warehouseName;
  final String branchName;
  final String categoryName;
  final String severity;
  final double quantityOnHand;
  final double quantityReserved;
  final double availableQuantity;
  final double reorderPoint;
  final double safetyStock;
  final double targetStock;
  final bool thresholdConfigured;
  final double suggestedOrderQuantity;
  final int averageCostMinor;
  final int suggestedOrderCostMinor;
  final DateTime updatedAt;
}

class StockAlertGroup {
  const StockAlertGroup({
    required this.name,
    required this.alertCount,
    required this.outOfStockCount,
    required this.belowSafetyStockCount,
    required this.reorderPointCount,
    required this.suggestedOrderQuantity,
    required this.estimatedReorderCostMinor,
    this.id,
  });

  factory StockAlertGroup.fromJson(Map<String, dynamic> json) =>
      StockAlertGroup(
        id: json['id'] as String?,
        name: json['name'] as String,
        alertCount: _wholeNumber(json['alert_count']),
        outOfStockCount: _wholeNumber(json['out_of_stock_count']),
        belowSafetyStockCount: _wholeNumber(json['below_safety_stock_count']),
        reorderPointCount: _wholeNumber(json['reorder_point_count']),
        suggestedOrderQuantity: _decimal(json['suggested_order_quantity']),
        estimatedReorderCostMinor: _minorUnits(json['estimated_reorder_cost']),
      );

  final String? id;
  final String name;
  final int alertCount;
  final int outOfStockCount;
  final int belowSafetyStockCount;
  final int reorderPointCount;
  final double suggestedOrderQuantity;
  final int estimatedReorderCostMinor;
}

class StockAlertNotification {
  const StockAlertNotification({
    required this.id,
    required this.warehouseId,
    required this.variantId,
    required this.warehouseName,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.severity,
    required this.status,
    required this.availableQuantity,
    required this.targetStock,
    required this.suggestedOrderQuantity,
    required this.averageCostMinor,
    required this.createdAt,
    required this.updatedAt,
    this.acknowledgedAt,
  });

  factory StockAlertNotification.fromJson(Map<String, dynamic> json) =>
      StockAlertNotification(
        id: json['id'] as String,
        warehouseId: json['warehouse_id'] as String,
        variantId: json['variant_id'] as String,
        warehouseName: json['warehouse_name'] as String,
        productName: json['product_name'] as String,
        variantName: json['variant_name'] as String,
        sku: json['sku'] as String,
        severity: json['severity'] as String,
        status: json['status'] as String,
        availableQuantity: _decimal(json['available_quantity']),
        targetStock: _decimal(json['target_stock']),
        suggestedOrderQuantity: _decimal(json['suggested_order_quantity']),
        averageCostMinor: _minorUnits(json['average_cost']),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
        acknowledgedAt: json['acknowledged_at'] == null
            ? null
            : DateTime.parse(json['acknowledged_at'] as String).toLocal(),
      );

  final String id;
  final String warehouseId;
  final String variantId;
  final String warehouseName;
  final String productName;
  final String variantName;
  final String sku;
  final String severity;
  final String status;
  final double availableQuantity;
  final double targetStock;
  final double suggestedOrderQuantity;
  final int averageCostMinor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? acknowledgedAt;
}

class CustomerAnalyticsReport {
  const CustomerAnalyticsReport({
    required this.periodStart,
    required this.periodEnd,
    required this.periodDays,
    required this.totalPeriodOrders,
    required this.identifiedPeriodOrders,
    required this.walkInPeriodOrders,
    required this.activeCustomers,
    required this.newCustomers,
    required this.returningCustomers,
    required this.repeatCustomers,
    required this.lifetimeCustomerCount,
    required this.totalLifetimeValueMinor,
    required this.identifiedPeriodNetRevenueMinor,
    required this.monthlyRetention,
    required this.topCustomers,
    this.customerCaptureRate,
    this.retentionRate,
    this.repeatCustomerRate,
    this.averageLifetimeValueMinor,
  });

  factory CustomerAnalyticsReport.fromJson(Map<String, dynamic> json) =>
      CustomerAnalyticsReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        periodDays: _wholeNumber(json['period_days']),
        totalPeriodOrders: _wholeNumber(json['total_period_orders']),
        identifiedPeriodOrders: _wholeNumber(json['identified_period_orders']),
        walkInPeriodOrders: _wholeNumber(json['walk_in_period_orders']),
        customerCaptureRate: _nullableDecimal(json['customer_capture_rate']),
        activeCustomers: _wholeNumber(json['active_customers']),
        newCustomers: _wholeNumber(json['new_customers']),
        returningCustomers: _wholeNumber(json['returning_customers']),
        repeatCustomers: _wholeNumber(json['repeat_customers']),
        retentionRate: _nullableDecimal(json['retention_rate']),
        repeatCustomerRate: _nullableDecimal(json['repeat_customer_rate']),
        lifetimeCustomerCount: _wholeNumber(json['lifetime_customer_count']),
        totalLifetimeValueMinor: _minorUnits(json['total_lifetime_value']),
        averageLifetimeValueMinor: json['average_lifetime_value'] == null
            ? null
            : _minorUnits(json['average_lifetime_value']),
        identifiedPeriodNetRevenueMinor: _minorUnits(
          json['identified_period_net_revenue'],
        ),
        monthlyRetention: _customerRetentionPoints(json['monthly_retention']),
        topCustomers: _customerLifetimeValues(json['top_customers']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int periodDays;
  final int totalPeriodOrders;
  final int identifiedPeriodOrders;
  final int walkInPeriodOrders;
  final double? customerCaptureRate;
  final int activeCustomers;
  final int newCustomers;
  final int returningCustomers;
  final int repeatCustomers;
  final double? retentionRate;
  final double? repeatCustomerRate;
  final int lifetimeCustomerCount;
  final int totalLifetimeValueMinor;
  final int? averageLifetimeValueMinor;
  final int identifiedPeriodNetRevenueMinor;
  final List<CustomerRetentionPoint> monthlyRetention;
  final List<CustomerLifetimeValue> topCustomers;

  int? get averageIdentifiedOrderValueMinor => identifiedPeriodOrders == 0
      ? null
      : (identifiedPeriodNetRevenueMinor / identifiedPeriodOrders).round();

  double? get averageOrdersPerActiveCustomer =>
      activeCustomers == 0 ? null : identifiedPeriodOrders / activeCustomers;
}

class CustomerRetentionPoint {
  const CustomerRetentionPoint({
    required this.month,
    required this.activeCustomers,
    required this.newCustomers,
    required this.returningCustomers,
    required this.netRevenueMinor,
    this.retentionRate,
  });

  factory CustomerRetentionPoint.fromJson(Map<String, dynamic> json) =>
      CustomerRetentionPoint(
        month: DateTime.parse(json['month'] as String),
        activeCustomers: _wholeNumber(json['active_customers']),
        newCustomers: _wholeNumber(json['new_customers']),
        returningCustomers: _wholeNumber(json['returning_customers']),
        retentionRate: _nullableDecimal(json['retention_rate']),
        netRevenueMinor: _minorUnits(json['net_revenue']),
      );

  final DateTime month;
  final int activeCustomers;
  final int newCustomers;
  final int returningCustomers;
  final double? retentionRate;
  final int netRevenueMinor;
}

class CustomerLifetimeValue {
  const CustomerLifetimeValue({
    required this.id,
    required this.name,
    required this.firstPurchaseAt,
    required this.lastPurchaseAt,
    required this.lifetimeOrderCount,
    required this.lifetimeGrossSalesMinor,
    required this.lifetimeRefundsMinor,
    required this.netLifetimeValueMinor,
    required this.averageOrderValueMinor,
    required this.periodOrderCount,
    required this.periodNetRevenueMinor,
    required this.periodStatus,
    required this.lifetimeDays,
    required this.daysSinceLastPurchase,
    this.phone,
    this.email,
  });

  factory CustomerLifetimeValue.fromJson(Map<String, dynamic> json) =>
      CustomerLifetimeValue(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        firstPurchaseAt: DateTime.parse(json['first_purchase_at'] as String)
            .toLocal(),
        lastPurchaseAt: DateTime.parse(json['last_purchase_at'] as String)
            .toLocal(),
        lifetimeOrderCount: _wholeNumber(json['lifetime_order_count']),
        lifetimeGrossSalesMinor: _minorUnits(json['lifetime_gross_sales']),
        lifetimeRefundsMinor: _minorUnits(json['lifetime_refunds']),
        netLifetimeValueMinor: _minorUnits(json['net_lifetime_value']),
        averageOrderValueMinor: _minorUnits(json['average_order_value']),
        periodOrderCount: _wholeNumber(json['period_order_count']),
        periodNetRevenueMinor: _minorUnits(json['period_net_revenue']),
        periodStatus: json['period_status'] as String,
        lifetimeDays: _wholeNumber(json['lifetime_days']),
        daysSinceLastPurchase: _wholeNumber(json['days_since_last_purchase']),
      );

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final DateTime firstPurchaseAt;
  final DateTime lastPurchaseAt;
  final int lifetimeOrderCount;
  final int lifetimeGrossSalesMinor;
  final int lifetimeRefundsMinor;
  final int netLifetimeValueMinor;
  final int averageOrderValueMinor;
  final int periodOrderCount;
  final int periodNetRevenueMinor;
  final String periodStatus;
  final int lifetimeDays;
  final int daysSinceLastPurchase;
}

class CustomerCreditAgeingReport {
  const CustomerCreditAgeingReport({
    required this.asOfDate,
    required this.ageBasis,
    required this.totalReceivablesMinor,
    required this.customerCount,
    required this.openInvoiceCount,
    required this.openAdjustmentCount,
    required this.olderThan60Minor,
    required this.totalCreditLimitMinor,
    required this.overLimitCustomerCount,
    required this.unlimitedCustomerCount,
    required this.unappliedCreditAdjustmentsMinor,
    required this.buckets,
    required this.customers,
    this.oldestAgeDays,
    this.weightedAverageAgeDays,
    this.olderThan60Rate,
    this.creditLimitUtilization,
  });

  factory CustomerCreditAgeingReport.fromJson(
    Map<String, dynamic> json,
  ) => CustomerCreditAgeingReport(
    asOfDate: DateTime.parse(json['as_of_date'] as String),
    ageBasis: json['age_basis'] as String,
    totalReceivablesMinor: _minorUnits(json['total_receivables']),
    customerCount: _wholeNumber(json['customer_count']),
    openInvoiceCount: _wholeNumber(json['open_invoice_count']),
    openAdjustmentCount: _wholeNumber(json['open_adjustment_count']),
    oldestAgeDays: json['oldest_age_days'] == null
        ? null
        : _wholeNumber(json['oldest_age_days']),
    weightedAverageAgeDays: _nullableDecimal(json['weighted_average_age_days']),
    olderThan60Minor: _minorUnits(json['older_than_60_amount']),
    olderThan60Rate: _nullableDecimal(json['older_than_60_rate']),
    totalCreditLimitMinor: _minorUnits(json['total_credit_limit']),
    creditLimitUtilization: _nullableDecimal(json['credit_limit_utilization']),
    overLimitCustomerCount: _wholeNumber(json['over_limit_customer_count']),
    unlimitedCustomerCount: _wholeNumber(json['unlimited_customer_count']),
    unappliedCreditAdjustmentsMinor: _minorUnits(
      json['unapplied_credit_adjustments'],
    ),
    buckets: _customerCreditAgeingBuckets(json['buckets']),
    customers: _customerCreditExposures(json['customers']),
  );

  final DateTime asOfDate;
  final String ageBasis;
  final int totalReceivablesMinor;
  final int customerCount;
  final int openInvoiceCount;
  final int openAdjustmentCount;
  final int? oldestAgeDays;
  final double? weightedAverageAgeDays;
  final int olderThan60Minor;
  final double? olderThan60Rate;
  final int totalCreditLimitMinor;
  final double? creditLimitUtilization;
  final int overLimitCustomerCount;
  final int unlimitedCustomerCount;
  final int unappliedCreditAdjustmentsMinor;
  final List<CustomerCreditAgeingBucket> buckets;
  final List<CustomerCreditExposure> customers;
}

class CustomerCreditAgeingBucket {
  const CustomerCreditAgeingBucket({
    required this.key,
    required this.label,
    required this.amountMinor,
    required this.customerCount,
    required this.itemCount,
  });

  factory CustomerCreditAgeingBucket.fromJson(Map<String, dynamic> json) =>
      CustomerCreditAgeingBucket(
        key: json['key'] as String,
        label: json['label'] as String,
        amountMinor: _minorUnits(json['amount']),
        customerCount: _wholeNumber(json['customer_count']),
        itemCount: _wholeNumber(json['item_count']),
      );

  final String key;
  final String label;
  final int amountMinor;
  final int customerCount;
  final int itemCount;
}

class CustomerCreditExposure {
  const CustomerCreditExposure({
    required this.id,
    required this.name,
    required this.creditLimitMinor,
    required this.outstandingAmountMinor,
    required this.availableCreditMinor,
    required this.overLimitAmountMinor,
    required this.openInvoiceCount,
    required this.openAdjustmentCount,
    required this.age0To30Minor,
    required this.age31To60Minor,
    required this.age61To90Minor,
    required this.age91PlusMinor,
    required this.oldestAgeDays,
    required this.weightedAverageAgeDays,
    this.code,
    this.phone,
    this.email,
    this.creditLimitUtilization,
  });

  factory CustomerCreditExposure.fromJson(Map<String, dynamic> json) =>
      CustomerCreditExposure(
        id: json['id'] as String,
        code: json['code'] as String?,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        creditLimitMinor: _minorUnits(json['credit_limit']),
        outstandingAmountMinor: _minorUnits(json['outstanding_amount']),
        availableCreditMinor: _minorUnits(json['available_credit']),
        overLimitAmountMinor: _minorUnits(json['over_limit_amount']),
        creditLimitUtilization: _nullableDecimal(
          json['credit_limit_utilization'],
        ),
        openInvoiceCount: _wholeNumber(json['open_invoice_count']),
        openAdjustmentCount: _wholeNumber(json['open_adjustment_count']),
        age0To30Minor: _minorUnits(json['age_0_30']),
        age31To60Minor: _minorUnits(json['age_31_60']),
        age61To90Minor: _minorUnits(json['age_61_90']),
        age91PlusMinor: _minorUnits(json['age_91_plus']),
        oldestAgeDays: _wholeNumber(json['oldest_age_days']),
        weightedAverageAgeDays: _decimal(json['weighted_average_age_days']),
      );

  final String id;
  final String? code;
  final String name;
  final String? phone;
  final String? email;
  final int creditLimitMinor;
  final int outstandingAmountMinor;
  final int availableCreditMinor;
  final int overLimitAmountMinor;
  final double? creditLimitUtilization;
  final int openInvoiceCount;
  final int openAdjustmentCount;
  final int age0To30Minor;
  final int age31To60Minor;
  final int age61To90Minor;
  final int age91PlusMinor;
  final int oldestAgeDays;
  final double weightedAverageAgeDays;
}

class SalesTargetComparisonReport {
  const SalesTargetComparisonReport({
    required this.periodStart,
    required this.periodEnd,
    required this.periodDays,
    required this.comparisonStart,
    required this.comparisonEnd,
    required this.currentSalesMinor,
    required this.previousSalesMinor,
    required this.salesChangeMinor,
    required this.currentOrders,
    required this.previousOrders,
    required this.targetedBranchCount,
    required this.accessibleBranchCount,
    required this.branches,
    this.salesChangeRate,
    this.orderChangeRate,
    this.currentAverageOrderValueMinor,
    this.previousAverageOrderValueMinor,
    this.targetAmountMinor,
    this.targetGapMinor,
    this.targetAchievementRate,
  });

  factory SalesTargetComparisonReport.fromJson(Map<String, dynamic> json) =>
      SalesTargetComparisonReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        periodDays: _wholeNumber(json['period_days']),
        comparisonStart: DateTime.parse(json['comparison_start'] as String),
        comparisonEnd: DateTime.parse(json['comparison_end'] as String),
        currentSalesMinor: _minorUnits(json['current_sales']),
        previousSalesMinor: _minorUnits(json['previous_sales']),
        salesChangeMinor: _minorUnits(json['sales_change']),
        salesChangeRate: _nullableDecimal(json['sales_change_rate']),
        currentOrders: _wholeNumber(json['current_orders']),
        previousOrders: _wholeNumber(json['previous_orders']),
        orderChangeRate: _nullableDecimal(json['order_change_rate']),
        currentAverageOrderValueMinor: _nullableMinorUnits(
          json['current_average_order_value'],
        ),
        previousAverageOrderValueMinor: _nullableMinorUnits(
          json['previous_average_order_value'],
        ),
        targetAmountMinor: _nullableMinorUnits(json['target_amount']),
        targetGapMinor: _nullableMinorUnits(json['target_gap']),
        targetAchievementRate: _nullableDecimal(
          json['target_achievement_rate'],
        ),
        targetedBranchCount: _wholeNumber(json['targeted_branch_count']),
        accessibleBranchCount: _wholeNumber(json['accessible_branch_count']),
        branches: _salesTargetBranchComparisons(json['branches']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int periodDays;
  final DateTime comparisonStart;
  final DateTime comparisonEnd;
  final int currentSalesMinor;
  final int previousSalesMinor;
  final int salesChangeMinor;
  final double? salesChangeRate;
  final int currentOrders;
  final int previousOrders;
  final double? orderChangeRate;
  final int? currentAverageOrderValueMinor;
  final int? previousAverageOrderValueMinor;
  final int? targetAmountMinor;
  final int? targetGapMinor;
  final double? targetAchievementRate;
  final int targetedBranchCount;
  final int accessibleBranchCount;
  final List<SalesTargetBranchComparison> branches;
}

class SalesTargetBranchComparison {
  const SalesTargetBranchComparison({
    required this.id,
    required this.name,
    required this.currentSalesMinor,
    required this.previousSalesMinor,
    required this.salesChangeMinor,
    required this.currentOrders,
    required this.previousOrders,
    this.targetId,
    this.targetAmountMinor,
    this.targetNotes,
    this.salesChangeRate,
    this.targetGapMinor,
    this.targetAchievementRate,
  });

  factory SalesTargetBranchComparison.fromJson(Map<String, dynamic> json) =>
      SalesTargetBranchComparison(
        id: json['id'] as String,
        name: json['name'] as String,
        targetId: json['target_id'] as String?,
        targetAmountMinor: _nullableMinorUnits(json['target_amount']),
        targetNotes: json['target_notes'] as String?,
        currentSalesMinor: _minorUnits(json['current_sales']),
        previousSalesMinor: _minorUnits(json['previous_sales']),
        salesChangeMinor: _minorUnits(json['sales_change']),
        salesChangeRate: _nullableDecimal(json['sales_change_rate']),
        currentOrders: _wholeNumber(json['current_orders']),
        previousOrders: _wholeNumber(json['previous_orders']),
        targetGapMinor: _nullableMinorUnits(json['target_gap']),
        targetAchievementRate: _nullableDecimal(
          json['target_achievement_rate'],
        ),
      );

  final String id;
  final String name;
  final String? targetId;
  final int? targetAmountMinor;
  final String? targetNotes;
  final int currentSalesMinor;
  final int previousSalesMinor;
  final int salesChangeMinor;
  final double? salesChangeRate;
  final int currentOrders;
  final int previousOrders;
  final int? targetGapMinor;
  final double? targetAchievementRate;
}

class PurchaseSupplierPerformanceReport {
  const PurchaseSupplierPerformanceReport({
    required this.periodStart,
    required this.periodEnd,
    required this.orderCount,
    required this.receivedOrderCount,
    required this.partiallyReceivedOrderCount,
    required this.openOrderCount,
    required this.cancelledOrderCount,
    required this.overdueOrderCount,
    required this.onTimeOrderCount,
    required this.lateOrderCount,
    required this.measuredDeliveryCount,
    required this.orderedTotalMinor,
    required this.receivedCostMinor,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.outstandingQuantity,
    required this.outstandingItemCostMinor,
    required this.receiptCount,
    required this.suppliers,
    required this.products,
    this.onTimeRate,
    this.averageLeadDays,
  });

  factory PurchaseSupplierPerformanceReport.fromJson(
    Map<String, dynamic> json,
  ) => PurchaseSupplierPerformanceReport(
    periodStart: DateTime.parse(json['period_start'] as String),
    periodEnd: DateTime.parse(json['period_end'] as String),
    orderCount: _wholeNumber(json['order_count']),
    receivedOrderCount: _wholeNumber(json['received_order_count']),
    partiallyReceivedOrderCount: _wholeNumber(
      json['partially_received_order_count'],
    ),
    openOrderCount: _wholeNumber(json['open_order_count']),
    cancelledOrderCount: _wholeNumber(json['cancelled_order_count']),
    overdueOrderCount: _wholeNumber(json['overdue_order_count']),
    onTimeOrderCount: _wholeNumber(json['on_time_order_count']),
    lateOrderCount: _wholeNumber(json['late_order_count']),
    measuredDeliveryCount: _wholeNumber(json['measured_delivery_count']),
    onTimeRate: _nullableDecimal(json['on_time_rate']),
    orderedTotalMinor: _minorUnits(json['ordered_total']),
    receivedCostMinor: _minorUnits(json['received_cost']),
    orderedQuantity: _decimal(json['ordered_quantity']),
    receivedQuantity: _decimal(json['received_quantity']),
    outstandingQuantity: _decimal(json['outstanding_quantity']),
    outstandingItemCostMinor: _minorUnits(json['outstanding_item_cost']),
    receiptCount: _wholeNumber(json['receipt_count']),
    averageLeadDays: _nullableDecimal(json['average_lead_days']),
    suppliers: _supplierPerformanceItems(json['suppliers']),
    products: _purchaseProductPerformanceItems(json['products']),
  );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int orderCount;
  final int receivedOrderCount;
  final int partiallyReceivedOrderCount;
  final int openOrderCount;
  final int cancelledOrderCount;
  final int overdueOrderCount;
  final int onTimeOrderCount;
  final int lateOrderCount;
  final int measuredDeliveryCount;
  final double? onTimeRate;
  final int orderedTotalMinor;
  final int receivedCostMinor;
  final double orderedQuantity;
  final double receivedQuantity;
  final double outstandingQuantity;
  final int outstandingItemCostMinor;
  final int receiptCount;
  final double? averageLeadDays;
  final List<SupplierPerformanceItem> suppliers;
  final List<PurchaseProductPerformanceItem> products;
}

class SupplierPerformanceItem {
  const SupplierPerformanceItem({
    required this.supplierId,
    required this.supplierName,
    required this.orderCount,
    required this.receivedOrderCount,
    required this.openOrderCount,
    required this.cancelledOrderCount,
    required this.overdueOrderCount,
    required this.onTimeOrderCount,
    required this.lateOrderCount,
    required this.orderedTotalMinor,
    required this.receivedCostMinor,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.outstandingQuantity,
    this.onTimeRate,
    this.averageLeadDays,
  });

  factory SupplierPerformanceItem.fromJson(Map<String, dynamic> json) =>
      SupplierPerformanceItem(
        supplierId: json['supplier_id'] as String,
        supplierName: json['supplier_name'] as String,
        orderCount: _wholeNumber(json['order_count']),
        receivedOrderCount: _wholeNumber(json['received_order_count']),
        openOrderCount: _wholeNumber(json['open_order_count']),
        cancelledOrderCount: _wholeNumber(json['cancelled_order_count']),
        overdueOrderCount: _wholeNumber(json['overdue_order_count']),
        onTimeOrderCount: _wholeNumber(json['on_time_order_count']),
        lateOrderCount: _wholeNumber(json['late_order_count']),
        onTimeRate: _nullableDecimal(json['on_time_rate']),
        orderedTotalMinor: _minorUnits(json['ordered_total']),
        receivedCostMinor: _minorUnits(json['received_cost']),
        orderedQuantity: _decimal(json['ordered_quantity']),
        receivedQuantity: _decimal(json['received_quantity']),
        outstandingQuantity: _decimal(json['outstanding_quantity']),
        averageLeadDays: _nullableDecimal(json['average_lead_days']),
      );

  final String supplierId;
  final String supplierName;
  final int orderCount;
  final int receivedOrderCount;
  final int openOrderCount;
  final int cancelledOrderCount;
  final int overdueOrderCount;
  final int onTimeOrderCount;
  final int lateOrderCount;
  final double? onTimeRate;
  final int orderedTotalMinor;
  final int receivedCostMinor;
  final double orderedQuantity;
  final double receivedQuantity;
  final double outstandingQuantity;
  final double? averageLeadDays;
}

class PurchaseProductPerformanceItem {
  const PurchaseProductPerformanceItem({
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.supplierCount,
    required this.orderCount,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.outstandingQuantity,
    required this.orderedItemCostMinor,
  });

  factory PurchaseProductPerformanceItem.fromJson(Map<String, dynamic> json) =>
      PurchaseProductPerformanceItem(
        variantId: json['variant_id'] as String,
        productName: json['product_name'] as String,
        variantName: json['variant_name'] as String,
        sku: json['sku'] as String,
        supplierCount: _wholeNumber(json['supplier_count']),
        orderCount: _wholeNumber(json['order_count']),
        orderedQuantity: _decimal(json['ordered_quantity']),
        receivedQuantity: _decimal(json['received_quantity']),
        outstandingQuantity: _decimal(json['outstanding_quantity']),
        orderedItemCostMinor: _minorUnits(json['ordered_item_cost']),
      );

  final String variantId;
  final String productName;
  final String variantName;
  final String sku;
  final int supplierCount;
  final int orderCount;
  final double orderedQuantity;
  final double receivedQuantity;
  final double outstandingQuantity;
  final int orderedItemCostMinor;
}

class SalesAdjustmentsReport {
  const SalesAdjustmentsReport({
    required this.periodStart,
    required this.periodEnd,
    required this.saleCount,
    required this.discountedSaleCount,
    required this.saleSubtotalMinor,
    required this.discountTotalMinor,
    required this.lineDiscountTotalMinor,
    required this.orderDiscountTotalMinor,
    required this.returnCount,
    required this.returnedQuantity,
    required this.returnedSubtotalMinor,
    required this.returnedDiscountTotalMinor,
    required this.returnedTaxTotalMinor,
    required this.refundTotalMinor,
    required this.settledRefundTotalMinor,
    required this.pendingRefundTotalMinor,
    required this.failedRefundTotalMinor,
    required this.creditNoteTotalMinor,
    required this.refundAllocations,
    required this.returnReasons,
    required this.returnedProducts,
    required this.branchDiscounts,
    this.discountRate,
  });

  factory SalesAdjustmentsReport.fromJson(Map<String, dynamic> json) =>
      SalesAdjustmentsReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        saleCount: _wholeNumber(json['sale_count']),
        discountedSaleCount: _wholeNumber(json['discounted_sale_count']),
        saleSubtotalMinor: _minorUnits(json['sale_subtotal']),
        discountTotalMinor: _minorUnits(json['discount_total']),
        lineDiscountTotalMinor: _minorUnits(json['line_discount_total']),
        orderDiscountTotalMinor: _minorUnits(json['order_discount_total']),
        discountRate: _nullableDecimal(json['discount_rate']),
        returnCount: _wholeNumber(json['return_count']),
        returnedQuantity: _decimal(json['returned_quantity']),
        returnedSubtotalMinor: _minorUnits(json['returned_subtotal']),
        returnedDiscountTotalMinor: _minorUnits(
          json['returned_discount_total'],
        ),
        returnedTaxTotalMinor: _minorUnits(json['returned_tax_total']),
        refundTotalMinor: _minorUnits(json['refund_total']),
        settledRefundTotalMinor: _minorUnits(json['settled_refund_total']),
        pendingRefundTotalMinor: _minorUnits(json['pending_refund_total']),
        failedRefundTotalMinor: _minorUnits(json['failed_refund_total']),
        creditNoteTotalMinor: _minorUnits(json['credit_note_total']),
        refundAllocations: _refundAllocationItems(json['refund_allocations']),
        returnReasons: _returnReasonItems(json['return_reasons']),
        returnedProducts: _returnedProductItems(json['returned_products']),
        branchDiscounts: _branchDiscountItems(json['branch_discounts']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int saleCount;
  final int discountedSaleCount;
  final int saleSubtotalMinor;
  final int discountTotalMinor;
  final int lineDiscountTotalMinor;
  final int orderDiscountTotalMinor;
  final double? discountRate;
  final int returnCount;
  final double returnedQuantity;
  final int returnedSubtotalMinor;
  final int returnedDiscountTotalMinor;
  final int returnedTaxTotalMinor;
  final int refundTotalMinor;
  final int settledRefundTotalMinor;
  final int pendingRefundTotalMinor;
  final int failedRefundTotalMinor;
  final int creditNoteTotalMinor;
  final List<RefundAllocationItem> refundAllocations;
  final List<ReturnReasonItem> returnReasons;
  final List<ReturnedProductItem> returnedProducts;
  final List<BranchDiscountItem> branchDiscounts;
}

class PromotionPerformanceReport {
  const PromotionPerformanceReport({
    required this.periodStart,
    required this.periodEnd,
    required this.promotionCount,
    required this.activePromotionCount,
    required this.campaignsUsed,
    required this.redemptionCount,
    required this.uniqueCustomerCount,
    required this.discountTotalMinor,
    required this.attributedSubtotalMinor,
    required this.attributedSalesMinor,
    required this.averageOrderValueMinor,
    required this.discountRate,
    required this.campaigns,
    required this.daily,
  });

  factory PromotionPerformanceReport.fromJson(Map<String, dynamic> json) =>
      PromotionPerformanceReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        promotionCount: _wholeNumber(json['promotion_count']),
        activePromotionCount: _wholeNumber(json['active_promotion_count']),
        campaignsUsed: _wholeNumber(json['campaigns_used']),
        redemptionCount: _wholeNumber(json['redemption_count']),
        uniqueCustomerCount: _wholeNumber(json['unique_customer_count']),
        discountTotalMinor: _minorUnits(json['discount_total']),
        attributedSubtotalMinor: _minorUnits(json['attributed_subtotal']),
        attributedSalesMinor: _minorUnits(json['attributed_sales']),
        averageOrderValueMinor: _nullableMinorUnits(
          json['average_order_value'],
        ),
        discountRate: _nullableDecimal(json['discount_rate']),
        campaigns: _promotionPerformanceCampaigns(json['campaigns']),
        daily: _promotionPerformanceDaily(json['daily']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int promotionCount;
  final int activePromotionCount;
  final int campaignsUsed;
  final int redemptionCount;
  final int uniqueCustomerCount;
  final int discountTotalMinor;
  final int attributedSubtotalMinor;
  final int attributedSalesMinor;
  final int? averageOrderValueMinor;
  final double? discountRate;
  final List<PromotionPerformanceCampaign> campaigns;
  final List<PromotionPerformanceDailyPoint> daily;
}

class PromotionPerformanceCampaign {
  const PromotionPerformanceCampaign({
    required this.promotionId,
    required this.code,
    required this.name,
    required this.branchName,
    required this.discountType,
    required this.discountValue,
    required this.usageLimit,
    required this.redeemedCount,
    required this.isActive,
    required this.redemptionCount,
    required this.uniqueCustomerCount,
    required this.discountTotalMinor,
    required this.attributedSubtotalMinor,
    required this.attributedSalesMinor,
    required this.averageOrderValueMinor,
    required this.discountRate,
    required this.firstRedeemedAt,
    required this.lastRedeemedAt,
  });

  factory PromotionPerformanceCampaign.fromJson(Map<String, dynamic> json) =>
      PromotionPerformanceCampaign(
        promotionId: json['promotion_id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        branchName: json['branch_name'] as String? ?? 'All branches',
        discountType: json['discount_type'] as String,
        discountValue: _decimal(json['discount_value']),
        usageLimit: (json['usage_limit'] as num?)?.toInt(),
        redeemedCount: _wholeNumber(json['redeemed_count']),
        isActive: json['is_active'] as bool? ?? false,
        redemptionCount: _wholeNumber(json['redemption_count']),
        uniqueCustomerCount: _wholeNumber(json['unique_customer_count']),
        discountTotalMinor: _minorUnits(json['discount_total']),
        attributedSubtotalMinor: _minorUnits(json['attributed_subtotal']),
        attributedSalesMinor: _minorUnits(json['attributed_sales']),
        averageOrderValueMinor: _nullableMinorUnits(
          json['average_order_value'],
        ),
        discountRate: _nullableDecimal(json['discount_rate']),
        firstRedeemedAt: _localDate(json['first_redeemed_at']),
        lastRedeemedAt: _localDate(json['last_redeemed_at']),
      );

  final String promotionId;
  final String code;
  final String name;
  final String branchName;
  final String discountType;
  final double discountValue;
  final int? usageLimit;
  final int redeemedCount;
  final bool isActive;
  final int redemptionCount;
  final int uniqueCustomerCount;
  final int discountTotalMinor;
  final int attributedSubtotalMinor;
  final int attributedSalesMinor;
  final int? averageOrderValueMinor;
  final double? discountRate;
  final DateTime? firstRedeemedAt;
  final DateTime? lastRedeemedAt;

  bool get isPercentage => discountType == 'percentage';
}

class PromotionPerformanceDailyPoint {
  const PromotionPerformanceDailyPoint({
    required this.day,
    required this.redemptionCount,
    required this.discountTotalMinor,
    required this.attributedSalesMinor,
  });

  factory PromotionPerformanceDailyPoint.fromJson(Map<String, dynamic> json) =>
      PromotionPerformanceDailyPoint(
        day: DateTime.parse(json['day'] as String),
        redemptionCount: _wholeNumber(json['redemption_count']),
        discountTotalMinor: _minorUnits(json['discount_total']),
        attributedSalesMinor: _minorUnits(json['attributed_sales']),
      );

  final DateTime day;
  final int redemptionCount;
  final int discountTotalMinor;
  final int attributedSalesMinor;
}

class RefundAllocationItem {
  const RefundAllocationItem({
    required this.method,
    required this.status,
    required this.amountMinor,
    required this.returnCount,
  });

  factory RefundAllocationItem.fromJson(Map<String, dynamic> json) =>
      RefundAllocationItem(
        method: json['method'] as String,
        status: json['status'] as String,
        amountMinor: _minorUnits(json['amount']),
        returnCount: _wholeNumber(json['return_count']),
      );

  final String method;
  final String status;
  final int amountMinor;
  final int returnCount;
}

class ReturnReasonItem {
  const ReturnReasonItem({
    required this.reason,
    required this.returnCount,
    required this.refundTotalMinor,
  });

  factory ReturnReasonItem.fromJson(Map<String, dynamic> json) =>
      ReturnReasonItem(
        reason: json['reason'] as String,
        returnCount: _wholeNumber(json['return_count']),
        refundTotalMinor: _minorUnits(json['refund_total']),
      );

  final String reason;
  final int returnCount;
  final int refundTotalMinor;
}

class ReturnedProductItem {
  const ReturnedProductItem({
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.quantity,
    required this.returnCount,
    required this.refundTotalMinor,
  });

  factory ReturnedProductItem.fromJson(Map<String, dynamic> json) =>
      ReturnedProductItem(
        variantId: json['variant_id'] as String,
        productName: json['product_name'] as String,
        variantName: json['variant_name'] as String,
        sku: json['sku'] as String,
        quantity: _decimal(json['quantity']),
        returnCount: _wholeNumber(json['return_count']),
        refundTotalMinor: _minorUnits(json['refund_total']),
      );

  final String variantId;
  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final int returnCount;
  final int refundTotalMinor;
}

class BranchDiscountItem {
  const BranchDiscountItem({
    required this.branchId,
    required this.branchName,
    required this.saleCount,
    required this.discountedSaleCount,
    required this.saleSubtotalMinor,
    required this.discountTotalMinor,
    this.discountRate,
  });

  factory BranchDiscountItem.fromJson(Map<String, dynamic> json) =>
      BranchDiscountItem(
        branchId: json['branch_id'] as String,
        branchName: json['branch_name'] as String,
        saleCount: _wholeNumber(json['sale_count']),
        discountedSaleCount: _wholeNumber(json['discounted_sale_count']),
        saleSubtotalMinor: _minorUnits(json['sale_subtotal']),
        discountTotalMinor: _minorUnits(json['discount_total']),
        discountRate: _nullableDecimal(json['discount_rate']),
      );

  final String branchId;
  final String branchName;
  final int saleCount;
  final int discountedSaleCount;
  final int saleSubtotalMinor;
  final int discountTotalMinor;
  final double? discountRate;
}

class SalesForecastReport {
  const SalesForecastReport({
    required this.historyStart,
    required this.historyEnd,
    required this.historyDays,
    required this.forecastStart,
    required this.forecastEnd,
    required this.forecastDays,
    required this.method,
    required this.rangeMethod,
    required this.dataQuality,
    required this.activeHistoryDays,
    required this.historicalSalesMinor,
    required this.historicalOrders,
    required this.historicalDailyAverageMinor,
    required this.trendDirection,
    required this.residualRmseMinor,
    required this.projectedSalesMinor,
    required this.projectedLowMinor,
    required this.projectedHighMinor,
    required this.projectedDailyAverageMinor,
    required this.history,
    required this.forecast,
    this.dailyTrendAmountMinor,
    this.projectedChangeRate,
  });

  factory SalesForecastReport.fromJson(
    Map<String, dynamic> json,
  ) => SalesForecastReport(
    historyStart: DateTime.parse(json['history_start'] as String),
    historyEnd: DateTime.parse(json['history_end'] as String),
    historyDays: _wholeNumber(json['history_days']),
    forecastStart: DateTime.parse(json['forecast_start'] as String),
    forecastEnd: DateTime.parse(json['forecast_end'] as String),
    forecastDays: _wholeNumber(json['forecast_days']),
    method: json['method'] as String,
    rangeMethod: json['range_method'] as String,
    dataQuality: json['data_quality'] as String,
    activeHistoryDays: _wholeNumber(json['active_history_days']),
    historicalSalesMinor: _minorUnits(json['historical_sales']),
    historicalOrders: _wholeNumber(json['historical_orders']),
    historicalDailyAverageMinor: _minorUnits(json['historical_daily_average']),
    dailyTrendAmountMinor: _nullableMinorUnits(json['daily_trend_amount']),
    trendDirection: json['trend_direction'] as String,
    residualRmseMinor: _minorUnits(json['residual_rmse']),
    projectedSalesMinor: _minorUnits(json['projected_sales']),
    projectedLowMinor: _minorUnits(json['projected_low']),
    projectedHighMinor: _minorUnits(json['projected_high']),
    projectedDailyAverageMinor: _minorUnits(json['projected_daily_average']),
    projectedChangeRate: _nullableDecimal(json['projected_change_rate']),
    history: _salesForecastHistoryPoints(json['history']),
    forecast: _salesForecastPoints(json['forecast']),
  );

  final DateTime historyStart;
  final DateTime historyEnd;
  final int historyDays;
  final DateTime forecastStart;
  final DateTime forecastEnd;
  final int forecastDays;
  final String method;
  final String rangeMethod;
  final String dataQuality;
  final int activeHistoryDays;
  final int historicalSalesMinor;
  final int historicalOrders;
  final int historicalDailyAverageMinor;
  final int? dailyTrendAmountMinor;
  final String trendDirection;
  final int residualRmseMinor;
  final int projectedSalesMinor;
  final int projectedLowMinor;
  final int projectedHighMinor;
  final int projectedDailyAverageMinor;
  final double? projectedChangeRate;
  final List<SalesForecastHistoryPoint> history;
  final List<SalesForecastPoint> forecast;
}

class SalesForecastHistoryPoint {
  const SalesForecastHistoryPoint({
    required this.date,
    required this.actualSalesMinor,
    required this.orders,
  });

  factory SalesForecastHistoryPoint.fromJson(Map<String, dynamic> json) =>
      SalesForecastHistoryPoint(
        date: DateTime.parse(json['date'] as String),
        actualSalesMinor: _minorUnits(json['actual_sales']),
        orders: _wholeNumber(json['orders']),
      );

  final DateTime date;
  final int actualSalesMinor;
  final int orders;
}

class SalesForecastPoint {
  const SalesForecastPoint({
    required this.date,
    required this.estimateMinor,
    required this.lowerEstimateMinor,
    required this.upperEstimateMinor,
  });

  factory SalesForecastPoint.fromJson(Map<String, dynamic> json) =>
      SalesForecastPoint(
        date: DateTime.parse(json['date'] as String),
        estimateMinor: _minorUnits(json['estimate']),
        lowerEstimateMinor: _minorUnits(json['lower_estimate']),
        upperEstimateMinor: _minorUnits(json['upper_estimate']),
      );

  final DateTime date;
  final int estimateMinor;
  final int lowerEstimateMinor;
  final int upperEstimateMinor;
}

class RegisterStaffPerformanceReport {
  const RegisterStaffPerformanceReport({
    required this.periodStart,
    required this.periodEnd,
    required this.grossSalesMinor,
    required this.returnedSalesMinor,
    required this.netSalesMinor,
    required this.orders,
    required this.returnsProcessed,
    required this.shiftsClosed,
    required this.balancedShifts,
    required this.overShifts,
    required this.shortShifts,
    required this.expectedCashMinor,
    required this.closingCashMinor,
    required this.netVarianceMinor,
    required this.absoluteVarianceMinor,
    required this.overageMinor,
    required this.shortageMinor,
    required this.staff,
    required this.registers,
    this.averageOrderValueMinor,
  });

  factory RegisterStaffPerformanceReport.fromJson(Map<String, dynamic> json) =>
      RegisterStaffPerformanceReport(
        periodStart: DateTime.parse(json['period_start'] as String),
        periodEnd: DateTime.parse(json['period_end'] as String),
        grossSalesMinor: _minorUnits(json['gross_sales']),
        returnedSalesMinor: _minorUnits(json['returned_sales']),
        netSalesMinor: _minorUnits(json['net_sales']),
        orders: _wholeNumber(json['orders']),
        averageOrderValueMinor: _nullableMinorUnits(
          json['average_order_value'],
        ),
        returnsProcessed: _wholeNumber(json['returns_processed']),
        shiftsClosed: _wholeNumber(json['shifts_closed']),
        balancedShifts: _wholeNumber(json['balanced_shifts']),
        overShifts: _wholeNumber(json['over_shifts']),
        shortShifts: _wholeNumber(json['short_shifts']),
        expectedCashMinor: _minorUnits(json['expected_cash']),
        closingCashMinor: _minorUnits(json['closing_cash']),
        netVarianceMinor: _minorUnits(json['net_variance']),
        absoluteVarianceMinor: _minorUnits(json['absolute_variance']),
        overageMinor: _minorUnits(json['overage']),
        shortageMinor: _minorUnits(json['shortage']),
        staff: _staffPerformanceItems(json['staff']),
        registers: _registerPerformanceItems(json['registers']),
      );

  final DateTime periodStart;
  final DateTime periodEnd;
  final int grossSalesMinor;
  final int returnedSalesMinor;
  final int netSalesMinor;
  final int orders;
  final int? averageOrderValueMinor;
  final int returnsProcessed;
  final int shiftsClosed;
  final int balancedShifts;
  final int overShifts;
  final int shortShifts;
  final int expectedCashMinor;
  final int closingCashMinor;
  final int netVarianceMinor;
  final int absoluteVarianceMinor;
  final int overageMinor;
  final int shortageMinor;
  final List<StaffPerformanceItem> staff;
  final List<RegisterPerformanceItem> registers;
}

class StaffPerformanceItem {
  const StaffPerformanceItem({
    required this.id,
    required this.name,
    required this.email,
    required this.grossSalesMinor,
    required this.returnedSalesMinor,
    required this.netSalesMinor,
    required this.orders,
    required this.returnsProcessed,
    required this.returnedAmountMinor,
    required this.shiftsClosed,
    required this.balancedShifts,
    required this.overShifts,
    required this.shortShifts,
    required this.expectedCashMinor,
    required this.closingCashMinor,
    required this.netVarianceMinor,
    required this.absoluteVarianceMinor,
    required this.overageMinor,
    required this.shortageMinor,
    this.averageOrderValueMinor,
  });

  factory StaffPerformanceItem.fromJson(Map<String, dynamic> json) =>
      StaffPerformanceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        grossSalesMinor: _minorUnits(json['gross_sales']),
        returnedSalesMinor: _minorUnits(json['returned_sales']),
        netSalesMinor: _minorUnits(json['net_sales']),
        orders: _wholeNumber(json['orders']),
        averageOrderValueMinor: _nullableMinorUnits(
          json['average_order_value'],
        ),
        returnsProcessed: _wholeNumber(json['returns_processed']),
        returnedAmountMinor: _minorUnits(json['returned_amount']),
        shiftsClosed: _wholeNumber(json['shifts_closed']),
        balancedShifts: _wholeNumber(json['balanced_shifts']),
        overShifts: _wholeNumber(json['over_shifts']),
        shortShifts: _wholeNumber(json['short_shifts']),
        expectedCashMinor: _minorUnits(json['expected_cash']),
        closingCashMinor: _minorUnits(json['closing_cash']),
        netVarianceMinor: _minorUnits(json['net_variance']),
        absoluteVarianceMinor: _minorUnits(json['absolute_variance']),
        overageMinor: _minorUnits(json['overage']),
        shortageMinor: _minorUnits(json['shortage']),
      );

  final String id;
  final String name;
  final String email;
  final int grossSalesMinor;
  final int returnedSalesMinor;
  final int netSalesMinor;
  final int orders;
  final int? averageOrderValueMinor;
  final int returnsProcessed;
  final int returnedAmountMinor;
  final int shiftsClosed;
  final int balancedShifts;
  final int overShifts;
  final int shortShifts;
  final int expectedCashMinor;
  final int closingCashMinor;
  final int netVarianceMinor;
  final int absoluteVarianceMinor;
  final int overageMinor;
  final int shortageMinor;
}

class RegisterPerformanceItem {
  const RegisterPerformanceItem({
    required this.id,
    required this.name,
    required this.code,
    required this.branchId,
    required this.branchName,
    required this.shiftsClosed,
    required this.balancedShifts,
    required this.overShifts,
    required this.shortShifts,
    required this.expectedCashMinor,
    required this.closingCashMinor,
    required this.netVarianceMinor,
    required this.absoluteVarianceMinor,
    required this.overageMinor,
    required this.shortageMinor,
  });

  factory RegisterPerformanceItem.fromJson(Map<String, dynamic> json) =>
      RegisterPerformanceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        branchId: json['branch_id'] as String,
        branchName: json['branch_name'] as String,
        shiftsClosed: _wholeNumber(json['shifts_closed']),
        balancedShifts: _wholeNumber(json['balanced_shifts']),
        overShifts: _wholeNumber(json['over_shifts']),
        shortShifts: _wholeNumber(json['short_shifts']),
        expectedCashMinor: _minorUnits(json['expected_cash']),
        closingCashMinor: _minorUnits(json['closing_cash']),
        netVarianceMinor: _minorUnits(json['net_variance']),
        absoluteVarianceMinor: _minorUnits(json['absolute_variance']),
        overageMinor: _minorUnits(json['overage']),
        shortageMinor: _minorUnits(json['shortage']),
      );

  final String id;
  final String name;
  final String code;
  final String branchId;
  final String branchName;
  final int shiftsClosed;
  final int balancedShifts;
  final int overShifts;
  final int shortShifts;
  final int expectedCashMinor;
  final int closingCashMinor;
  final int netVarianceMinor;
  final int absoluteVarianceMinor;
  final int overageMinor;
  final int shortageMinor;
}

class DailySalesPoint {
  const DailySalesPoint({
    required this.date,
    required this.totalMinor,
    required this.orders,
  });

  factory DailySalesPoint.fromJson(Map<String, dynamic> json) =>
      DailySalesPoint(
        date: DateTime.parse(json['date'] as String),
        totalMinor: _minorUnits(json['total']),
        orders: _wholeNumber(json['orders']),
      );

  final DateTime date;
  final int totalMinor;
  final int orders;
}

class PaymentTotal {
  const PaymentTotal({required this.method, required this.totalMinor});

  factory PaymentTotal.fromJson(Map<String, dynamic> json) => PaymentTotal(
    method: json['method'] as String,
    totalMinor: _minorUnits(json['total']),
  );

  final String method;
  final int totalMinor;
}

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name});

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

class ExpenseEntry {
  const ExpenseEntry({
    required this.id,
    required this.expenseNumber,
    required this.categoryName,
    required this.branchName,
    required this.entryType,
    required this.amountMinor,
    required this.taxAmountMinor,
    required this.paymentMethod,
    required this.incurredOn,
    this.vendorName,
    this.reference,
    this.notes,
    this.approvalStatus = 'approved',
    this.approvedAt,
    this.approvalNote,
  });

  factory ExpenseEntry.fromJson(Map<String, dynamic> json) {
    final category = Map<String, dynamic>.from(
      json['expense_categories'] as Map,
    );
    final branch = Map<String, dynamic>.from(json['branches'] as Map);
    return ExpenseEntry(
      id: json['id'] as String,
      expenseNumber: json['expense_number'] as String,
      categoryName: category['name'] as String,
      branchName: branch['name'] as String,
      entryType: json['entry_type'] as String,
      amountMinor: _minorUnits(json['amount']),
      taxAmountMinor: _minorUnits(json['tax_amount']),
      paymentMethod: json['payment_method'] as String,
      incurredOn: DateTime.parse(json['incurred_on'] as String),
      vendorName: json['vendor_name'] as String?,
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
      approvalStatus: json['approval_status'] as String? ?? 'approved',
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.tryParse(json['approved_at'] as String),
      approvalNote: json['approval_note'] as String?,
    );
  }

  final String id;
  final String expenseNumber;
  final String categoryName;
  final String branchName;
  final String entryType;
  final int amountMinor;
  final int taxAmountMinor;
  final String paymentMethod;
  final DateTime incurredOn;
  final String? vendorName;
  final String? reference;
  final String? notes;
  final String approvalStatus;
  final DateTime? approvedAt;
  final String? approvalNote;

  int get signedAmountMinor =>
      entryType == 'reversal' ? -amountMinor : amountMinor;
}

class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.id,
    required this.entryType,
    required this.direction,
    required this.amountMinor,
    required this.description,
    required this.occurredAt,
  });

  factory CustomerLedgerEntry.fromJson(Map<String, dynamic> json) =>
      CustomerLedgerEntry(
        id: json['id'] as String,
        entryType: json['entry_type'] as String,
        direction: json['direction'] as String,
        amountMinor: _minorUnits(json['amount']),
        description: json['description'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
      );

  final String id;
  final String entryType;
  final String direction;
  final int amountMinor;
  final String description;
  final DateTime occurredAt;

  int get signedAmountMinor =>
      direction == 'debit' ? amountMinor : -amountMinor;
}

int _minorUnits(Object? value) => (_decimal(value) * 100).round();
int _wholeNumber(Object? value) => _decimal(value).round();
double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
double? _nullableDecimal(Object? value) =>
    value == null ? null : _decimal(value);
int? _nullableMinorUnits(Object? value) =>
    value == null ? null : _minorUnits(value);
DateTime? _localDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

List<SalesBreakdownItem> _breakdownItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => SalesBreakdownItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<InventoryValuationGroup> _valuationGroups(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => InventoryValuationGroup.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<InventoryAgeingGroup> _ageingGroups(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => InventoryAgeingGroup.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<DeadStockItem> _deadStockItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) =>
              DeadStockItem.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

List<DeadStockGroup> _deadStockGroups(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) =>
              DeadStockGroup.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

List<AbcInventoryClass> _abcInventoryClasses(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) =>
              AbcInventoryClass.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

List<AbcInventoryProduct> _abcInventoryProducts(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => AbcInventoryProduct.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<InventoryTurnoverGroup> _turnoverGroups(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => InventoryTurnoverGroup.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<StockAlertItem> _stockAlertItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) =>
              StockAlertItem.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

List<StockAlertGroup> _stockAlertGroups(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) =>
              StockAlertGroup.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

List<CustomerRetentionPoint> _customerRetentionPoints(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => CustomerRetentionPoint.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<CustomerLifetimeValue> _customerLifetimeValues(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => CustomerLifetimeValue.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<CustomerCreditAgeingBucket> _customerCreditAgeingBuckets(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => CustomerCreditAgeingBucket.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<CustomerCreditExposure> _customerCreditExposures(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => CustomerCreditExposure.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<SalesTargetBranchComparison> _salesTargetBranchComparisons(
  Object? value,
) => (value as List? ?? const [])
    .map(
      (row) => SalesTargetBranchComparison.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
    )
    .toList(growable: false);

List<SalesForecastHistoryPoint> _salesForecastHistoryPoints(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => SalesForecastHistoryPoint.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<SalesForecastPoint> _salesForecastPoints(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => SalesForecastPoint.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<StaffPerformanceItem> _staffPerformanceItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => StaffPerformanceItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<RegisterPerformanceItem> _registerPerformanceItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => RegisterPerformanceItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<RefundAllocationItem> _refundAllocationItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => RefundAllocationItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<ReturnReasonItem> _returnReasonItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) =>
              ReturnReasonItem.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);

List<ReturnedProductItem> _returnedProductItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => ReturnedProductItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<BranchDiscountItem> _branchDiscountItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => BranchDiscountItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<PromotionPerformanceCampaign> _promotionPerformanceCampaigns(
  Object? value,
) => (value as List? ?? const [])
    .map(
      (row) => PromotionPerformanceCampaign.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
    )
    .toList(growable: false);

List<PromotionPerformanceDailyPoint> _promotionPerformanceDaily(
  Object? value,
) => (value as List? ?? const [])
    .map(
      (row) => PromotionPerformanceDailyPoint.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
    )
    .toList(growable: false);

List<SupplierPerformanceItem> _supplierPerformanceItems(Object? value) =>
    (value as List? ?? const [])
        .map(
          (row) => SupplierPerformanceItem.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);

List<PurchaseProductPerformanceItem> _purchaseProductPerformanceItems(
  Object? value,
) => (value as List? ?? const [])
    .map(
      (row) => PurchaseProductPerformanceItem.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
    )
    .toList(growable: false);
