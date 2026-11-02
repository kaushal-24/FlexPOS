import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard parses exact minor units and restricted profit', () {
    final dashboard = AccountingDashboard.fromJson({
      'sales_total': '1234.56',
      'tax_total': '34.56',
      'expenses_total': '200.00',
      'outstanding_receivables': '99.90',
      'order_count': 7,
      'low_stock_count': 2,
      'gross_profit': null,
      'daily_sales': [
        {'date': '2026-10-20', 'total': '1234.56', 'orders': 7},
      ],
      'payment_breakdown': [
        {'method': 'cash', 'total': '1000.00'},
      ],
      'branch_breakdown': [
        {'id': 'branch-1', 'name': 'Main', 'total': '1234.56', 'orders': 7},
      ],
      'employee_breakdown': [
        {'id': 'user-1', 'name': 'Cashier', 'total': '1234.56', 'orders': 7},
      ],
      'product_breakdown': [
        {
          'id': 'product-1',
          'name': 'Demo',
          'total': '900.25',
          'quantity': '3.5',
        },
      ],
      'category_breakdown': [
        {
          'id': null,
          'name': 'Uncategorized',
          'total': '900.25',
          'quantity': '3.5',
        },
      ],
    });

    expect(dashboard.salesTotalMinor, 123456);
    expect(dashboard.expensesTotalMinor, 20000);
    expect(dashboard.outstandingReceivablesMinor, 9990);
    expect(dashboard.grossProfitMinor, isNull);
    expect(dashboard.dailySales.single.totalMinor, 123456);
    expect(dashboard.paymentBreakdown.single.totalMinor, 100000);
    expect(dashboard.branchBreakdown.single.orderCount, 7);
    expect(dashboard.employeeBreakdown.single.name, 'Cashier');
    expect(dashboard.productBreakdown.single.totalMinor, 90025);
    expect(dashboard.productBreakdown.single.quantity, 3.5);
    expect(dashboard.categoryBreakdown.single.id, isNull);
  });

  test('expense reversals and ledger credits expose signed values', () {
    final reversal = ExpenseEntry.fromJson({
      'id': 'expense-id',
      'expense_number': 'EXR-1',
      'entry_type': 'reversal',
      'amount': '45.50',
      'tax_amount': '0',
      'payment_method': 'cash',
      'incurred_on': '2026-10-20',
      'vendor_name': null,
      'reference': null,
      'notes': 'Correction',
      'expense_categories': {'name': 'Other'},
      'branches': {'name': 'Main'},
    });
    final repayment = CustomerLedgerEntry.fromJson({
      'id': 'ledger-id',
      'entry_type': 'repayment',
      'direction': 'credit',
      'amount': '20.25',
      'description': 'Customer repayment',
      'occurred_at': '2026-10-20T08:00:00Z',
    });

    expect(reversal.signedAmountMinor, -4550);
    expect(repayment.signedAmountMinor, -2025);
  });

  test('inventory valuation parses totals and grouped balances', () {
    final report = InventoryValuationReport.fromJson({
      'total_value': '1234.5678',
      'on_hand_quantity': '96.5',
      'reserved_quantity': '4',
      'available_quantity': '92.5',
      'sku_count': 3,
      'low_stock_count': 1,
      'by_warehouse': [
        {
          'id': 'warehouse-1',
          'name': 'Main Warehouse',
          'total_value': '1234.5678',
          'on_hand_quantity': '96.5',
          'reserved_quantity': '4',
          'available_quantity': '92.5',
          'sku_count': 3,
          'low_stock_count': 1,
        },
      ],
      'by_category': [
        {
          'id': null,
          'name': 'Uncategorized',
          'total_value': '1234.5678',
          'on_hand_quantity': '96.5',
          'reserved_quantity': '4',
          'available_quantity': '92.5',
          'sku_count': 3,
          'low_stock_count': 1,
        },
      ],
    });

    expect(report.totalValueMinor, 123457);
    expect(report.onHandQuantity, 96.5);
    expect(report.availableQuantity, 92.5);
    expect(report.byWarehouse.single.name, 'Main Warehouse');
    expect(report.byWarehouse.single.totalValueMinor, 123457);
    expect(report.byCategory.single.id, isNull);
    expect(report.lowStockCount, 1);
  });

  test('inventory ageing parses FIFO layers and fills empty age buckets', () {
    final report = InventoryAgeingReport.fromJson({
      'as_of_date': '2026-10-26',
      'method': 'fifo',
      'total_quantity': '96',
      'total_value': '4800.00',
      'tracked_quantity': '96',
      'untracked_quantity': '0',
      'oldest_age_days': 6,
      'buckets': [
        {
          'key': '0_30',
          'label': '0-30 days',
          'quantity': '96',
          'total_value': '4800.00',
          'sku_count': 3,
        },
      ],
      'by_warehouse': [
        {
          'id': 'warehouse-1',
          'name': 'Main Warehouse',
          'quantity': '96',
          'total_value': '4800.00',
          'sku_count': 3,
          'oldest_age_days': 6,
          'older_than_90_quantity': '0',
        },
      ],
      'by_category': [],
    });

    expect(report.asOfDate, DateTime(2026, 10, 26));
    expect(report.totalQuantity, 96);
    expect(report.totalValueMinor, 480000);
    expect(report.buckets, hasLength(5));
    expect(report.buckets.first.quantity, 96);
    expect(report.buckets[1].quantity, 0);
    expect(report.byWarehouse.single.oldestAgeDays, 6);
    expect(report.untrackedQuantity, 0);
  });

  test('inventory turnover parses values and unavailable ratios', () {
    final report = InventoryTurnoverReport.fromJson({
      'period_start': '2026-09-26T00:00:00Z',
      'period_end': '2026-10-26T00:00:00Z',
      'period_days': 30,
      'method': 'two_point_current_average_cost',
      'net_cogs': '1000.00',
      'net_units_sold': '4',
      'beginning_inventory_value': '0',
      'ending_inventory_value': '0',
      'average_inventory_value': '0',
      'turnover_ratio': null,
      'days_on_hand': null,
      'by_product': [
        {
          'id': 'product-1',
          'name': 'Demo Product',
          'beginning_quantity': '10',
          'ending_quantity': '6',
          'beginning_inventory_value': '3000.00',
          'ending_inventory_value': '5000.00',
          'average_inventory_value': '4000.00',
          'net_units_sold': '4',
          'net_cogs': '1000.00',
          'turnover_ratio': '0.25',
          'days_on_hand': '120',
        },
      ],
      'by_category': [],
    });

    expect(report.periodStart, DateTime.utc(2026, 9, 26));
    expect(report.periodDays, 30);
    expect(report.netCogsMinor, 100000);
    expect(report.netUnitsSold, 4);
    expect(report.turnoverRatio, isNull);
    expect(report.daysOnHand, isNull);
    expect(report.byProduct.single.averageInventoryValueMinor, 400000);
    expect(report.byProduct.single.turnoverRatio, 0.25);
    expect(report.byProduct.single.daysOnHand, 120);
    expect(report.byCategory, isEmpty);
  });

  test(
    'dead stock parses inactivity, value exposure, and never-sold items',
    () {
      final report = DeadStockReport.fromJson({
        'as_of_date': '2026-10-26',
        'inactivity_days': 90,
        'stock_position_count': 3,
        'stocked_sku_count': 3,
        'dead_position_count': 1,
        'dead_sku_count': 1,
        'never_sold_sku_count': 1,
        'total_quantity': '96',
        'total_value': '4800.00',
        'dead_quantity': '10',
        'dead_reserved_quantity': '2',
        'dead_value': '750.00',
        'dead_value_rate': '15.63',
        'items': [
          {
            'warehouse_id': 'warehouse-1',
            'warehouse_name': 'Main Warehouse',
            'variant_id': 'variant-2',
            'product_name': 'Slow Product',
            'variant_name': 'Default',
            'sku': 'SLOW',
            'category_name': 'Demo Category',
            'quantity_on_hand': '10',
            'quantity_reserved': '2',
            'available_quantity': '8',
            'average_cost': '75.00',
            'stock_value': '750.00',
            'last_sale_at': null,
            'days_since_last_sale': null,
            'last_inbound_at': '2026-05-01T00:00:00Z',
            'days_since_inbound': 178,
            'never_sold': true,
          },
        ],
        'by_warehouse': [
          {
            'id': 'warehouse-1',
            'name': 'Main Warehouse',
            'position_count': 1,
            'sku_count': 1,
            'never_sold_sku_count': 1,
            'quantity': '10',
            'total_value': '750.00',
          },
        ],
        'by_category': [],
      });

      expect(report.inactivityDays, 90);
      expect(report.deadValueMinor, 75000);
      expect(report.deadValueRate, 15.63);
      expect(report.items.single.neverSold, isTrue);
      expect(report.items.single.lastSaleAt, isNull);
      expect(report.items.single.averageCostMinor, 7500);
      expect(report.byWarehouse.single.totalValueMinor, 75000);
    },
  );

  test('ABC inventory parses class and cumulative product contributions', () {
    final report = AbcInventoryReport.fromJson({
      'period_start': '2026-09-26T00:00:00Z',
      'period_end': '2026-10-26T00:00:00Z',
      'method': 'cumulative_net_sales_value',
      'a_threshold': 80,
      'b_threshold': 95,
      'product_count': 3,
      'net_quantity': '20',
      'net_sales': '1000.00',
      'inventory_quantity': '50',
      'inventory_value': '2000.00',
      'classes': [
        {
          'class': 'A',
          'label': 'A - highest contribution',
          'product_count': 1,
          'net_quantity': '10',
          'net_sales': '800.00',
          'inventory_quantity': '20',
          'inventory_value': '1000.00',
          'contribution_rate': '80.00',
        },
      ],
      'products': [
        {
          'product_id': 'product-1',
          'product_name': 'Demo Product',
          'category_id': 'category-1',
          'category_name': 'Demo Category',
          'class': 'A',
          'net_quantity': '10',
          'net_sales': '800.00',
          'contribution_rate': '80.00',
          'cumulative_contribution_rate': '80.00',
          'inventory_quantity': '20',
          'inventory_value': '1000.00',
        },
      ],
    });

    expect(report.productCount, 3);
    expect(report.netSalesMinor, 100000);
    expect(report.aThreshold, 80);
    expect(report.classes.single.abcClass, 'A');
    expect(report.classes.single.contributionRate, 80);
    expect(report.products.single.cumulativeContributionRate, 80);
    expect(report.products.single.inventoryValueMinor, 100000);
  });

  test('stock alerts parse severity, thresholds, and replenishment totals', () {
    final report = StockAlertReport.fromJson({
      'generated_at': '2026-10-26T08:06:35Z',
      'alert_count': 1,
      'affected_sku_count': 1,
      'out_of_stock_count': 0,
      'below_safety_stock_count': 0,
      'reorder_point_count': 1,
      'unconfigured_threshold_count': 0,
      'suggested_order_quantity': '4',
      'estimated_reorder_cost': '100.00',
      'items': [
        {
          'variant_id': 'variant-1',
          'product_id': 'product-1',
          'category_id': null,
          'warehouse_id': 'warehouse-1',
          'branch_id': 'branch-1',
          'product_name': 'Demo Product',
          'variant_name': 'Default',
          'sku': 'DEMO',
          'warehouse_name': 'Main Warehouse',
          'branch_name': 'Main Branch',
          'category_name': 'Uncategorized',
          'severity': 'reorder_point',
          'quantity_on_hand': '6',
          'quantity_reserved': '0',
          'available_quantity': '6',
          'reorder_point': '10',
          'safety_stock': '2',
          'target_stock': '10',
          'threshold_configured': true,
          'suggested_order_quantity': '4',
          'average_cost': '25.00',
          'suggested_order_cost': '100.00',
          'updated_at': '2026-10-26T08:00:00Z',
        },
      ],
      'by_warehouse': [
        {
          'id': 'warehouse-1',
          'name': 'Main Warehouse',
          'alert_count': 1,
          'out_of_stock_count': 0,
          'below_safety_stock_count': 0,
          'reorder_point_count': 1,
          'suggested_order_quantity': '4',
          'estimated_reorder_cost': '100.00',
        },
      ],
      'by_category': [],
    });

    expect(report.alertCount, 1);
    expect(report.affectedSkuCount, 1);
    expect(report.suggestedOrderQuantity, 4);
    expect(report.estimatedReorderCostMinor, 10000);
    expect(report.items.single.severity, 'reorder_point');
    expect(report.items.single.categoryId, isNull);
    expect(report.items.single.availableQuantity, 6);
    expect(report.items.single.thresholdConfigured, isTrue);
    expect(report.items.single.averageCostMinor, 2500);
    expect(report.items.single.suggestedOrderCostMinor, 10000);
    expect(report.byWarehouse.single.alertCount, 1);
    expect(report.byCategory, isEmpty);
  });

  test('customer analytics parse retention and net lifetime value', () {
    final report = CustomerAnalyticsReport.fromJson({
      'period_start': '2026-09-26T00:00:00Z',
      'period_end': '2026-10-26T00:00:00Z',
      'period_days': 30,
      'total_period_orders': 6,
      'identified_period_orders': 5,
      'walk_in_period_orders': 1,
      'customer_capture_rate': '83.33',
      'active_customers': 3,
      'new_customers': 1,
      'returning_customers': 2,
      'repeat_customers': 2,
      'retention_rate': '66.67',
      'repeat_customer_rate': '66.67',
      'lifetime_customer_count': 4,
      'total_lifetime_value': '5000.00',
      'average_lifetime_value': '1250.00',
      'identified_period_net_revenue': '3000.00',
      'monthly_retention': [
        {
          'month': '2026-10-01',
          'active_customers': 3,
          'new_customers': 1,
          'returning_customers': 2,
          'retention_rate': '66.67',
          'net_revenue': '3000.00',
        },
      ],
      'top_customers': [
        {
          'id': 'customer-1',
          'name': 'Demo Customer',
          'phone': '9999999999',
          'email': 'demo@example.com',
          'first_purchase_at': '2026-01-01T10:00:00Z',
          'last_purchase_at': '2026-10-24T10:00:00Z',
          'lifetime_order_count': 4,
          'lifetime_gross_sales': '3000.00',
          'lifetime_refunds': '500.00',
          'net_lifetime_value': '2500.00',
          'average_order_value': '625.00',
          'period_order_count': 2,
          'period_net_revenue': '1000.00',
          'period_status': 'returning',
          'lifetime_days': 296,
          'days_since_last_purchase': 2,
        },
      ],
    });

    expect(report.customerCaptureRate, 83.33);
    expect(report.retentionRate, 66.67);
    expect(report.totalLifetimeValueMinor, 500000);
    expect(report.averageLifetimeValueMinor, 125000);
    expect(report.averageIdentifiedOrderValueMinor, 60000);
    expect(report.averageOrdersPerActiveCustomer, closeTo(1.6667, 0.0001));
    expect(report.monthlyRetention.single.returningCustomers, 2);
    expect(report.monthlyRetention.single.netRevenueMinor, 300000);
    expect(report.topCustomers.single.netLifetimeValueMinor, 250000);
    expect(report.topCustomers.single.lifetimeRefundsMinor, 50000);
    expect(report.topCustomers.single.periodStatus, 'returning');
  });

  test('customer credit ageing parses buckets and customer exposure', () {
    final report = CustomerCreditAgeingReport.fromJson({
      'as_of_date': '2026-10-26',
      'age_basis': 'credit_sale_or_adjustment_date',
      'total_receivables': '525.00',
      'customer_count': 1,
      'open_invoice_count': 3,
      'open_adjustment_count': 0,
      'oldest_age_days': 100,
      'weighted_average_age_days': '27.619',
      'older_than_60_amount': '25.00',
      'older_than_60_rate': '4.76',
      'total_credit_limit': '1000.00',
      'credit_limit_utilization': '52.50',
      'over_limit_customer_count': 0,
      'unlimited_customer_count': 0,
      'unapplied_credit_adjustments': '0',
      'buckets': [
        {
          'key': '0_30',
          'label': '0-30 days',
          'amount': '300.00',
          'customer_count': 1,
          'item_count': 1,
        },
      ],
      'customers': [
        {
          'id': 'customer-1',
          'code': 'CUST-1',
          'name': 'Demo Customer',
          'phone': null,
          'email': null,
          'credit_limit': '1000.00',
          'outstanding_amount': '525.00',
          'available_credit': '475.00',
          'over_limit_amount': '0',
          'credit_limit_utilization': '52.50',
          'open_invoice_count': 3,
          'open_adjustment_count': 0,
          'age_0_30': '300.00',
          'age_31_60': '200.00',
          'age_61_90': '0',
          'age_91_plus': '25.00',
          'oldest_age_days': 100,
          'weighted_average_age_days': '27.619',
        },
      ],
    });

    expect(report.asOfDate, DateTime(2026, 10, 26));
    expect(report.totalReceivablesMinor, 52500);
    expect(report.olderThan60Minor, 2500);
    expect(report.creditLimitUtilization, 52.5);
    expect(report.buckets.single.amountMinor, 30000);
    expect(report.customers.single.outstandingAmountMinor, 52500);
    expect(report.customers.single.age91PlusMinor, 2500);
    expect(report.customers.single.oldestAgeDays, 100);
  });

  test('sales target comparison parses optional targets and prior period', () {
    final report = SalesTargetComparisonReport.fromJson({
      'period_start': '2026-10-20',
      'period_end': '2026-10-26',
      'period_days': 7,
      'comparison_start': '2026-10-13',
      'comparison_end': '2026-10-19',
      'current_sales': '580.00',
      'previous_sales': '400.00',
      'sales_change': '180.00',
      'sales_change_rate': '45.00',
      'current_orders': 4,
      'previous_orders': 2,
      'order_change_rate': '100.00',
      'current_average_order_value': '145.00',
      'previous_average_order_value': '200.00',
      'target_amount': '1000.00',
      'target_gap': '-420.00',
      'target_achievement_rate': '58.00',
      'targeted_branch_count': 1,
      'accessible_branch_count': 2,
      'branches': [
        {
          'id': 'branch-1',
          'name': 'Main Branch',
          'target_id': 'target-1',
          'target_amount': '1000.00',
          'target_notes': 'Launch month',
          'current_sales': '580.00',
          'previous_sales': '400.00',
          'sales_change': '180.00',
          'sales_change_rate': '45.00',
          'current_orders': 4,
          'previous_orders': 2,
          'target_gap': '-420.00',
          'target_achievement_rate': '58.00',
        },
        {
          'id': 'branch-2',
          'name': 'Second Branch',
          'target_id': null,
          'target_amount': null,
          'target_notes': null,
          'current_sales': '0',
          'previous_sales': '0',
          'sales_change': '0',
          'sales_change_rate': null,
          'current_orders': 0,
          'previous_orders': 0,
          'target_gap': null,
          'target_achievement_rate': null,
        },
      ],
    });

    expect(report.periodDays, 7);
    expect(report.comparisonStart, DateTime(2026, 10, 13));
    expect(report.currentSalesMinor, 58000);
    expect(report.salesChangeRate, 45);
    expect(report.targetAmountMinor, 100000);
    expect(report.targetGapMinor, -42000);
    expect(report.targetAchievementRate, 58);
    expect(report.branches.first.targetNotes, 'Launch month');
    expect(report.branches.last.targetAmountMinor, isNull);
    expect(report.branches.last.salesChangeRate, isNull);
  });

  test('sales forecast parses history, estimate range, and quality', () {
    final report = SalesForecastReport.fromJson({
      'history_start': '2026-09-28',
      'history_end': '2026-10-27',
      'history_days': 30,
      'forecast_start': '2026-10-28',
      'forecast_end': '2026-11-26',
      'forecast_days': 30,
      'method': 'weekday_seasonality_linear_trend',
      'range_method': 'approximate_95_percent_residual_range',
      'data_quality': 'limited',
      'active_history_days': 2,
      'historical_sales': '580.00',
      'historical_orders': 4,
      'historical_daily_average': '19.33',
      'daily_trend_amount': null,
      'trend_direction': 'insufficient_data',
      'residual_rmse': '79.72',
      'projected_sales': '530.64',
      'projected_low': '0',
      'projected_high': '1386.42',
      'projected_daily_average': '17.69',
      'projected_change_rate': '-8.51',
      'history': [
        {'date': '2026-10-20', 'actual_sales': '440.00', 'orders': 3},
      ],
      'forecast': [
        {
          'date': '2026-10-28',
          'estimate': '12.50',
          'lower_estimate': '0',
          'upper_estimate': '168.74',
        },
      ],
    });

    expect(report.historyDays, 30);
    expect(report.dataQuality, 'limited');
    expect(report.historicalSalesMinor, 58000);
    expect(report.dailyTrendAmountMinor, isNull);
    expect(report.projectedHighMinor, 138642);
    expect(report.projectedChangeRate, -8.51);
    expect(report.history.single.actualSalesMinor, 44000);
    expect(report.forecast.single.estimateMinor, 1250);
    expect(report.forecast.single.upperEstimateMinor, 16874);
  });

  test('register and staff performance parses sales and cash variance', () {
    final report = RegisterStaffPerformanceReport.fromJson({
      'period_start': '2026-10-20T00:00:00Z',
      'period_end': '2026-10-28T00:00:00Z',
      'gross_sales': '580.00',
      'returned_sales': '30.00',
      'net_sales': '550.00',
      'orders': 4,
      'average_order_value': '137.50',
      'returns_processed': 1,
      'shifts_closed': 2,
      'balanced_shifts': 1,
      'over_shifts': 1,
      'short_shifts': 0,
      'expected_cash': '500.00',
      'closing_cash': '505.00',
      'net_variance': '5.00',
      'absolute_variance': '5.00',
      'overage': '5.00',
      'shortage': '0',
      'staff': [
        {
          'id': 'user-1',
          'name': 'Demo Cashier',
          'email': 'cashier@example.com',
          'gross_sales': '580.00',
          'returned_sales': '30.00',
          'net_sales': '550.00',
          'orders': 4,
          'average_order_value': '137.50',
          'returns_processed': 1,
          'returned_amount': '30.00',
          'shifts_closed': 2,
          'balanced_shifts': 1,
          'over_shifts': 1,
          'short_shifts': 0,
          'expected_cash': '500.00',
          'closing_cash': '505.00',
          'net_variance': '5.00',
          'absolute_variance': '5.00',
          'overage': '5.00',
          'shortage': '0',
        },
      ],
      'registers': [
        {
          'id': 'register-1',
          'name': 'Main Register',
          'code': 'MAIN',
          'branch_id': 'branch-1',
          'branch_name': 'Main Branch',
          'shifts_closed': 2,
          'balanced_shifts': 1,
          'over_shifts': 1,
          'short_shifts': 0,
          'expected_cash': '500.00',
          'closing_cash': '505.00',
          'net_variance': '5.00',
          'absolute_variance': '5.00',
          'overage': '5.00',
          'shortage': '0',
        },
      ],
    });

    expect(report.netSalesMinor, 55000);
    expect(report.averageOrderValueMinor, 13750);
    expect(report.netVarianceMinor, 500);
    expect(report.staff.single.returnsProcessed, 1);
    expect(report.staff.single.absoluteVarianceMinor, 500);
    expect(report.registers.single.branchName, 'Main Branch');
    expect(report.registers.single.overShifts, 1);
  });
}
