import 'dart:typed_data';

import 'package:flexpos/core/data/repository_contract.dart';
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final accountingRepositoryProvider = Provider<AccountingRepository>(
  (ref) => AccountingRepository(ref.watch(supabaseClientProvider)),
);

final accountingDashboardProvider = FutureProvider.autoDispose
    .family<AccountingDashboard, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view')) {
        throw StateError('Report viewing permission required.');
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchDashboard(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final inventoryValuationProvider =
    FutureProvider.autoDispose<InventoryValuationReport?>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchInventoryValuation(workspace.businessId);
    });

final inventoryAgeingProvider =
    FutureProvider.autoDispose<InventoryAgeingReport?>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchInventoryAgeing(workspace.businessId, DateTime.now());
    });

final deadStockReportProvider = FutureProvider.autoDispose<DeadStockReport?>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('reports.view') ||
      !workspace.permissionCodes.contains('inventory.view')) {
    return null;
  }
  return ref
      .watch(accountingRepositoryProvider)
      .fetchDeadStock(workspace.businessId, DateTime.now(), 90);
});

final abcInventoryReportProvider = FutureProvider.autoDispose
    .family<AbcInventoryReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('sales.view') ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchAbcInventory(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final inventoryTurnoverProvider = FutureProvider.autoDispose
    .family<InventoryTurnoverReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('reports.profit') ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchInventoryTurnover(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final stockAlertReportProvider = FutureProvider.autoDispose<StockAlertReport?>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('reports.view') ||
      !workspace.permissionCodes.contains('inventory.view')) {
    return null;
  }
  return ref
      .watch(accountingRepositoryProvider)
      .fetchStockAlerts(workspace.businessId);
});

final stockAlertNotificationsProvider =
    FutureProvider.autoDispose<List<StockAlertNotification>?>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('inventory.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchStockAlertNotifications(workspace.businessId);
    });

final customerAnalyticsProvider = FutureProvider.autoDispose
    .family<CustomerAnalyticsReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('customers.view') ||
          !workspace.permissionCodes.contains('sales.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchCustomerAnalytics(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final customerCreditAgeingProvider =
    FutureProvider.autoDispose<CustomerCreditAgeingReport?>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('customer_credit.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchCustomerCreditAgeing(workspace.businessId, DateTime.now());
    });

final salesTargetComparisonProvider = FutureProvider.autoDispose
    .family<SalesTargetComparisonReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('sales.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchSalesTargetComparison(workspace.businessId, period);
    });

final salesForecastProvider = FutureProvider.autoDispose
    .family<SalesForecastReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('sales.view')) {
        return null;
      }
      final historyPeriod = period.dayCount >= 7
          ? period
          : ReportPeriod(
              start: period.end.subtract(const Duration(days: 6)),
              end: period.end,
            );
      return ref
          .watch(accountingRepositoryProvider)
          .fetchSalesForecast(
            workspace.businessId,
            historyPeriod,
            period.dayCount.clamp(7, 90).toInt(),
          );
    });

final registerStaffPerformanceProvider = FutureProvider.autoDispose
    .family<RegisterStaffPerformanceReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('sales.view') ||
          !workspace.permissionCodes.contains('staff.view') ||
          !workspace.permissionCodes.contains('registers.manage')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchRegisterStaffPerformance(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final salesAdjustmentsProvider = FutureProvider.autoDispose
    .family<SalesAdjustmentsReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('sales.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchSalesAdjustments(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final promotionPerformanceProvider = FutureProvider.autoDispose
    .family<PromotionPerformanceReport?, ReportPeriod>((ref, period) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('sales.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchPromotionPerformance(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final purchaseSupplierPerformanceProvider = FutureProvider.autoDispose
    .family<PurchaseSupplierPerformanceReport?, ReportPeriod>((
      ref,
      period,
    ) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('reports.view') ||
          !workspace.permissionCodes.contains('purchases.view')) {
        return null;
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchPurchaseSupplierPerformance(
            workspace.businessId,
            period.startUtc,
            period.endExclusiveUtc,
          );
    });

final expenseCategoriesProvider =
    FutureProvider.autoDispose<List<ExpenseCategory>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('expenses.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchExpenseCategories(workspace.businessId);
    });

final expensesProvider = FutureProvider.autoDispose<List<ExpenseEntry>>((
  ref,
) async {
  final workspace = ref.watch(selectedWorkspaceProvider).value;
  if (workspace == null ||
      !workspace.permissionCodes.contains('expenses.view')) {
    return const [];
  }
  return ref
      .watch(accountingRepositoryProvider)
      .fetchExpenses(workspace.businessId);
});

final accountingAccountsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('accounting.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchAccountingAccounts(workspace.businessId);
    });

final accountingJournalEntriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('accounting.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchJournalEntries(workspace.businessId);
    });

final accountingFiscalYearsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('accounting.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchFiscalYears(workspace.businessId);
    });

final cashBankAccountsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('accounting.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchCashBankAccounts(workspace.businessId);
    });

final recurringExpensesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('expenses.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchRecurringExpenses(workspace.businessId);
    });

final taxProfilesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('tax.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchTaxProfiles(workspace.businessId);
    });

final accountingSubledgerPostingsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('accounting.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchSubledgerPostings(workspace.businessId);
    });

final bankReconciliationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('accounting.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchBankReconciliations(workspace.businessId);
    });

final taxAdjustmentNotesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('tax.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchTaxAdjustmentNotes(workspace.businessId);
    });

final customerLedgerProvider = FutureProvider.autoDispose
    .family<List<CustomerLedgerEntry>, String>((ref, customerId) async {
      final workspace = ref.watch(selectedWorkspaceProvider).value;
      if (workspace == null ||
          !workspace.permissionCodes.contains('customer_credit.view')) {
        return const [];
      }
      return ref
          .watch(accountingRepositoryProvider)
          .fetchCustomerLedger(workspace.businessId, customerId);
    });

class AccountingRepository implements SupabaseRepositoryContract {
  AccountingRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  Future<AccountingDashboard> fetchDashboard(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_business_dashboard_with_net_profit',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return AccountingDashboard.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<InventoryValuationReport> fetchInventoryValuation(
    String businessId,
  ) async {
    final result = await _client.rpc(
      'get_inventory_valuation_report',
      params: {'target_business_id': businessId},
    );
    return InventoryValuationReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<void> setInventoryValuationMethod({
    required String businessId,
    required String method,
    double? standardCost,
  }) async {
    await _client.rpc(
      'set_inventory_valuation_method',
      params: {
        'target_business_id': businessId,
        'selected_method': method,
        'target_standard_cost': standardCost,
      },
    );
  }

  Future<InventoryAgeingReport> fetchInventoryAgeing(
    String businessId,
    DateTime asOfDate,
  ) async {
    final result = await _client.rpc(
      'get_inventory_ageing_report',
      params: {
        'target_business_id': businessId,
        'target_as_of_date': _date(asOfDate),
      },
    );
    return InventoryAgeingReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<DeadStockReport> fetchDeadStock(
    String businessId,
    DateTime asOfDate,
    int inactivityDays,
  ) async {
    final result = await _client.rpc(
      'get_dead_stock_report',
      params: {
        'target_business_id': businessId,
        'target_as_of_date': _date(asOfDate),
        'inactivity_days': inactivityDays,
      },
    );
    return DeadStockReport.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<AbcInventoryReport> fetchAbcInventory(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_abc_inventory_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return AbcInventoryReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<InventoryTurnoverReport> fetchInventoryTurnover(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_inventory_turnover_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return InventoryTurnoverReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<StockAlertReport> fetchStockAlerts(String businessId) async {
    final result = await _client.rpc(
      'get_stock_alert_report',
      params: {'target_business_id': businessId},
    );
    return StockAlertReport.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<List<StockAlertNotification>> fetchStockAlertNotifications(
    String businessId,
  ) async {
    final result = await _client.rpc(
      'get_inventory_stock_alert_notifications',
      params: {'target_business_id': businessId},
    );
    final payload = Map<String, dynamic>.from(result as Map);
    return (payload['items'] as List? ?? const [])
        .map(
          (item) => StockAlertNotification.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> refreshStockAlertNotifications(String businessId) async {
    await _client.rpc(
      'refresh_inventory_stock_alert_notifications',
      params: {'target_business_id': businessId},
    );
  }

  Future<void> acknowledgeStockAlertNotification(String notificationId) async {
    await _client.rpc(
      'acknowledge_inventory_stock_alert',
      params: {'target_notification_id': notificationId},
    );
  }

  Future<CustomerAnalyticsReport> fetchCustomerAnalytics(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_customer_analytics_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return CustomerAnalyticsReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<CustomerCreditAgeingReport> fetchCustomerCreditAgeing(
    String businessId,
    DateTime asOfDate,
  ) async {
    final result = await _client.rpc(
      'get_customer_credit_ageing_report',
      params: {
        'target_business_id': businessId,
        'target_as_of_date': _date(asOfDate),
      },
    );
    return CustomerCreditAgeingReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<SalesTargetComparisonReport> fetchSalesTargetComparison(
    String businessId,
    ReportPeriod period,
  ) async {
    final result = await _client.rpc(
      'get_sales_target_comparison_report',
      params: {
        'target_business_id': businessId,
        'period_start': period.startUtc.toIso8601String(),
        'period_end': period.endExclusiveUtc.toIso8601String(),
        'target_starts_on': _date(period.start),
        'target_ends_on': _date(period.end),
      },
    );
    return SalesTargetComparisonReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<Map<String, dynamic>> upsertSalesTarget({
    required String businessId,
    required String branchId,
    required DateTime startsOn,
    required DateTime endsOn,
    required int amountMinor,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'upsert_sales_target',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_starts_on': _date(startsOn),
        'target_ends_on': _date(endsOn),
        'target_amount': amountMinor / 100,
        'target_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<SalesForecastReport> fetchSalesForecast(
    String businessId,
    ReportPeriod historyPeriod,
    int forecastDays,
  ) async {
    final result = await _client.rpc(
      'get_sales_forecast_report',
      params: {
        'target_business_id': businessId,
        'history_start': historyPeriod.startUtc.toIso8601String(),
        'history_end': historyPeriod.endExclusiveUtc.toIso8601String(),
        'history_starts_on': _date(historyPeriod.start),
        'history_ends_on': _date(historyPeriod.end),
        'forecast_days': forecastDays,
      },
    );
    return SalesForecastReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<RegisterStaffPerformanceReport> fetchRegisterStaffPerformance(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_register_staff_performance_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return RegisterStaffPerformanceReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<SalesAdjustmentsReport> fetchSalesAdjustments(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_sales_adjustments_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return SalesAdjustmentsReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<PromotionPerformanceReport> fetchPromotionPerformance(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_promotion_performance_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return PromotionPerformanceReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<PurchaseSupplierPerformanceReport> fetchPurchaseSupplierPerformance(
    String businessId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _client.rpc(
      'get_purchase_supplier_performance_report',
      params: {
        'target_business_id': businessId,
        'period_start': start.toIso8601String(),
        'period_end': end.toIso8601String(),
      },
    );
    return PurchaseSupplierPerformanceReport.fromJson(
      Map<String, dynamic>.from(result as Map),
    );
  }

  Future<List<ExpenseCategory>> fetchExpenseCategories(
    String businessId,
  ) async {
    final rows = await _client
        .from('expense_categories')
        .select('id,name')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');
    return rows
        .map((row) => ExpenseCategory.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ExpenseEntry>> fetchExpenses(String businessId) async {
    final rows = await _client
        .from('expenses')
        .select(
          'id,expense_number,entry_type,amount,tax_amount,payment_method,'
          'vendor_name,reference,notes,incurred_on,approval_status,approved_at,approval_note,'
          'expense_categories(name),branches(name)',
        )
        .eq('business_id', businessId)
        .order('incurred_on', ascending: false)
        .order('created_at', ascending: false)
        .limit(200);
    return rows
        .map((row) => ExpenseEntry.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchAccountingAccounts(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_accounts')
        .select('id,code,name,account_type,parent_id,is_system,is_active')
        .eq('business_id', businessId)
        .order('code');
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchCashBankAccounts(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_cash_bank_accounts')
        .select(
          'id,name,account_type,account_number_masked,opening_balance,is_active,ledger_account_id',
        )
        .eq('business_id', businessId)
        .order('name');
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchRecurringExpenses(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_recurring_expenses')
        .select(
          'id,branch_id,category_id,description,amount,tax_amount,payment_method,vendor_name,frequency,next_run_on,end_on,is_active,last_generated_on,expense_categories(name),branches(name)',
        )
        .eq('business_id', businessId)
        .order('next_run_on');
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchTaxProfiles(String businessId) async {
    final rows = await _client
        .from('accounting_tax_profiles')
        .select(
          'id,branch_id,legal_name,gstin,state_code,default_place_of_supply,effective_from,effective_to,is_active,tax_regime,country_code,registration_number,default_tax_rate,tax_inclusive',
        )
        .eq('business_id', businessId)
        .order('effective_from', ascending: false);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchSubledgerPostings(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_subledger_postings')
        .select('id,subledger_type,source_id,journal_entry_id,memo,posted_at')
        .eq('business_id', businessId)
        .order('posted_at', ascending: false)
        .limit(200);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchBankReconciliations(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_bank_reconciliations')
        .select(
          'id,cash_bank_account_id,statement_start,statement_end,opening_balance,closing_balance,reconciled_amount,difference_amount,status,notes,completed_at,accounting_cash_bank_accounts(name,account_type)',
        )
        .eq('business_id', businessId)
        .order('statement_end', ascending: false)
        .limit(100);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchTaxAdjustmentNotes(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_tax_adjustment_notes')
        .select(
          'id,branch_id,note_number,note_type,scope,source_id,taxable_amount,cgst_amount,sgst_amount,igst_amount,reason,note_date,status,posted_at',
        )
        .eq('business_id', businessId)
        .order('note_date', ascending: false)
        .limit(100);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchTrialBalance(
    String businessId,
    DateTime asOf,
  ) async {
    final result = await _client.rpc(
      'get_trial_balance',
      params: {
        'target_business_id': businessId,
        'target_as_of_date': _date(asOf),
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchJournalEntries(
    String businessId,
  ) async {
    final rows = await _client
        .from('accounting_journal_entries')
        .select('id,entry_number,entry_date,source_type,memo,status,created_at')
        .eq('business_id', businessId)
        .order('entry_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchFiscalYears(String businessId) async {
    final rows = await _client
        .from('accounting_fiscal_years')
        .select('id,label,starts_on,ends_on,status,closed_at')
        .eq('business_id', businessId)
        .order('starts_on', ascending: false);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> createFiscalYear({
    required String businessId,
    required String label,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    await _client.rpc(
      'create_accounting_fiscal_year',
      params: {
        'target_business_id': businessId,
        'target_label': label.trim(),
        'target_starts_on': _date(startsOn),
        'target_ends_on': _date(endsOn),
      },
    );
  }

  Future<void> updateFiscalYear({
    required String id,
    required String businessId,
    required String label,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    await _client
        .from('accounting_fiscal_years')
        .update({
          'label': label.trim(),
          'starts_on': _date(startsOn),
          'ends_on': _date(endsOn),
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteFiscalYear({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('accounting_fiscal_years')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId)
        .eq('status', 'open');
  }

  Future<Map<String, dynamic>> reverseJournalEntry({
    required String journalEntryId,
    required String reason,
  }) async {
    final result = await _client.rpc(
      'reverse_journal_entry',
      params: {
        'target_journal_entry_id': journalEntryId,
        'correction_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> getGstSummary({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await _client.rpc(
      'get_gst_summary',
      params: {
        'target_business_id': businessId,
        'period_start': start.toUtc().toIso8601String(),
        'period_end': end.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> fetchFinancialStatements({
    required String businessId,
    required DateTime start,
    required DateTime end,
  }) async {
    final result = await _client.rpc(
      'get_financial_statements',
      params: {
        'target_business_id': businessId,
        'period_start': _date(start),
        'period_end': _date(end),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> getTaxInvoiceBreakdown(String saleId) async {
    final result = await _client.rpc(
      'get_tax_invoice_breakdown',
      params: {'target_sale_id': saleId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> createJournalEntry({
    required String businessId,
    required DateTime entryDate,
    required String memo,
    required List<Map<String, dynamic>> lines,
    String sourceType = 'manual',
    String? sourceId,
  }) async {
    final result = await _client.rpc(
      'create_journal_entry',
      params: {
        'target_business_id': businessId,
        'target_entry_date': _date(entryDate),
        'target_memo': memo.trim(),
        'target_source_type': sourceType,
        'target_source_id': sourceId,
        'target_lines': lines,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> createCashBankAccount({
    required String businessId,
    required String name,
    required String accountType,
    String? maskedNumber,
    int openingBalanceMinor = 0,
    String? ledgerAccountId,
  }) async {
    await _client.from('accounting_cash_bank_accounts').insert({
      'business_id': businessId,
      'name': name.trim(),
      'account_type': accountType,
      'account_number_masked': _nullable(maskedNumber),
      'opening_balance': openingBalanceMinor / 100,
      'ledger_account_id': ledgerAccountId,
    });
  }

  Future<void> updateCashBankAccount({
    required String id,
    required String businessId,
    required String name,
    required String accountType,
    String? maskedNumber,
    int openingBalanceMinor = 0,
    String? ledgerAccountId,
    required bool isActive,
  }) async {
    await _client
        .from('accounting_cash_bank_accounts')
        .update({
          'name': name.trim(),
          'account_type': accountType,
          'account_number_masked': _nullable(maskedNumber),
          'opening_balance': openingBalanceMinor / 100,
          'ledger_account_id': ledgerAccountId,
          'is_active': isActive,
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteCashBankAccount({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('accounting_cash_bank_accounts')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> createAccountingAccount({
    required String businessId,
    required String code,
    required String name,
    required String accountType,
  }) async {
    await _client.from('accounting_accounts').insert({
      'business_id': businessId,
      'code': code.trim(),
      'name': name.trim(),
      'account_type': accountType,
    });
  }

  Future<void> updateAccountingAccount({
    required String id,
    required String businessId,
    required String code,
    required String name,
    required String accountType,
    required bool isActive,
  }) async {
    await _client
        .from('accounting_accounts')
        .update({
          'code': code.trim(),
          'name': name.trim(),
          'account_type': accountType,
          'is_active': isActive,
        })
        .eq('id', id)
        .eq('business_id', businessId)
        .eq('is_system', false);
  }

  Future<void> deleteAccountingAccount({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('accounting_accounts')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId)
        .eq('is_system', false);
  }

  Future<void> createTaxProfile({
    required String businessId,
    String? branchId,
    required String legalName,
    String? gstin,
    required String stateCode,
    String? placeOfSupply,
    required DateTime effectiveFrom,
    String taxRegime = 'gst',
    String countryCode = 'IN',
    String? registrationNumber,
    double defaultTaxRate = 0,
    bool taxInclusive = false,
  }) async {
    await _client.from('accounting_tax_profiles').insert({
      'business_id': businessId,
      'branch_id': branchId,
      'legal_name': legalName.trim(),
      'gstin': _nullable(gstin)?.toUpperCase(),
      'state_code': stateCode.trim(),
      'default_place_of_supply': _nullable(placeOfSupply),
      'effective_from': _date(effectiveFrom),
      'tax_regime': taxRegime,
      'country_code': countryCode.trim().toUpperCase(),
      'registration_number': _nullable(registrationNumber),
      'default_tax_rate': defaultTaxRate,
      'tax_inclusive': taxInclusive,
    });
  }

  Future<void> updateTaxProfile({
    required String id,
    required String businessId,
    String? branchId,
    required String legalName,
    String? gstin,
    required String stateCode,
    String? placeOfSupply,
    required DateTime effectiveFrom,
    String taxRegime = 'gst',
    String countryCode = 'IN',
    String? registrationNumber,
    double defaultTaxRate = 0,
    bool taxInclusive = false,
    required bool isActive,
  }) async {
    await _client
        .from('accounting_tax_profiles')
        .update({
          'branch_id': branchId,
          'legal_name': legalName.trim(),
          'gstin': _nullable(gstin)?.toUpperCase(),
          'state_code': stateCode.trim(),
          'default_place_of_supply': _nullable(placeOfSupply),
          'effective_from': _date(effectiveFrom),
          'tax_regime': taxRegime,
          'country_code': countryCode.trim().toUpperCase(),
          'registration_number': _nullable(registrationNumber),
          'default_tax_rate': defaultTaxRate,
          'tax_inclusive': taxInclusive,
          'is_active': isActive,
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteTaxProfile({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('accounting_tax_profiles')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<Map<String, dynamic>> syncOperationalLedger(String businessId) async {
    final result = await _client.rpc(
      'sync_operational_ledger',
      params: {'target_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> createBankReconciliation({
    required String businessId,
    required String cashBankAccountId,
    required DateTime statementStart,
    required DateTime statementEnd,
    required int openingBalanceMinor,
    required int closingBalanceMinor,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'create_bank_reconciliation',
      params: {
        'target_business_id': businessId,
        'target_cash_bank_account_id': cashBankAccountId,
        'target_statement_start': _date(statementStart),
        'target_statement_end': _date(statementEnd),
        'target_opening_balance': openingBalanceMinor / 100,
        'target_closing_balance': closingBalanceMinor / 100,
        'target_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> autoReconcileBankReconciliation(
    String reconciliationId,
  ) async {
    final result = await _client.rpc(
      'auto_reconcile_bank_reconciliation',
      params: {'target_reconciliation_id': reconciliationId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> reopenBankReconciliation(
    String reconciliationId,
  ) async {
    final result = await _client.rpc(
      'reopen_bank_reconciliation',
      params: {'target_reconciliation_id': reconciliationId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> createTaxAdjustmentNote({
    required String businessId,
    String? branchId,
    required String noteNumber,
    required String noteType,
    required String scope,
    required int taxableAmountMinor,
    required int cgstMinor,
    required int sgstMinor,
    required int igstMinor,
    required String reason,
    required DateTime noteDate,
    String? sourceId,
  }) async {
    final result = await _client.rpc(
      'create_tax_adjustment_note',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_note_number': noteNumber.trim(),
        'target_note_type': noteType,
        'target_scope': scope,
        'target_taxable_amount': taxableAmountMinor / 100,
        'target_cgst': cgstMinor / 100,
        'target_sgst': sgstMinor / 100,
        'target_igst': igstMinor / 100,
        'target_reason': reason.trim(),
        'target_note_date': _date(noteDate),
        'target_source_id': sourceId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> postTaxAdjustmentNote(String noteId) async {
    final result = await _client.rpc(
      'post_tax_adjustment_note_to_ledger',
      params: {'target_note_id': noteId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> createRecurringExpense({
    required String businessId,
    required String branchId,
    required String categoryId,
    required String description,
    required int amountMinor,
    required int taxMinor,
    required String paymentMethod,
    String? vendorName,
    required String frequency,
    required DateTime nextRunOn,
    DateTime? endOn,
  }) async {
    await _client.rpc(
      'create_recurring_expense',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_category_id': categoryId,
        'target_description': description.trim(),
        'target_amount': amountMinor / 100,
        'target_tax_amount': taxMinor / 100,
        'target_payment_method': paymentMethod,
        'target_vendor_name': _nullable(vendorName),
        'target_frequency': frequency,
        'target_next_run_on': _date(nextRunOn),
        'target_end_on': endOn == null ? null : _date(endOn),
      },
    );
  }

  Future<void> updateRecurringExpense({
    required String id,
    required String businessId,
    required String branchId,
    required String categoryId,
    required String description,
    required int amountMinor,
    required int taxMinor,
    required String paymentMethod,
    String? vendorName,
    required String frequency,
    required DateTime nextRunOn,
    DateTime? endOn,
    required bool isActive,
  }) async {
    await _client
        .from('accounting_recurring_expenses')
        .update({
          'branch_id': branchId,
          'category_id': categoryId,
          'description': description.trim(),
          'amount': amountMinor / 100,
          'tax_amount': taxMinor / 100,
          'payment_method': paymentMethod,
          'vendor_name': _nullable(vendorName),
          'frequency': frequency,
          'next_run_on': _date(nextRunOn),
          'end_on': endOn == null ? null : _date(endOn),
          'is_active': isActive,
        })
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<void> deleteRecurringExpense({
    required String id,
    required String businessId,
  }) async {
    await _client
        .from('accounting_recurring_expenses')
        .delete()
        .eq('id', id)
        .eq('business_id', businessId);
  }

  Future<Map<String, dynamic>> runRecurringExpenses(String businessId) async {
    final result = await _client.rpc(
      'run_due_recurring_expenses',
      params: {'target_business_id': businessId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> requestExpenseApproval({
    required String expenseId,
    String? note,
  }) async {
    await _client.rpc(
      'request_expense_approval',
      params: {'target_expense_id': expenseId, 'target_note': _nullable(note)},
    );
  }

  Future<void> decideExpenseApproval({
    required String expenseId,
    required bool approve,
    String? note,
  }) async {
    await _client.rpc(
      'decide_expense_approval',
      params: {
        'target_expense_id': expenseId,
        'approve_request': approve,
        'target_note': _nullable(note),
      },
    );
  }

  Future<void> uploadExpenseAttachment({
    required String businessId,
    required String expenseId,
    required String fileName,
    required List<int> bytes,
    String? mimeType,
  }) async {
    final path =
        '$businessId/$expenseId/${DateTime.now().microsecondsSinceEpoch}_$fileName';
    await _client.storage
        .from('expense-attachments')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      await _client.from('expense_attachments').insert({
        'business_id': businessId,
        'expense_id': expenseId,
        'storage_path': path,
        'file_name': fileName,
        'mime_type': mimeType,
        'file_size': bytes.length,
      });
    } catch (_) {
      await _client.storage.from('expense-attachments').remove([path]);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchExpenseAttachments(
    String businessId,
    String expenseId,
  ) async {
    final rows = await _client
        .from('expense_attachments')
        .select('id,file_name,storage_path,mime_type,file_size,created_at')
        .eq('business_id', businessId)
        .eq('expense_id', expenseId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> closeAccountingPeriod({
    required String businessId,
    required DateTime startsOn,
    required DateTime endsOn,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'close_accounting_period',
      params: {
        'target_business_id': businessId,
        'target_starts_on': _date(startsOn),
        'target_ends_on': _date(endsOn),
        'target_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<CustomerLedgerEntry>> fetchCustomerLedger(
    String businessId,
    String customerId,
  ) async {
    final rows = await _client
        .from('customer_ledger_entries')
        .select('id,entry_type,direction,amount,description,occurred_at')
        .eq('business_id', businessId)
        .eq('customer_id', customerId)
        .order('occurred_at', ascending: false)
        .limit(200);
    return rows
        .map(
          (row) => CustomerLedgerEntry.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createExpense({
    required String businessId,
    required String branchId,
    required String categoryId,
    required int amountMinor,
    required int taxAmountMinor,
    required String paymentMethod,
    required DateTime incurredOn,
    String? vendorName,
    String? reference,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'create_expense',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_category_id': categoryId,
        'operation_id': createUuidV4(),
        'expense_amount': amountMinor / 100,
        'expense_tax_amount': taxAmountMinor / 100,
        'expense_payment_method': paymentMethod,
        'expense_vendor_name': _nullable(vendorName),
        'expense_reference': _nullable(reference),
        'expense_notes': _nullable(notes),
        'expense_incurred_on': _date(incurredOn),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> reverseExpense({
    required String expenseId,
    required String reason,
  }) async {
    final result = await _client.rpc(
      'reverse_expense',
      params: {
        'target_expense_id': expenseId,
        'operation_id': createUuidV4(),
        'reversal_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> recordCustomerRepayment({
    required String businessId,
    required String branchId,
    required String customerId,
    required int amountMinor,
    required String paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final result = await _client.rpc(
      'record_customer_repayment',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_customer_id': customerId,
        'operation_id': createUuidV4(),
        'repayment_amount': amountMinor / 100,
        'repayment_method': paymentMethod,
        'repayment_reference': _nullable(reference),
        'repayment_notes': _nullable(notes),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> createCustomerCreditAdjustment({
    required String businessId,
    required String branchId,
    required String customerId,
    required String adjustmentType,
    required int amountMinor,
    required String description,
  }) async {
    final result = await _client.rpc(
      'create_customer_credit_adjustment',
      params: {
        'target_business_id': businessId,
        'target_branch_id': branchId,
        'target_customer_id': customerId,
        'target_operation_id': createUuidV4(),
        'target_adjustment_type': adjustmentType,
        'target_amount': amountMinor / 100,
        'target_description': description.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }
}

String? _nullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
