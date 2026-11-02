import 'dart:convert';

import 'package:excel_plus/excel_plus.dart' as xlsx;
import 'package:flexpos/features/accounting/application/accounting_report_export.dart';
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dashboard = AccountingDashboard(
    salesTotalMinor: 123456,
    taxTotalMinor: 12345,
    expensesTotalMinor: 25000,
    outstandingReceivablesMinor: 7000,
    orderCount: 8,
    lowStockCount: 3,
    grossProfitMinor: 42000,
    netProfitMinor: 17000,
    netProfitMargin: 13.77,
    dailySales: [
      DailySalesPoint(
        date: DateTime(2026, 10, 24),
        totalMinor: 123456,
        orders: 8,
      ),
    ],
    paymentBreakdown: const [
      PaymentTotal(method: 'bank_transfer', totalMinor: 123456),
    ],
    branchBreakdown: const [
      SalesBreakdownItem(
        id: 'branch-1',
        name: 'Main Branch',
        totalMinor: 123456,
        orderCount: 8,
      ),
    ],
    employeeBreakdown: const [
      SalesBreakdownItem(
        id: 'user-1',
        name: 'Demo Cashier',
        totalMinor: 123456,
        orderCount: 8,
      ),
    ],
    productBreakdown: const [
      SalesBreakdownItem(
        id: 'product-1',
        name: 'Demo Product',
        totalMinor: 123456,
        quantity: 3.5,
      ),
    ],
    categoryBreakdown: const [
      SalesBreakdownItem(
        id: 'category-1',
        name: 'Demo Category',
        totalMinor: 123456,
        quantity: 3.5,
      ),
    ],
  );
  const inventoryValuation = InventoryValuationReport(
    totalValueMinor: 480000,
    onHandQuantity: 96,
    reservedQuantity: 4,
    availableQuantity: 92,
    skuCount: 3,
    lowStockCount: 1,
    byWarehouse: [
      InventoryValuationGroup(
        id: 'warehouse-1',
        name: 'Main Warehouse',
        totalValueMinor: 480000,
        onHandQuantity: 96,
        reservedQuantity: 4,
        availableQuantity: 92,
        skuCount: 3,
        lowStockCount: 1,
      ),
    ],
    byCategory: [
      InventoryValuationGroup(
        name: 'Uncategorized',
        totalValueMinor: 480000,
        onHandQuantity: 96,
        reservedQuantity: 4,
        availableQuantity: 92,
        skuCount: 3,
        lowStockCount: 1,
      ),
    ],
  );
  final inventoryAgeing = InventoryAgeingReport(
    asOfDate: DateTime(2026, 10, 26),
    method: 'fifo',
    totalQuantity: 96,
    totalValueMinor: 480000,
    trackedQuantity: 96,
    untrackedQuantity: 0,
    oldestAgeDays: 6,
    buckets: const [
      InventoryAgeBucket(
        key: '0_30',
        label: '0-30 days',
        quantity: 96,
        totalValueMinor: 480000,
        skuCount: 3,
      ),
    ],
    byWarehouse: const [
      InventoryAgeingGroup(
        id: 'warehouse-1',
        name: 'Main Warehouse',
        quantity: 96,
        totalValueMinor: 480000,
        skuCount: 3,
        oldestAgeDays: 6,
        olderThan90Quantity: 0,
      ),
    ],
    byCategory: const [
      InventoryAgeingGroup(
        name: 'Uncategorized',
        quantity: 96,
        totalValueMinor: 480000,
        skuCount: 3,
        oldestAgeDays: 6,
        olderThan90Quantity: 0,
      ),
    ],
  );
  final deadStock = DeadStockReport(
    asOfDate: DateTime(2026, 10, 26),
    inactivityDays: 90,
    stockPositionCount: 3,
    stockedSkuCount: 3,
    deadPositionCount: 1,
    deadSkuCount: 1,
    neverSoldSkuCount: 1,
    totalQuantity: 96,
    totalValueMinor: 480000,
    deadQuantity: 10,
    deadReservedQuantity: 2,
    deadValueMinor: 75000,
    deadValueRate: 15.63,
    items: [
      DeadStockItem(
        warehouseId: 'warehouse-1',
        warehouseName: 'Main Warehouse',
        variantId: 'variant-2',
        productName: 'Slow Product',
        variantName: 'Default',
        sku: 'SLOW',
        categoryName: 'Demo Category',
        quantityOnHand: 10,
        quantityReserved: 2,
        availableQuantity: 8,
        averageCostMinor: 7500,
        stockValueMinor: 75000,
        neverSold: true,
        lastInboundAt: DateTime.utc(2026, 5, 1),
        daysSinceInbound: 178,
      ),
    ],
    byWarehouse: const [
      DeadStockGroup(
        id: 'warehouse-1',
        name: 'Main Warehouse',
        positionCount: 1,
        skuCount: 1,
        neverSoldSkuCount: 1,
        quantity: 10,
        totalValueMinor: 75000,
      ),
    ],
    byCategory: const [
      DeadStockGroup(
        id: 'category-1',
        name: 'Demo Category',
        positionCount: 1,
        skuCount: 1,
        neverSoldSkuCount: 1,
        quantity: 10,
        totalValueMinor: 75000,
      ),
    ],
  );
  final abcInventory = AbcInventoryReport(
    periodStart: DateTime.utc(2026, 9, 26),
    periodEnd: DateTime.utc(2026, 10, 26),
    method: 'cumulative_net_sales_value',
    aThreshold: 80,
    bThreshold: 95,
    productCount: 3,
    netQuantity: 20,
    netSalesMinor: 100000,
    inventoryQuantity: 50,
    inventoryValueMinor: 200000,
    classes: const [
      AbcInventoryClass(
        abcClass: 'A',
        label: 'A - highest contribution',
        productCount: 1,
        netQuantity: 10,
        netSalesMinor: 80000,
        inventoryQuantity: 20,
        inventoryValueMinor: 100000,
        contributionRate: 80,
      ),
      AbcInventoryClass(
        abcClass: 'B',
        label: 'B - medium contribution',
        productCount: 1,
        netQuantity: 6,
        netSalesMinor: 15000,
        inventoryQuantity: 15,
        inventoryValueMinor: 60000,
        contributionRate: 15,
      ),
      AbcInventoryClass(
        abcClass: 'C',
        label: 'C - lowest contribution',
        productCount: 1,
        netQuantity: 4,
        netSalesMinor: 5000,
        inventoryQuantity: 15,
        inventoryValueMinor: 40000,
        contributionRate: 5,
      ),
    ],
    products: const [
      AbcInventoryProduct(
        productId: 'product-1',
        productName: 'Demo Product',
        categoryId: 'category-1',
        categoryName: 'Demo Category',
        abcClass: 'A',
        netQuantity: 10,
        netSalesMinor: 80000,
        contributionRate: 80,
        cumulativeContributionRate: 80,
        inventoryQuantity: 20,
        inventoryValueMinor: 100000,
      ),
    ],
  );
  final inventoryTurnover = InventoryTurnoverReport(
    periodStart: DateTime.utc(2026, 9, 26),
    periodEnd: DateTime.utc(2026, 10, 26),
    periodDays: 30,
    method: 'two_point_current_average_cost',
    netCogsMinor: 100000,
    netUnitsSold: 4,
    beginningInventoryValueMinor: 300000,
    endingInventoryValueMinor: 500000,
    averageInventoryValueMinor: 400000,
    turnoverRatio: 0.25,
    daysOnHand: 120,
    byProduct: const [
      InventoryTurnoverGroup(
        id: 'product-1',
        name: 'Demo Product',
        beginningQuantity: 10,
        endingQuantity: 6,
        beginningInventoryValueMinor: 300000,
        endingInventoryValueMinor: 500000,
        averageInventoryValueMinor: 400000,
        netUnitsSold: 4,
        netCogsMinor: 100000,
        turnoverRatio: 0.25,
        daysOnHand: 120,
      ),
    ],
    byCategory: const [
      InventoryTurnoverGroup(
        id: 'category-1',
        name: 'Demo Category',
        beginningQuantity: 10,
        endingQuantity: 6,
        beginningInventoryValueMinor: 300000,
        endingInventoryValueMinor: 500000,
        averageInventoryValueMinor: 400000,
        netUnitsSold: 4,
        netCogsMinor: 100000,
        turnoverRatio: 0.25,
        daysOnHand: 120,
      ),
    ],
  );
  final stockAlerts = StockAlertReport(
    generatedAt: DateTime(2026, 10, 26, 13, 30),
    alertCount: 1,
    affectedSkuCount: 1,
    outOfStockCount: 0,
    belowSafetyStockCount: 0,
    reorderPointCount: 1,
    unconfiguredThresholdCount: 0,
    suggestedOrderQuantity: 4,
    estimatedReorderCostMinor: 10000,
    items: [
      StockAlertItem(
        variantId: 'variant-1',
        productId: 'product-1',
        warehouseId: 'warehouse-1',
        branchId: 'branch-1',
        productName: 'Demo Product',
        variantName: 'Default',
        sku: 'DEMO',
        warehouseName: 'Main Warehouse',
        branchName: 'Main Branch',
        categoryName: 'Demo Category',
        severity: 'reorder_point',
        quantityOnHand: 6,
        quantityReserved: 0,
        availableQuantity: 6,
        reorderPoint: 10,
        safetyStock: 2,
        targetStock: 10,
        thresholdConfigured: true,
        suggestedOrderQuantity: 4,
        averageCostMinor: 2500,
        suggestedOrderCostMinor: 10000,
        updatedAt: DateTime(2026, 10, 26, 13),
      ),
    ],
    byWarehouse: const [
      StockAlertGroup(
        id: 'warehouse-1',
        name: 'Main Warehouse',
        alertCount: 1,
        outOfStockCount: 0,
        belowSafetyStockCount: 0,
        reorderPointCount: 1,
        suggestedOrderQuantity: 4,
        estimatedReorderCostMinor: 10000,
      ),
    ],
    byCategory: const [
      StockAlertGroup(
        id: 'category-1',
        name: 'Demo Category',
        alertCount: 1,
        outOfStockCount: 0,
        belowSafetyStockCount: 0,
        reorderPointCount: 1,
        suggestedOrderQuantity: 4,
        estimatedReorderCostMinor: 10000,
      ),
    ],
  );
  final customerAnalytics = CustomerAnalyticsReport(
    periodStart: DateTime.utc(2026, 9, 26),
    periodEnd: DateTime.utc(2026, 10, 26),
    periodDays: 30,
    totalPeriodOrders: 6,
    identifiedPeriodOrders: 5,
    walkInPeriodOrders: 1,
    customerCaptureRate: 83.33,
    activeCustomers: 3,
    newCustomers: 1,
    returningCustomers: 2,
    repeatCustomers: 2,
    retentionRate: 66.67,
    repeatCustomerRate: 66.67,
    lifetimeCustomerCount: 4,
    totalLifetimeValueMinor: 500000,
    averageLifetimeValueMinor: 125000,
    identifiedPeriodNetRevenueMinor: 300000,
    monthlyRetention: [
      CustomerRetentionPoint(
        month: DateTime(2026, 10),
        activeCustomers: 3,
        newCustomers: 1,
        returningCustomers: 2,
        retentionRate: 66.67,
        netRevenueMinor: 300000,
      ),
    ],
    topCustomers: [
      CustomerLifetimeValue(
        id: 'customer-1',
        name: 'Demo Customer',
        phone: '9999999999',
        email: 'demo@example.com',
        firstPurchaseAt: DateTime(2026, 1, 1),
        lastPurchaseAt: DateTime(2026, 10, 24),
        lifetimeOrderCount: 4,
        lifetimeGrossSalesMinor: 300000,
        lifetimeRefundsMinor: 50000,
        netLifetimeValueMinor: 250000,
        averageOrderValueMinor: 62500,
        periodOrderCount: 2,
        periodNetRevenueMinor: 100000,
        periodStatus: 'returning',
        lifetimeDays: 296,
        daysSinceLastPurchase: 2,
      ),
    ],
  );
  final customerCreditAgeing = CustomerCreditAgeingReport(
    asOfDate: DateTime(2026, 10, 26),
    ageBasis: 'credit_sale_or_adjustment_date',
    totalReceivablesMinor: 52500,
    customerCount: 1,
    openInvoiceCount: 3,
    openAdjustmentCount: 0,
    oldestAgeDays: 100,
    weightedAverageAgeDays: 27.619,
    olderThan60Minor: 2500,
    olderThan60Rate: 4.76,
    totalCreditLimitMinor: 100000,
    creditLimitUtilization: 52.5,
    overLimitCustomerCount: 0,
    unlimitedCustomerCount: 0,
    unappliedCreditAdjustmentsMinor: 0,
    buckets: const [
      CustomerCreditAgeingBucket(
        key: '0_30',
        label: '0-30 days',
        amountMinor: 30000,
        customerCount: 1,
        itemCount: 1,
      ),
      CustomerCreditAgeingBucket(
        key: '31_60',
        label: '31-60 days',
        amountMinor: 20000,
        customerCount: 1,
        itemCount: 1,
      ),
      CustomerCreditAgeingBucket(
        key: '61_90',
        label: '61-90 days',
        amountMinor: 0,
        customerCount: 0,
        itemCount: 0,
      ),
      CustomerCreditAgeingBucket(
        key: '91_plus',
        label: '91+ days',
        amountMinor: 2500,
        customerCount: 1,
        itemCount: 1,
      ),
    ],
    customers: const [
      CustomerCreditExposure(
        id: 'customer-1',
        code: 'CUST-1',
        name: 'Demo Customer',
        creditLimitMinor: 100000,
        outstandingAmountMinor: 52500,
        availableCreditMinor: 47500,
        overLimitAmountMinor: 0,
        creditLimitUtilization: 52.5,
        openInvoiceCount: 3,
        openAdjustmentCount: 0,
        age0To30Minor: 30000,
        age31To60Minor: 20000,
        age61To90Minor: 0,
        age91PlusMinor: 2500,
        oldestAgeDays: 100,
        weightedAverageAgeDays: 27.619,
      ),
    ],
  );
  final salesTargetComparison = SalesTargetComparisonReport(
    periodStart: DateTime(2026, 9, 26),
    periodEnd: DateTime(2026, 10, 25),
    periodDays: 30,
    comparisonStart: DateTime(2026, 8, 27),
    comparisonEnd: DateTime(2026, 9, 25),
    currentSalesMinor: 123456,
    previousSalesMinor: 100000,
    salesChangeMinor: 23456,
    salesChangeRate: 23.46,
    currentOrders: 8,
    previousOrders: 5,
    orderChangeRate: 60,
    currentAverageOrderValueMinor: 15432,
    previousAverageOrderValueMinor: 20000,
    targetAmountMinor: 200000,
    targetGapMinor: -76544,
    targetAchievementRate: 61.73,
    targetedBranchCount: 1,
    accessibleBranchCount: 1,
    branches: const [
      SalesTargetBranchComparison(
        id: 'branch-1',
        name: 'Main Branch',
        targetId: 'target-1',
        targetAmountMinor: 200000,
        targetNotes: 'October plan',
        currentSalesMinor: 123456,
        previousSalesMinor: 100000,
        salesChangeMinor: 23456,
        salesChangeRate: 23.46,
        currentOrders: 8,
        previousOrders: 5,
        targetGapMinor: -76544,
        targetAchievementRate: 61.73,
      ),
    ],
  );
  final salesForecast = SalesForecastReport(
    historyStart: DateTime(2026, 9, 26),
    historyEnd: DateTime(2026, 10, 25),
    historyDays: 30,
    forecastStart: DateTime(2026, 10, 26),
    forecastEnd: DateTime(2026, 11, 24),
    forecastDays: 30,
    method: 'weekday_seasonality_linear_trend',
    rangeMethod: 'approximate_95_percent_residual_range',
    dataQuality: 'sufficient',
    activeHistoryDays: 20,
    historicalSalesMinor: 123456,
    historicalOrders: 8,
    historicalDailyAverageMinor: 4115,
    dailyTrendAmountMinor: 125,
    trendDirection: 'rising',
    residualRmseMinor: 5000,
    projectedSalesMinor: 150000,
    projectedLowMinor: 110000,
    projectedHighMinor: 190000,
    projectedDailyAverageMinor: 5000,
    projectedChangeRate: 21.51,
    history: [
      SalesForecastHistoryPoint(
        date: DateTime(2026, 10, 25),
        actualSalesMinor: 123456,
        orders: 8,
      ),
    ],
    forecast: [
      SalesForecastPoint(
        date: DateTime(2026, 10, 26),
        estimateMinor: 5000,
        lowerEstimateMinor: 2500,
        upperEstimateMinor: 7500,
      ),
    ],
  );
  final registerStaffPerformance = RegisterStaffPerformanceReport(
    periodStart: DateTime(2026, 9, 26),
    periodEnd: DateTime(2026, 10, 26),
    grossSalesMinor: 123456,
    returnedSalesMinor: 10000,
    netSalesMinor: 113456,
    orders: 8,
    averageOrderValueMinor: 14182,
    returnsProcessed: 1,
    shiftsClosed: 3,
    balancedShifts: 1,
    overShifts: 1,
    shortShifts: 1,
    expectedCashMinor: 100000,
    closingCashMinor: 100250,
    netVarianceMinor: 250,
    absoluteVarianceMinor: 750,
    overageMinor: 500,
    shortageMinor: 250,
    staff: const [
      StaffPerformanceItem(
        id: 'user-1',
        name: 'Demo Cashier',
        email: 'cashier@example.com',
        grossSalesMinor: 123456,
        returnedSalesMinor: 10000,
        netSalesMinor: 113456,
        orders: 8,
        averageOrderValueMinor: 14182,
        returnsProcessed: 1,
        returnedAmountMinor: 10000,
        shiftsClosed: 3,
        balancedShifts: 1,
        overShifts: 1,
        shortShifts: 1,
        expectedCashMinor: 100000,
        closingCashMinor: 100250,
        netVarianceMinor: 250,
        absoluteVarianceMinor: 750,
        overageMinor: 500,
        shortageMinor: 250,
      ),
    ],
    registers: const [
      RegisterPerformanceItem(
        id: 'register-1',
        name: 'Main Register',
        code: 'MAIN',
        branchId: 'branch-1',
        branchName: 'Main Branch',
        shiftsClosed: 3,
        balancedShifts: 1,
        overShifts: 1,
        shortShifts: 1,
        expectedCashMinor: 100000,
        closingCashMinor: 100250,
        netVarianceMinor: 250,
        absoluteVarianceMinor: 750,
        overageMinor: 500,
        shortageMinor: 250,
      ),
    ],
  );
  final salesAdjustments = SalesAdjustmentsReport(
    periodStart: DateTime(2026, 9, 26),
    periodEnd: DateTime(2026, 10, 26),
    saleCount: 8,
    discountedSaleCount: 3,
    saleSubtotalMinor: 140000,
    discountTotalMinor: 16544,
    lineDiscountTotalMinor: 10000,
    orderDiscountTotalMinor: 6544,
    discountRate: 11.82,
    returnCount: 1,
    returnedQuantity: 1,
    returnedSubtotalMinor: 11000,
    returnedDiscountTotalMinor: 1000,
    returnedTaxTotalMinor: 0,
    refundTotalMinor: 10000,
    settledRefundTotalMinor: 10000,
    pendingRefundTotalMinor: 0,
    failedRefundTotalMinor: 0,
    creditNoteTotalMinor: 0,
    refundAllocations: const [
      RefundAllocationItem(
        method: 'cash',
        status: 'settled',
        amountMinor: 10000,
        returnCount: 1,
      ),
    ],
    returnReasons: const [
      ReturnReasonItem(
        reason: 'Damaged item',
        returnCount: 1,
        refundTotalMinor: 10000,
      ),
    ],
    returnedProducts: const [
      ReturnedProductItem(
        variantId: 'variant-1',
        productName: 'Demo Product',
        variantName: 'Default',
        sku: 'DEMO',
        quantity: 1,
        returnCount: 1,
        refundTotalMinor: 10000,
      ),
    ],
    branchDiscounts: const [
      BranchDiscountItem(
        branchId: 'branch-1',
        branchName: 'Main Branch',
        saleCount: 8,
        discountedSaleCount: 3,
        saleSubtotalMinor: 140000,
        discountTotalMinor: 16544,
        discountRate: 11.82,
      ),
    ],
  );
  final purchaseSupplierPerformance = PurchaseSupplierPerformanceReport(
    periodStart: DateTime(2026, 9, 26),
    periodEnd: DateTime(2026, 10, 26),
    orderCount: 5,
    receivedOrderCount: 2,
    partiallyReceivedOrderCount: 1,
    openOrderCount: 1,
    cancelledOrderCount: 1,
    overdueOrderCount: 1,
    onTimeOrderCount: 1,
    lateOrderCount: 1,
    measuredDeliveryCount: 2,
    onTimeRate: 50,
    orderedTotalMinor: 500000,
    receivedCostMinor: 300000,
    orderedQuantity: 100,
    receivedQuantity: 60,
    outstandingQuantity: 40,
    outstandingItemCostMinor: 200000,
    receiptCount: 3,
    averageLeadDays: 4.5,
    suppliers: const [
      SupplierPerformanceItem(
        supplierId: 'supplier-1',
        supplierName: 'Demo Supplier',
        orderCount: 5,
        receivedOrderCount: 2,
        openOrderCount: 2,
        cancelledOrderCount: 1,
        overdueOrderCount: 1,
        onTimeOrderCount: 1,
        lateOrderCount: 1,
        onTimeRate: 50,
        orderedTotalMinor: 500000,
        receivedCostMinor: 300000,
        orderedQuantity: 100,
        receivedQuantity: 60,
        outstandingQuantity: 40,
        averageLeadDays: 4.5,
      ),
    ],
    products: const [
      PurchaseProductPerformanceItem(
        variantId: 'variant-1',
        productName: 'Demo Product',
        variantName: 'Default',
        sku: 'DEMO',
        supplierCount: 1,
        orderCount: 5,
        orderedQuantity: 100,
        receivedQuantity: 60,
        outstandingQuantity: 40,
        orderedItemCostMinor: 500000,
      ),
    ],
  );
  final generatedAt = DateTime(2026, 10, 25, 9, 30);

  test('report period normalizes dates and uses an exclusive end boundary', () {
    final period = ReportPeriod(
      start: DateTime(2026, 10, 23, 18, 30),
      end: DateTime(2026, 10, 25, 8, 45),
    );

    expect(period.start, DateTime(2026, 10, 23));
    expect(period.end, DateTime(2026, 10, 25));
    expect(period.dayCount, 3);
    expect(period.endExclusiveUtc, DateTime(2026, 10, 26).toUtc());
    expect(period, ReportPeriod.lastDays(3, now: DateTime(2026, 10, 25, 22)));
  });

  test('CSV report contains every visible report section and escapes cells', () {
    final bytes = buildAccountingReportCsv(
      data: dashboard,
      businessName: '=Demo, Ltd',
      currencyCode: 'INR',
      periodLabel: 'Sep 26, 2026 - Oct 25, 2026',
      generatedAt: generatedAt,
      inventoryValuation: inventoryValuation,
      inventoryAgeing: inventoryAgeing,
      deadStock: deadStock,
      abcInventory: abcInventory,
      inventoryTurnover: inventoryTurnover,
      stockAlerts: stockAlerts,
      customerAnalytics: customerAnalytics,
      customerCreditAgeing: customerCreditAgeing,
      salesTargetComparison: salesTargetComparison,
      salesForecast: salesForecast,
      registerStaffPerformance: registerStaffPerformance,
      salesAdjustments: salesAdjustments,
      purchaseSupplierPerformance: purchaseSupplierPerformance,
    );
    final csv = utf8.decode(bytes).replaceFirst('\uFEFF', '');

    expect(csv, contains("Business,\"'=Demo, Ltd\""));
    expect(csv, contains('Net sales,1234.56'));
    expect(csv, contains('Net profit,170.00'));
    expect(csv, contains('Net profit margin,13.77%'));
    expect(csv, contains('2026-10-24,8,1234.56'));
    expect(csv, contains('Bank Transfer,1234.56'));
    expect(csv, contains('Sales by branch'));
    expect(csv, contains('Main Branch,8,1234.56'));
    expect(csv, contains('Demo Product,3.50,1234.56'));
    expect(csv, contains('Inventory valuation'));
    expect(csv, contains('Current value (INR),4800.00'));
    expect(csv, contains('Main Warehouse,3,96,4,92,1,4800.00'));
    expect(csv, contains('Inventory ageing'));
    expect(csv, contains('0-30 days,3,96,4800.00'));
    expect(csv, contains('Main Warehouse,3,96,6,0,4800.00'));
    expect(csv, contains('Dead stock analysis'));
    expect(csv, contains('Dead-stock value (INR),750.00'));
    expect(
      csv,
      contains(
        'Slow Product,Default,SLOW,Main Warehouse,Demo Category,10,2,8,75.00,750.00,Never,,2026-05-01,Yes',
      ),
    );
    expect(csv, contains('ABC inventory analysis'));
    expect(csv, contains('A,1,10,800.00,80.00%,20,1000.00'));
    expect(
      csv,
      contains(
        'Demo Product,Demo Category,A,10,800.00,80.00%,80.00%,20,1000.00',
      ),
    );
    expect(csv, contains('Inventory turnover'));
    expect(csv, contains('Net COGS (INR),1000.00'));
    expect(csv, contains('Demo Product,4,1000.00,4000.00,0.25,120.00'));
    expect(csv, contains('Stock alerts'));
    expect(csv, contains('Estimated reorder cost (INR),100.00'));
    expect(
      csv,
      contains(
        'Demo Product,Default,DEMO,At reorder point,Main Branch,'
        'Main Warehouse,6,10,2,4,100.00,Yes',
      ),
    );
    expect(csv, contains('Customer retention and lifetime value'));
    expect(csv, contains('Customer capture rate,83.33%'));
    expect(csv, contains('Identified average order value (INR),600.00'));
    expect(csv, contains('Demo Customer,Returning,4,2500.00,625.00,2,1000.00'));
    expect(csv, contains('Customer credit ageing'));
    expect(csv, contains('Outstanding receivables (INR),525.00'));
    expect(csv, contains('91+ days,25.00,1,1'));
    expect(csv, contains('Demo Customer,525.00,1000.00,52.50%'));
    expect(csv, contains('Sales targets and period comparison'));
    expect(csv, contains('Net sales (INR),1234.56,1000.00,23.46%'));
    expect(
      csv,
      contains(
        "Main Branch,1234.56,1000.00,23.46%,2000.00,61.73%,'-765.44,8,October plan",
      ),
    );
    expect(csv, contains('Sales forecast'));
    expect(csv, contains('Projected sales (INR),1500.00'));
    expect(csv, contains('2026-10-26,50.00,25.00,75.00'));
    expect(csv, contains('Register reconciliation and staff performance'));
    expect(csv, contains('Net variance (INR),2.50'));
    expect(
      csv,
      contains(
        'Demo Cashier,cashier@example.com,8,1134.56,141.82,1,3,1,1,1,2.50,7.50',
      ),
    );
    expect(
      csv,
      contains(
        'Main Branch,Main Register,MAIN,3,1,1,1,1000.00,1002.50,2.50,7.50',
      ),
    );
    expect(csv, contains('Sales adjustments: discounts, returns, and refunds'));
    expect(csv, contains('Total discounts (INR),165.44'));
    expect(csv, contains('Cash,Settled,1,100.00'));
    expect(csv, contains('Demo Product,Default,DEMO,1,1,100.00'));
    expect(csv, contains('Purchase and supplier performance'));
    expect(csv, contains('Ordered total (INR),5000.00'));
    expect(csv, contains('Demo Supplier,5,2,2,1,1,5000.00,3000.00'));
    expect(csv, contains('Demo Product,Default,DEMO,1,5,100,60,40,5000.00'));
  });

  test('Excel report contains typed cells and every report section', () {
    final bytes = buildAccountingReportExcel(
      data: dashboard,
      businessName: '=Demo, Ltd',
      currencyCode: 'INR',
      periodLabel: 'Sep 26, 2026 - Oct 25, 2026',
      generatedAt: generatedAt,
      inventoryValuation: inventoryValuation,
      inventoryAgeing: inventoryAgeing,
      deadStock: deadStock,
      abcInventory: abcInventory,
      inventoryTurnover: inventoryTurnover,
      stockAlerts: stockAlerts,
      customerAnalytics: customerAnalytics,
      customerCreditAgeing: customerCreditAgeing,
      salesTargetComparison: salesTargetComparison,
      salesForecast: salesForecast,
      registerStaffPerformance: registerStaffPerformance,
      salesAdjustments: salesAdjustments,
      purchaseSupplierPerformance: purchaseSupplierPerformance,
    );

    expect(bytes.length, greaterThan(1000));
    expect(bytes.take(2), orderedEquals([0x50, 0x4b]));

    final workbook = xlsx.Excel.decodeBytes(bytes);
    expect(workbook.tables.keys, contains('Business report'));
    final sheet = workbook.tables['Business report']!;
    expect(
      sheet.cell(xlsx.CellIndex.indexByString('A1')).value,
      xlsx.TextCellValue('FlexPOS business report'),
    );
    expect(
      sheet.cell(xlsx.CellIndex.indexByString('B2')).value,
      xlsx.TextCellValue('=Demo, Ltd'),
    );
    expect(
      sheet.cell(xlsx.CellIndex.indexByString('B8')).value,
      xlsx.DoubleCellValue(1234.56),
    );
    expect(
      sheet.cell(xlsx.CellIndex.indexByString('A20')).value,
      isA<xlsx.DateCellValue>(),
    );

    final firstColumnText = sheet.rows
        .map((row) => row.isEmpty ? null : row.first?.value)
        .whereType<xlsx.TextCellValue>()
        .map((value) => value.value.text)
        .toSet();
    expect(firstColumnText, contains('Inventory valuation'));
    expect(firstColumnText, contains('Dead stock analysis'));
    expect(firstColumnText, contains('ABC inventory analysis'));
    expect(
      firstColumnText,
      contains('Register reconciliation and staff performance'),
    );
    expect(
      firstColumnText,
      contains('Sales adjustments: discounts, returns, and refunds'),
    );
    expect(firstColumnText, contains('Purchase and supplier performance'));
  });

  test('PDF report generator emits a valid A4 report', () async {
    final bytes = await buildAccountingReportPdf(
      data: dashboard,
      businessName: 'Demo Store',
      currencyCode: 'INR',
      periodLabel: 'Sep 26, 2026 - Oct 25, 2026',
      generatedAt: generatedAt,
      inventoryValuation: inventoryValuation,
      inventoryAgeing: inventoryAgeing,
      deadStock: deadStock,
      abcInventory: abcInventory,
      inventoryTurnover: inventoryTurnover,
      stockAlerts: stockAlerts,
      customerAnalytics: customerAnalytics,
      customerCreditAgeing: customerCreditAgeing,
      salesTargetComparison: salesTargetComparison,
      salesForecast: salesForecast,
      registerStaffPerformance: registerStaffPerformance,
      salesAdjustments: salesAdjustments,
      purchaseSupplierPerformance: purchaseSupplierPerformance,
    );

    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}
