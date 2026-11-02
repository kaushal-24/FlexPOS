import 'dart:math' as math;

import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/features/accounting/application/accounting_report_export.dart';
import 'package:flexpos/features/accounting/application/sales_aggregation.dart';
import 'package:flexpos/features/accounting/data/accounting_repository.dart';
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _ReportExportFormat { csv, excel, pdf }

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int? _presetDays = 30;
  late ReportPeriod _period;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _period = ReportPeriod.lastDays(_presetDays!);
  }

  String get _periodLabel {
    final formatter = DateFormat.yMMMd();
    if (_period.start == _period.end) {
      return formatter.format(_period.start);
    }
    return '${formatter.format(_period.start)} - ${formatter.format(_period.end)}';
  }

  void _selectPreset(int days) {
    setState(() {
      _presetDays = days;
      _period = ReportPeriod.lastDays(days);
    });
  }

  Future<void> _selectCustomPeriod() async {
    final today = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(start: _period.start, end: _period.end),
      helpText: 'Select report period',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _presetDays = null;
      _period = ReportPeriod(start: selected.start, end: selected.end);
    });
  }

  Future<void> _exportReport({
    required AccountingDashboard data,
    required String businessName,
    required String currencyCode,
    required _ReportExportFormat format,
    InventoryValuationReport? inventoryValuation,
    InventoryAgeingReport? inventoryAgeing,
    DeadStockReport? deadStock,
    AbcInventoryReport? abcInventory,
    InventoryTurnoverReport? inventoryTurnover,
    StockAlertReport? stockAlerts,
    CustomerAnalyticsReport? customerAnalytics,
    CustomerCreditAgeingReport? customerCreditAgeing,
    SalesTargetComparisonReport? salesTargetComparison,
    SalesForecastReport? salesForecast,
    RegisterStaffPerformanceReport? registerStaffPerformance,
    SalesAdjustmentsReport? salesAdjustments,
    PromotionPerformanceReport? promotionPerformance,
    PurchaseSupplierPerformanceReport? purchaseSupplierPerformance,
  }) async {
    setState(() => _exporting = true);
    try {
      final generatedAt = DateTime.now();
      final bytes = switch (format) {
        _ReportExportFormat.csv => buildAccountingReportCsv(
          data: data,
          businessName: businessName,
          currencyCode: currencyCode,
          periodLabel: _periodLabel,
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
          promotionPerformance: promotionPerformance,
          purchaseSupplierPerformance: purchaseSupplierPerformance,
        ),
        _ReportExportFormat.excel => buildAccountingReportExcel(
          data: data,
          businessName: businessName,
          currencyCode: currencyCode,
          periodLabel: _periodLabel,
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
          promotionPerformance: promotionPerformance,
          purchaseSupplierPerformance: purchaseSupplierPerformance,
        ),
        _ReportExportFormat.pdf => await buildAccountingReportPdf(
          data: data,
          businessName: businessName,
          currencyCode: currencyCode,
          periodLabel: _periodLabel,
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
          promotionPerformance: promotionPerformance,
          purchaseSupplierPerformance: purchaseSupplierPerformance,
        ),
      };
      final (extension, mimeType) = switch (format) {
        _ReportExportFormat.csv => ('csv', 'text/csv'),
        _ReportExportFormat.excel => (
          'xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
        _ReportExportFormat.pdf => ('pdf', 'application/pdf'),
      };
      final date = DateFormat('yyyy-MM-dd').format(generatedAt);
      final destination = await FilePicker.saveFile(
        dialogTitle: 'Save business report',
        fileName: 'flexpos-report-$date.$extension',
        bytes: bytes,
        mimeType: mimeType,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      if (mounted && destination != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${extension.toUpperCase()} report saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _editSalesTargets({
    required String businessId,
    required String currencyCode,
    required SalesTargetComparisonReport report,
  }) async {
    final draft = await showDialog<_SalesTargetDraft>(
      context: context,
      builder: (context) => _SalesTargetDialog(
        report: report,
        currencyCode: currencyCode,
        periodLabel: _periodLabel,
      ),
    );
    if (draft == null || !mounted) return;

    try {
      await ref
          .read(accountingRepositoryProvider)
          .upsertSalesTarget(
            businessId: businessId,
            branchId: draft.branchId,
            startsOn: _period.start,
            endsOn: _period.end,
            amountMinor: draft.amountMinor,
            notes: draft.notes,
          );
      ref.invalidate(salesTargetComparisonProvider(_period));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Sales target saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save sales target: $error')),
        );
      }
    }
  }

  Future<void> _configureInventoryValuation({
    required String businessId,
    required String currencyCode,
    required InventoryValuationReport report,
  }) async {
    var method = report.valuationMethod;
    final standardCostController = TextEditingController(
      text: report.standardCost?.toStringAsFixed(2) ?? '',
    );
    final selected = await showDialog<({String method, double? standardCost})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Inventory valuation method'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Method'),
                  items: const [
                    DropdownMenuItem(
                      value: 'weighted_average',
                      child: Text('Weighted average'),
                    ),
                    DropdownMenuItem(
                      value: 'fifo',
                      child: Text('FIFO batch layers'),
                    ),
                    DropdownMenuItem(
                      value: 'standard_cost',
                      child: Text('Standard cost'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    if (value != null) method = value;
                  }),
                ),
                if (method == 'standard_cost') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: standardCostController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Standard cost per unit',
                      prefixText: '$currencyCode ',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  method == 'fifo'
                      ? 'Uses current batch costs in receipt order. Legacy unbatched stock uses its recorded average cost.'
                      : method == 'standard_cost'
                      ? 'Values all on-hand units at the configured standard cost.'
                      : 'Values stock using the weighted average cost recorded on each warehouse balance.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(
                  standardCostController.text.trim(),
                );
                if (method == 'standard_cost' &&
                    (parsed == null || parsed < 0)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid standard cost.'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop((
                  method: method,
                  standardCost: method == 'standard_cost' ? parsed : null,
                ));
              },
              child: const Text('Save method'),
            ),
          ],
        ),
      ),
    );
    standardCostController.dispose();
    if (selected == null || !mounted) return;
    try {
      await ref
          .read(accountingRepositoryProvider)
          .setInventoryValuationMethod(
            businessId: businessId,
            method: selected.method,
            standardCost: selected.standardCost,
          );
      ref.invalidate(inventoryValuationProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventory valuation method saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save valuation method: $error')),
        );
      }
    }
  }

  Future<void> _refreshStockAlertNotifications(String businessId) async {
    try {
      await ref
          .read(accountingRepositoryProvider)
          .refreshStockAlertNotifications(businessId);
      ref.invalidate(stockAlertNotificationsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock notifications refreshed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not refresh stock notifications: $error'),
          ),
        );
      }
    }
  }

  Future<void> _acknowledgeStockAlertNotification(String notificationId) async {
    try {
      await ref
          .read(accountingRepositoryProvider)
          .acknowledgeStockAlertNotification(notificationId);
      ref.invalidate(stockAlertNotificationsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not acknowledge notification: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A workspace is required to view reports.',
      );
    }
    if (!workspace.canRead('reports')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Reports are restricted',
        message: 'Your role does not include report viewing permission.',
      );
    }
    final dashboard = ref.watch(accountingDashboardProvider(_period));
    final inventoryValuation = ref.watch(inventoryValuationProvider);
    final inventoryAgeing = ref.watch(inventoryAgeingProvider);
    final deadStock = ref.watch(deadStockReportProvider);
    final abcInventory = ref.watch(abcInventoryReportProvider(_period));
    final inventoryTurnover = ref.watch(inventoryTurnoverProvider(_period));
    final stockAlerts = ref.watch(stockAlertReportProvider);
    final stockAlertNotifications = ref.watch(stockAlertNotificationsProvider);
    final customerAnalytics = ref.watch(customerAnalyticsProvider(_period));
    final customerCreditAgeing = ref.watch(customerCreditAgeingProvider);
    final salesTargetComparison = ref.watch(
      salesTargetComparisonProvider(_period),
    );
    final salesForecast = ref.watch(salesForecastProvider(_period));
    final registerStaffPerformance = ref.watch(
      registerStaffPerformanceProvider(_period),
    );
    final salesAdjustments = ref.watch(salesAdjustmentsProvider(_period));
    final promotionPerformance = ref.watch(
      promotionPerformanceProvider(_period),
    );
    final purchaseSupplierPerformance = ref.watch(
      purchaseSupplierPerformanceProvider(_period),
    );
    final supportingReportsLoading =
        inventoryValuation.isLoading ||
        inventoryAgeing.isLoading ||
        deadStock.isLoading ||
        abcInventory.isLoading ||
        inventoryTurnover.isLoading ||
        stockAlerts.isLoading ||
        stockAlertNotifications.isLoading ||
        customerAnalytics.isLoading ||
        customerCreditAgeing.isLoading ||
        salesTargetComparison.isLoading ||
        salesForecast.isLoading ||
        registerStaffPerformance.isLoading ||
        salesAdjustments.isLoading ||
        promotionPerformance.isLoading ||
        purchaseSupplierPerformance.isLoading;
    return dashboard.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'reports'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load reports',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () {
            ref.invalidate(accountingDashboardProvider(_period));
            ref.invalidate(inventoryValuationProvider);
            ref.invalidate(inventoryAgeingProvider);
            ref.invalidate(deadStockReportProvider);
            ref.invalidate(abcInventoryReportProvider(_period));
            ref.invalidate(inventoryTurnoverProvider(_period));
            ref.invalidate(stockAlertReportProvider);
            ref.invalidate(stockAlertNotificationsProvider);
            ref.invalidate(customerAnalyticsProvider(_period));
            ref.invalidate(customerCreditAgeingProvider);
            ref.invalidate(salesTargetComparisonProvider(_period));
            ref.invalidate(salesForecastProvider(_period));
            ref.invalidate(registerStaffPerformanceProvider(_period));
            ref.invalidate(salesAdjustmentsProvider(_period));
            ref.invalidate(promotionPerformanceProvider(_period));
            ref.invalidate(purchaseSupplierPerformanceProvider(_period));
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.refresh(accountingDashboardProvider(_period).future),
            ref.refresh(inventoryValuationProvider.future),
            ref.refresh(inventoryAgeingProvider.future),
            ref.refresh(deadStockReportProvider.future),
            ref.refresh(abcInventoryReportProvider(_period).future),
            ref.refresh(inventoryTurnoverProvider(_period).future),
            ref.refresh(stockAlertReportProvider.future),
            ref.refresh(stockAlertNotificationsProvider.future),
            ref.refresh(customerAnalyticsProvider(_period).future),
            ref.refresh(customerCreditAgeingProvider.future),
            ref.refresh(salesTargetComparisonProvider(_period).future),
            ref.refresh(salesForecastProvider(_period).future),
            ref.refresh(registerStaffPerformanceProvider(_period).future),
            ref.refresh(salesAdjustmentsProvider(_period).future),
            ref.refresh(promotionPerformanceProvider(_period).future),
            ref.refresh(purchaseSupplierPerformanceProvider(_period).future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Business reports',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Verified database totals for accessible branches',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _exporting || supportingReportsLoading
                          ? null
                          : () => _exportReport(
                              data: data,
                              businessName: workspace.businessName,
                              currencyCode: workspace.currencyCode,
                              format: _ReportExportFormat.csv,
                              inventoryValuation:
                                  inventoryValuation.asData?.value,
                              inventoryAgeing: inventoryAgeing.asData?.value,
                              deadStock: deadStock.asData?.value,
                              abcInventory: abcInventory.asData?.value,
                              inventoryTurnover:
                                  inventoryTurnover.asData?.value,
                              stockAlerts: stockAlerts.asData?.value,
                              customerAnalytics:
                                  customerAnalytics.asData?.value,
                              customerCreditAgeing:
                                  customerCreditAgeing.asData?.value,
                              salesTargetComparison:
                                  salesTargetComparison.asData?.value,
                              salesForecast: salesForecast.asData?.value,
                              registerStaffPerformance:
                                  registerStaffPerformance.asData?.value,
                              salesAdjustments: salesAdjustments.asData?.value,
                              promotionPerformance:
                                  promotionPerformance.asData?.value,
                              purchaseSupplierPerformance:
                                  purchaseSupplierPerformance.asData?.value,
                            ),
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Export CSV'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exporting || supportingReportsLoading
                          ? null
                          : () => _exportReport(
                              data: data,
                              businessName: workspace.businessName,
                              currencyCode: workspace.currencyCode,
                              format: _ReportExportFormat.excel,
                              inventoryValuation:
                                  inventoryValuation.asData?.value,
                              inventoryAgeing: inventoryAgeing.asData?.value,
                              deadStock: deadStock.asData?.value,
                              abcInventory: abcInventory.asData?.value,
                              inventoryTurnover:
                                  inventoryTurnover.asData?.value,
                              stockAlerts: stockAlerts.asData?.value,
                              customerAnalytics:
                                  customerAnalytics.asData?.value,
                              customerCreditAgeing:
                                  customerCreditAgeing.asData?.value,
                              salesTargetComparison:
                                  salesTargetComparison.asData?.value,
                              salesForecast: salesForecast.asData?.value,
                              registerStaffPerformance:
                                  registerStaffPerformance.asData?.value,
                              salesAdjustments: salesAdjustments.asData?.value,
                              promotionPerformance:
                                  promotionPerformance.asData?.value,
                              purchaseSupplierPerformance:
                                  purchaseSupplierPerformance.asData?.value,
                            ),
                      icon: const Icon(Icons.grid_on_outlined),
                      label: const Text('Export Excel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exporting || supportingReportsLoading
                          ? null
                          : () => _exportReport(
                              data: data,
                              businessName: workspace.businessName,
                              currencyCode: workspace.currencyCode,
                              format: _ReportExportFormat.pdf,
                              inventoryValuation:
                                  inventoryValuation.asData?.value,
                              inventoryAgeing: inventoryAgeing.asData?.value,
                              deadStock: deadStock.asData?.value,
                              abcInventory: abcInventory.asData?.value,
                              inventoryTurnover:
                                  inventoryTurnover.asData?.value,
                              stockAlerts: stockAlerts.asData?.value,
                              customerAnalytics:
                                  customerAnalytics.asData?.value,
                              customerCreditAgeing:
                                  customerCreditAgeing.asData?.value,
                              salesTargetComparison:
                                  salesTargetComparison.asData?.value,
                              salesForecast: salesForecast.asData?.value,
                              registerStaffPerformance:
                                  registerStaffPerformance.asData?.value,
                              salesAdjustments: salesAdjustments.asData?.value,
                              promotionPerformance:
                                  promotionPerformance.asData?.value,
                              purchaseSupplierPerformance:
                                  purchaseSupplierPerformance.asData?.value,
                            ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Export PDF'),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('7 days')),
                        ButtonSegment(value: 30, label: Text('30 days')),
                        ButtonSegment(value: 90, label: Text('90 days')),
                      ],
                      selected: _presetDays == null ? const {} : {_presetDays!},
                      emptySelectionAllowed: true,
                      onSelectionChanged: _exporting
                          ? null
                          : (value) {
                              if (value.isNotEmpty) {
                                _selectPreset(value.single);
                              }
                            },
                    ),
                    OutlinedButton.icon(
                      onPressed: _exporting ? null : _selectCustomPeriod,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        _presetDays == null ? _periodLabel : 'Custom range',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 1000
                    ? (constraints.maxWidth - 48) / 4
                    : constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _KpiCard(
                      width: width,
                      icon: Icons.trending_up_rounded,
                      label: 'Net sales',
                      value: formatMoney(
                        workspace.currencyCode,
                        data.salesTotalMinor,
                      ),
                      detail: '${data.orderCount} completed orders',
                    ),
                    _KpiCard(
                      width: width,
                      icon: Icons.receipt_long_outlined,
                      label: 'Expenses',
                      value: formatMoney(
                        workspace.currencyCode,
                        data.expensesTotalMinor,
                      ),
                      detail: 'Net of reversals',
                    ),
                    _KpiCard(
                      width: width,
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Customer dues',
                      value: formatMoney(
                        workspace.currencyCode,
                        data.outstandingReceivablesMinor,
                      ),
                      detail: 'Outstanding receivables',
                    ),
                    _KpiCard(
                      width: width,
                      icon: data.grossProfitMinor == null
                          ? Icons.inventory_2_outlined
                          : Icons.insights_outlined,
                      label: data.grossProfitMinor == null
                          ? 'Low stock'
                          : 'Gross profit',
                      value: data.grossProfitMinor == null
                          ? data.lowStockCount.toString()
                          : formatMoney(
                              workspace.currencyCode,
                              data.grossProfitMinor!,
                            ),
                      detail: data.grossProfitMinor == null
                          ? 'Items at reorder point'
                          : 'Before operating expenses',
                    ),
                    if (data.netProfitMinor != null)
                      _KpiCard(
                        width: width,
                        icon: data.netProfitMinor! >= 0
                            ? Icons.savings_outlined
                            : Icons.trending_down_rounded,
                        label: 'Net profit',
                        value: formatMoney(
                          workspace.currencyCode,
                          data.netProfitMinor!,
                        ),
                        detail: data.netProfitMargin == null
                            ? 'After operating expenses'
                            : '${data.netProfitMargin!.toStringAsFixed(2)}% of net sales',
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                final sales = _SalesPanel(
                  data: data,
                  currencyCode: workspace.currencyCode,
                );
                final payments = _PaymentsPanel(
                  items: data.paymentBreakdown,
                  currencyCode: workspace.currencyCode,
                  taxTotalMinor: data.taxTotalMinor,
                  lowStockCount: data.lowStockCount,
                );
                if (!wide) {
                  return Column(
                    children: [sales, const SizedBox(height: 16), payments],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: sales),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: payments),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 1050
                    ? (constraints.maxWidth - 32) / 3
                    : constraints.maxWidth >= 680
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _SalesBreakdownPanel(
                      width: width,
                      title: 'Sales by branch',
                      icon: Icons.store_outlined,
                      items: data.branchBreakdown,
                      currencyCode: workspace.currencyCode,
                    ),
                    _SalesBreakdownPanel(
                      width: width,
                      title: 'Sales by employee',
                      icon: Icons.badge_outlined,
                      items: data.employeeBreakdown,
                      currencyCode: workspace.currencyCode,
                    ),
                    _SalesBreakdownPanel(
                      width: width,
                      title: 'Sales by product',
                      icon: Icons.inventory_2_outlined,
                      items: data.productBreakdown,
                      currencyCode: workspace.currencyCode,
                      quantityDetail: true,
                    ),
                    _SalesBreakdownPanel(
                      width: width,
                      title: 'Sales by category',
                      icon: Icons.category_outlined,
                      items: data.categoryBreakdown,
                      currencyCode: workspace.currencyCode,
                      quantityDetail: true,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            salesTargetComparison.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load sales comparison: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry sales comparison',
                      onPressed: () => ref.invalidate(
                        salesTargetComparisonProvider(_period),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _SalesTargetComparisonSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                      canManage: workspace.canUpdate('sales_targets'),
                      onManage: () => _editSalesTargets(
                        businessId: workspace.businessId,
                        currencyCode: workspace.currencyCode,
                        report: report,
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            salesForecast.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Could not load forecast: $error')),
                    IconButton(
                      tooltip: 'Retry forecast',
                      onPressed: () =>
                          ref.invalidate(salesForecastProvider(_period)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _SalesForecastSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            registerStaffPerformance.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Could not load register and staff performance: $error',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry register and staff performance',
                      onPressed: () => ref.invalidate(
                        registerStaffPerformanceProvider(_period),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _RegisterStaffPerformanceSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            salesAdjustments.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load sales adjustments: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry sales adjustments',
                      onPressed: () =>
                          ref.invalidate(salesAdjustmentsProvider(_period)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _SalesAdjustmentsSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            promotionPerformance.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Could not load promotion performance: $error',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry promotion performance',
                      onPressed: () =>
                          ref.invalidate(promotionPerformanceProvider(_period)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _PromotionPerformanceSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            purchaseSupplierPerformance.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Could not load purchase and supplier performance: $error',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry purchase and supplier performance',
                      onPressed: () => ref.invalidate(
                        purchaseSupplierPerformanceProvider(_period),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _PurchaseSupplierPerformanceSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            inventoryValuation.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load inventory valuation: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry inventory valuation',
                      onPressed: () =>
                          ref.invalidate(inventoryValuationProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _InventoryValuationSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                      canManage: workspace.canUpdate('inventory'),
                      onConfigure: () => _configureInventoryValuation(
                        businessId: workspace.businessId,
                        currencyCode: workspace.currencyCode,
                        report: report,
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            inventoryAgeing.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load inventory ageing: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry inventory ageing',
                      onPressed: () => ref.invalidate(inventoryAgeingProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _InventoryAgeingSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            deadStock.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load dead-stock analysis: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry dead-stock analysis',
                      onPressed: () => ref.invalidate(deadStockReportProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _DeadStockSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            abcInventory.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load ABC analysis: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry ABC analysis',
                      onPressed: () =>
                          ref.invalidate(abcInventoryReportProvider(_period)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _AbcInventorySection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            inventoryTurnover.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load inventory turnover: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry inventory turnover',
                      onPressed: () =>
                          ref.invalidate(inventoryTurnoverProvider(_period)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _InventoryTurnoverSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            stockAlerts.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load stock alerts: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry stock alerts',
                      onPressed: () => ref.invalidate(stockAlertReportProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _StockAlertSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                      notifications:
                          stockAlertNotifications.asData?.value ?? const [],
                      canManage: workspace.canUpdate('inventory'),
                      onRefreshNotifications: () =>
                          _refreshStockAlertNotifications(workspace.businessId),
                      onAcknowledgeNotification:
                          _acknowledgeStockAlertNotification,
                    ),
            ),
            const SizedBox(height: 18),
            customerAnalytics.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load customer analytics: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry customer analytics',
                      onPressed: () =>
                          ref.invalidate(customerAnalyticsProvider(_period)),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _CustomerAnalyticsSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
            const SizedBox(height: 18),
            customerCreditAgeing.when(
              loading: () => const AppPanel(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => AppPanel(
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Could not load credit ageing: $error'),
                    ),
                    IconButton(
                      tooltip: 'Retry credit ageing',
                      onPressed: () =>
                          ref.invalidate(customerCreditAgeingProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              data: (report) => report == null
                  ? const SizedBox.shrink()
                  : _CustomerCreditAgeingSection(
                      report: report,
                      currencyCode: workspace.currencyCode,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegisterStaffPerformanceSection extends StatelessWidget {
  const _RegisterStaffPerformanceSection({
    required this.report,
    required this.currencyCode,
  });

  final RegisterStaffPerformanceReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Register reconciliation and staff performance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Closed-shift cash differences and net sales for the selected period.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.badge_outlined,
                  label: 'Staff net sales',
                  value: formatMoney(currencyCode, report.netSalesMinor),
                  detail: '${report.orders} completed orders',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.point_of_sale_outlined,
                  label: 'Closed shifts',
                  value: report.shiftsClosed.toString(),
                  detail:
                      '${report.balancedShifts} balanced · ${report.overShifts} over · ${report.shortShifts} short',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Net cash variance',
                  value: formatMoney(currencyCode, report.netVarianceMinor),
                  detail:
                      '${formatMoney(currencyCode, report.overageMinor)} over · '
                      '${formatMoney(currencyCode, report.shortageMinor)} short',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.rule_folder_outlined,
                  label: 'Absolute variance',
                  value: formatMoney(
                    currencyCode,
                    report.absoluteVarianceMinor,
                  ),
                  detail:
                      '${formatMoney(currencyCode, report.expectedCashMinor)} expected · '
                      '${formatMoney(currencyCode, report.closingCashMinor)} counted',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staff performance',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Returns reduce the original seller’s net sales; processed returns are counted for the handling staff member.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (report.staff.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No active staff found.'),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Staff')),
                      DataColumn(label: Text('Orders'), numeric: true),
                      DataColumn(label: Text('Net sales'), numeric: true),
                      DataColumn(label: Text('Average order'), numeric: true),
                      DataColumn(label: Text('Returns'), numeric: true),
                      DataColumn(label: Text('Shifts'), numeric: true),
                      DataColumn(label: Text('Cash variance'), numeric: true),
                    ],
                    rows: [
                      for (final staff in report.staff)
                        DataRow(
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(staff.name),
                                  if (staff.email != staff.name)
                                    Text(
                                      staff.email,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            DataCell(Text(staff.orders.toString())),
                            DataCell(
                              Text(
                                formatMoney(currencyCode, staff.netSalesMinor),
                              ),
                            ),
                            DataCell(
                              Text(
                                staff.averageOrderValueMinor == null
                                    ? '—'
                                    : formatMoney(
                                        currencyCode,
                                        staff.averageOrderValueMinor!,
                                      ),
                              ),
                            ),
                            DataCell(Text(staff.returnsProcessed.toString())),
                            DataCell(
                              Text(
                                '${staff.shiftsClosed} (${staff.balancedShifts} balanced)',
                              ),
                            ),
                            DataCell(
                              Text(
                                formatMoney(
                                  currencyCode,
                                  staff.netVarianceMinor,
                                ),
                                style: TextStyle(
                                  color: _varianceColor(
                                    context,
                                    staff.netVarianceMinor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Register differences',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Only closed shifts are reconciled; open shifts are excluded.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (report.registers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No accessible registers found.'),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Register')),
                      DataColumn(label: Text('Shifts'), numeric: true),
                      DataColumn(label: Text('Balanced'), numeric: true),
                      DataColumn(label: Text('Over'), numeric: true),
                      DataColumn(label: Text('Short'), numeric: true),
                      DataColumn(label: Text('Expected'), numeric: true),
                      DataColumn(label: Text('Counted'), numeric: true),
                      DataColumn(label: Text('Variance'), numeric: true),
                    ],
                    rows: [
                      for (final register in report.registers)
                        DataRow(
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(register.name),
                                  Text(
                                    '${register.branchName} · ${register.code}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            DataCell(Text(register.shiftsClosed.toString())),
                            DataCell(Text(register.balancedShifts.toString())),
                            DataCell(Text(register.overShifts.toString())),
                            DataCell(Text(register.shortShifts.toString())),
                            DataCell(
                              Text(
                                formatMoney(
                                  currencyCode,
                                  register.expectedCashMinor,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                formatMoney(
                                  currencyCode,
                                  register.closingCashMinor,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                formatMoney(
                                  currencyCode,
                                  register.netVarianceMinor,
                                ),
                                style: TextStyle(
                                  color: _varianceColor(
                                    context,
                                    register.netVarianceMinor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesAdjustmentsSection extends StatelessWidget {
  const _SalesAdjustmentsSection({
    required this.report,
    required this.currencyCode,
  });

  final SalesAdjustmentsReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discounts, returns, and refunds',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Completed activity for accessible branches with return-adjusted discount and refund detail.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.percent_rounded,
                  label: 'Discounts',
                  value: formatMoney(currencyCode, report.discountTotalMinor),
                  detail:
                      '${report.discountedSaleCount} of ${report.saleCount} sales · ${_percentageLabel(report.discountRate)}',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.assignment_return_outlined,
                  label: 'Completed returns',
                  value: report.returnCount.toString(),
                  detail: '${_quantityLabel(report.returnedQuantity)} units',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.currency_exchange_outlined,
                  label: 'Refund value',
                  value: formatMoney(currencyCode, report.refundTotalMinor),
                  detail:
                      '${formatMoney(currencyCode, report.settledRefundTotalMinor)} settled',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.description_outlined,
                  label: 'Credit notes',
                  value: formatMoney(currencyCode, report.creditNoteTotalMinor),
                  detail:
                      '${formatMoney(currencyCode, report.pendingRefundTotalMinor)} pending refunds',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final products = _SalesAdjustmentListPanel(
              title: 'Top returned products',
              icon: Icons.inventory_2_outlined,
              emptyText: 'No completed returns in this period.',
              children: [
                for (final item in report.returnedProducts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.productName),
                    subtitle: Text(
                      '${item.sku} · ${item.variantName} · ${_quantityLabel(item.quantity)} returned',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, item.refundTotalMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            );
            final allocations = _SalesAdjustmentListPanel(
              title: 'Refund allocation',
              icon: Icons.account_balance_wallet_outlined,
              emptyText: 'No refund allocations in this period.',
              children: [
                for (final item in report.refundAllocations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(_salesAdjustmentLabel(item.method)),
                    subtitle: Text(
                      '${_salesAdjustmentLabel(item.status)} · ${item.returnCount} return${item.returnCount == 1 ? '' : 's'}',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, item.amountMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            );
            if (!wide) {
              return Column(
                children: [products, const SizedBox(height: 16), allocations],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: products),
                const SizedBox(width: 16),
                Expanded(child: allocations),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PromotionPerformanceSection extends StatelessWidget {
  const _PromotionPerformanceSection({
    required this.report,
    required this.currencyCode,
  });

  final PromotionPerformanceReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Promotion performance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Campaign redemptions and attributed sales for completed orders in the selected period.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.local_offer_outlined,
                  label: 'Redemptions',
                  value: report.redemptionCount.toString(),
                  detail: '${report.campaignsUsed} campaigns used',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.trending_up_rounded,
                  label: 'Attributed sales',
                  value: formatMoney(currencyCode, report.attributedSalesMinor),
                  detail: report.averageOrderValueMinor == null
                      ? 'No attributed orders'
                      : 'Average ${formatMoney(currencyCode, report.averageOrderValueMinor!)}',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.percent_rounded,
                  label: 'Discounts granted',
                  value: formatMoney(currencyCode, report.discountTotalMinor),
                  detail:
                      '${_percentageLabel(report.discountRate)} of attributed subtotal',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.people_outline_rounded,
                  label: 'Unique customers',
                  value: report.uniqueCustomerCount.toString(),
                  detail: '${report.activePromotionCount} active campaigns',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final campaigns = _SalesAdjustmentListPanel(
              title: 'Campaign results',
              icon: Icons.campaign_outlined,
              emptyText: 'No promotions have been created yet.',
              children: [
                for (final campaign in report.campaigns)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(campaign.name),
                    subtitle: Text(
                      '${campaign.code} · ${campaign.branchName} · '
                      '${campaign.redemptionCount} redemption${campaign.redemptionCount == 1 ? '' : 's'} · '
                      '${campaign.uniqueCustomerCount} customer${campaign.uniqueCustomerCount == 1 ? '' : 's'}',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, campaign.attributedSalesMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            );
            final daily = _SalesAdjustmentListPanel(
              title: 'Daily campaign activity',
              icon: Icons.timeline_outlined,
              emptyText: 'No coupon redemptions in this period.',
              children: [
                for (final point in report.daily.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(DateFormat.yMMMd().format(point.day)),
                    subtitle: Text(
                      '${point.redemptionCount} redemption${point.redemptionCount == 1 ? '' : 's'} · '
                      '${formatMoney(currencyCode, point.discountTotalMinor)} discounts',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, point.attributedSalesMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            );
            if (constraints.maxWidth < 900) {
              return Column(
                children: [campaigns, const SizedBox(height: 16), daily],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: campaigns),
                const SizedBox(width: 16),
                Expanded(child: daily),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SalesAdjustmentListPanel extends StatelessWidget {
  const _SalesAdjustmentListPanel({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(emptyText),
          )
        else
          ...children,
      ],
    ),
  );
}

class _PurchaseSupplierPerformanceSection extends StatelessWidget {
  const _PurchaseSupplierPerformanceSection({
    required this.report,
    required this.currencyCode,
  });

  final PurchaseSupplierPerformanceReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final deliveryRate = report.onTimeRate == null
        ? 'Not measured'
        : _percentageLabel(report.onTimeRate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Purchase and supplier performance',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Ordered spend, receipt progress, and delivery reliability for accessible branches. Delivery rates use received orders with an expected date.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.shopping_cart_checkout_outlined,
                  label: 'Ordered value',
                  value: formatMoney(currencyCode, report.orderedTotalMinor),
                  detail: '${report.orderCount} purchase orders',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.inventory_outlined,
                  label: 'Received cost',
                  value: formatMoney(currencyCode, report.receivedCostMinor),
                  detail: '${report.receiptCount} goods receipts',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.local_shipping_outlined,
                  label: 'Quantity fulfillment',
                  value:
                      '${_quantityLabel(report.receivedQuantity)} / ${_quantityLabel(report.orderedQuantity)}',
                  detail:
                      '${_quantityLabel(report.outstandingQuantity)} outstanding',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.schedule_outlined,
                  label: 'On-time delivery',
                  value: deliveryRate,
                  detail:
                      '${report.overdueOrderCount} overdue · ${report.measuredDeliveryCount} measured',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final suppliers = _SalesAdjustmentListPanel(
              title: 'Supplier performance',
              icon: Icons.factory_outlined,
              emptyText: 'No purchase orders in this period.',
              children: [
                for (final item in report.suppliers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.supplierName),
                    subtitle: Text(
                      '${item.orderCount} orders · ${item.openOrderCount} open · ${item.overdueOrderCount} overdue · ${_percentageLabel(item.onTimeRate)} on time',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, item.orderedTotalMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            );
            final products = _SalesAdjustmentListPanel(
              title: 'Top purchased products',
              icon: Icons.category_outlined,
              emptyText: 'No purchase-order items in this period.',
              children: [
                for (final item in report.products)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.productName),
                    subtitle: Text(
                      '${item.sku} · ${_quantityLabel(item.receivedQuantity)} of ${_quantityLabel(item.orderedQuantity)} received · ${item.supplierCount} supplier${item.supplierCount == 1 ? '' : 's'}',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, item.orderedItemCostMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
              ],
            );
            if (!wide) {
              return Column(
                children: [suppliers, const SizedBox(height: 16), products],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: suppliers),
                const SizedBox(width: 16),
                Expanded(child: products),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _salesAdjustmentLabel(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

Color _varianceColor(BuildContext context, int value) {
  if (value == 0) return Theme.of(context).colorScheme.onSurfaceVariant;
  return value > 0
      ? Colors.orange.shade800
      : Theme.of(context).colorScheme.error;
}

class _SalesForecastSection extends StatelessWidget {
  const _SalesForecastSection({
    required this.report,
    required this.currencyCode,
  });

  final SalesForecastReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final weeks = _forecastWeeks(report.forecast);
    final maximum = weeks.fold<int>(
      0,
      (current, week) => math.max(current, week.estimateMinor),
    );
    final date = DateFormat.yMMMd();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sales forecast',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          '${date.format(report.forecastStart)} - '
          '${date.format(report.forecastEnd)} · based on '
          '${report.historyDays} days of net sales history',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.auto_graph_rounded,
                  label: 'Projected sales',
                  value: formatMoney(currencyCode, report.projectedSalesMinor),
                  detail: '${report.forecastDays}-day estimate',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.swap_vert_circle_outlined,
                  label: 'Indicative range',
                  value: formatMoney(currencyCode, report.projectedLowMinor),
                  detail:
                      'Up to ${formatMoney(currencyCode, report.projectedHighMinor)}',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.calendar_view_day_outlined,
                  label: 'Projected daily average',
                  value: formatMoney(
                    currencyCode,
                    report.projectedDailyAverageMinor,
                  ),
                  detail: _forecastChangeLabel(report.projectedChangeRate),
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.analytics_outlined,
                  label: 'Model signal',
                  value: _forecastTrendLabel(report.trendDirection),
                  detail:
                      '${_forecastQualityLabel(report.dataQuality)} data · '
                      '${report.activeHistoryDays} active days',
                ),
              ],
            );
          },
        ),
        if (report.dataQuality != 'sufficient') ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Forecast confidence is limited because only '
                    '${report.activeHistoryDays} of ${report.historyDays} '
                    'history days contain net sales. Trend extrapolation is '
                    'disabled until at least seven active days are available.',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly projection',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Weekday seasonality, linear trend, and completed returns are included.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              if (weeks.isEmpty)
                const Text('No forecast data available yet.')
              else
                LayoutBuilder(
                  builder: (context, _) {
                    const chartHeight = 220.0;
                    final barColor = Theme.of(context).colorScheme.primary;
                    return SizedBox(
                      height: chartHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final week in weeks)
                            Expanded(
                              child: Semantics(
                                label:
                                    '${date.format(week.start)} to ${date.format(week.end)}, '
                                    '${formatMoney(currencyCode, week.estimateMinor)} forecast',
                                child: Tooltip(
                                  message:
                                      '${date.format(week.start)} – ${date.format(week.end)}\n'
                                      '${formatMoney(currencyCode, week.estimateMinor)} estimate\n'
                                      '${formatMoney(currencyCode, week.lowerMinor)} – ${formatMoney(currencyCode, week.upperMinor)} range',
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          formatMoney(
                                            currencyCode,
                                            week.estimateMinor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.bottomCenter,
                                            child: FractionallySizedBox(
                                              heightFactor: maximum <= 0
                                                  ? 0.0
                                                  : (week.estimateMinor /
                                                            maximum)
                                                        .clamp(0.08, 1.0)
                                                        .toDouble(),
                                              child: Container(
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: barColor,
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                    top: Radius.circular(8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          DateFormat.MMMd().format(week.start),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Text(
                'Forecasts are estimates, not guaranteed revenue. The range '
                'is derived from historical model residuals.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ForecastWeek {
  const _ForecastWeek({
    required this.start,
    required this.end,
    required this.estimateMinor,
    required this.lowerMinor,
    required this.upperMinor,
  });

  final DateTime start;
  final DateTime end;
  final int estimateMinor;
  final int lowerMinor;
  final int upperMinor;
}

List<_ForecastWeek> _forecastWeeks(List<SalesForecastPoint> points) {
  final result = <_ForecastWeek>[];
  for (var index = 0; index < points.length; index += 7) {
    final endIndex = math.min(index + 7, points.length);
    final slice = points.sublist(index, endIndex);
    result.add(
      _ForecastWeek(
        start: slice.first.date,
        end: slice.last.date,
        estimateMinor: slice.fold(0, (sum, point) => sum + point.estimateMinor),
        lowerMinor: slice.fold(
          0,
          (sum, point) => sum + point.lowerEstimateMinor,
        ),
        upperMinor: slice.fold(
          0,
          (sum, point) => sum + point.upperEstimateMinor,
        ),
      ),
    );
  }
  return result;
}

String _forecastChangeLabel(double? value) {
  if (value == null) return 'No historical baseline';
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}% vs historical daily average';
}

String _forecastQualityLabel(String value) => switch (value) {
  'sufficient' => 'Sufficient',
  'sparse' => 'Sparse',
  'limited' => 'Limited',
  _ => value,
};

String _forecastTrendLabel(String value) => switch (value) {
  'rising' => 'Rising',
  'falling' => 'Falling',
  'stable' => 'Stable',
  'insufficient_data' => 'Awaiting history',
  _ => value,
};

class _SalesTargetComparisonSection extends StatelessWidget {
  const _SalesTargetComparisonSection({
    required this.report,
    required this.currencyCode,
    required this.canManage,
    required this.onManage,
  });

  final SalesTargetComparisonReport report;
  final String currencyCode;
  final bool canManage;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd();
    final comparisonLabel =
        '${date.format(report.comparisonStart)} - '
        '${date.format(report.comparisonEnd)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sales targets and comparison',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compared with the previous ${report.periodDays}-day period '
                    '($comparisonLabel)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (canManage && report.branches.isNotEmpty)
              OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Set targets'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.compare_arrows_rounded,
                  label: 'Sales vs previous',
                  value: formatMoney(currencyCode, report.currentSalesMinor),
                  detail:
                      '${_changeLabel(report.salesChangeRate)} · previous '
                      '${formatMoney(currencyCode, report.previousSalesMinor)}',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.flag_outlined,
                  label: 'Target achievement',
                  value: report.targetAchievementRate == null
                      ? 'Not configured'
                      : '${report.targetAchievementRate!.toStringAsFixed(1)}%',
                  detail: report.targetAmountMinor == null
                      ? '${report.targetedBranchCount} of '
                            '${report.accessibleBranchCount} branches targeted'
                      : 'Target '
                            '${formatMoney(currencyCode, report.targetAmountMinor!)}',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.shopping_bag_outlined,
                  label: 'Orders vs previous',
                  value: report.currentOrders.toString(),
                  detail:
                      '${_changeLabel(report.orderChangeRate)} · previous '
                      '${report.previousOrders}',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.receipt_long_outlined,
                  label: 'Average order',
                  value: report.currentAverageOrderValueMinor == null
                      ? 'Not available'
                      : formatMoney(
                          currencyCode,
                          report.currentAverageOrderValueMinor!,
                        ),
                  detail: report.previousAverageOrderValueMinor == null
                      ? 'No orders in the previous period'
                      : 'Previous '
                            '${formatMoney(currencyCode, report.previousAverageOrderValueMinor!)}',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Branch target progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (report.branches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No accessible branches'),
                )
              else
                for (final branch in report.branches) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(branch.name),
                    subtitle: Text(
                      branch.targetAmountMinor == null
                          ? '${branch.currentOrders} orders · target not set'
                          : '${branch.currentOrders} orders · '
                                '${branch.targetAchievementRate?.toStringAsFixed(1) ?? '0.0'}% of '
                                '${formatMoney(currencyCode, branch.targetAmountMinor!)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(currencyCode, branch.currentSalesMinor),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          _changeLabel(branch.salesChangeRate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _changeColor(
                                  context,
                                  branch.salesChangeRate,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (branch.targetAchievementRate != null)
                    LinearProgressIndicator(
                      value: (branch.targetAchievementRate! / 100)
                          .clamp(0, 1)
                          .toDouble(),
                    ),
                  if (branch != report.branches.last) const Divider(height: 24),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesTargetDraft {
  const _SalesTargetDraft({
    required this.branchId,
    required this.amountMinor,
    this.notes,
  });

  final String branchId;
  final int amountMinor;
  final String? notes;
}

class _SalesTargetDialog extends StatefulWidget {
  const _SalesTargetDialog({
    required this.report,
    required this.currencyCode,
    required this.periodLabel,
  });

  final SalesTargetComparisonReport report;
  final String currencyCode;
  final String periodLabel;

  @override
  State<_SalesTargetDialog> createState() => _SalesTargetDialogState();
}

class _SalesTargetDialogState extends State<_SalesTargetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  late String _branchId;

  @override
  void initState() {
    super.initState();
    _branchId = widget.report.branches.first.id;
    _loadBranch();
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  SalesTargetBranchComparison get _branch =>
      widget.report.branches.firstWhere((branch) => branch.id == _branchId);

  void _loadBranch() {
    final target = _branch.targetAmountMinor;
    _amount.text = target == null ? '' : (target / 100).toStringAsFixed(2);
    _notes.text = _branch.targetNotes ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set branch sales target'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exact period: ${widget.periodLabel}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  for (final branch in widget.report.branches)
                    DropdownMenuItem(
                      value: branch.id,
                      child: Text(branch.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _branchId = value;
                    _loadBranch();
                  });
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Target amount (${widget.currencyCode})',
                  prefixIcon: const Icon(Icons.flag_outlined),
                ),
                validator: (value) {
                  final amount = parseMoneyToMinor(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter a target greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notes,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _SalesTargetDraft(
                branchId: _branchId,
                amountMinor: parseMoneyToMinor(_amount.text)!,
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              ),
            );
          },
          child: const Text('Save target'),
        ),
      ],
    );
  }
}

String _changeLabel(double? value) {
  if (value == null) return 'No prior baseline';
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(1)}%';
}

Color _changeColor(BuildContext context, double? value) {
  if (value == null || value == 0) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  return value > 0
      ? Colors.green.shade700
      : Theme.of(context).colorScheme.error;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 3),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SalesPanel extends StatefulWidget {
  const _SalesPanel({required this.data, required this.currencyCode});

  final AccountingDashboard data;
  final String currencyCode;

  @override
  State<_SalesPanel> createState() => _SalesPanelState();
}

class _SalesPanelState extends State<_SalesPanel> {
  SalesInterval _interval = SalesInterval.daily;
  DateTime? _selectedPeriod;

  @override
  Widget build(BuildContext context) {
    final points = aggregateSales(widget.data.dailySales, _interval);
    final maximum = points.fold<int>(
      0,
      (current, item) => math.max(current, item.totalMinor),
    );
    SalesAggregate? selectedPoint;
    for (final point in points) {
      if (point.periodStart == _selectedPeriod) {
        selectedPoint = point;
        break;
      }
    }
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            spacing: 12,
            children: [
              Text(
                '${_interval.label} sales',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final interval in SalesInterval.values)
                    ChoiceChip(
                      label: Text(interval.label),
                      selected: _interval == interval,
                      onSelected: (_) => setState(() {
                        _interval = interval;
                        _selectedPeriod = null;
                      }),
                    ),
                ],
              ),
            ],
          ),
          if (selectedPoint != null) ...[
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 4,
                spacing: 12,
                children: [
                  Text(
                    formatSalesPeriod(selectedPoint.periodStart, _interval),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    '${formatMoney(widget.currencyCode, selectedPoint.totalMinor)}'
                    ' · ${selectedPoint.orders} order${selectedPoint.orders == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (points.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Center(child: Text('No completed sales in this period')),
            )
          else
            for (final point in points) ...[
              Semantics(
                button: true,
                selected: point.periodStart == _selectedPeriod,
                label:
                    '${formatSalesPeriod(point.periodStart, _interval)}, '
                    '${formatMoney(widget.currencyCode, point.totalMinor)}, '
                    '${point.orders} orders',
                child: Material(
                  color: point.periodStart == _selectedPeriod
                      ? Theme.of(context).colorScheme.primaryContainer
                            .withValues(alpha: 0.32)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      _selectedPeriod = point.periodStart == _selectedPeriod
                          ? null
                          : point.periodStart;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: _interval == SalesInterval.weekly ? 110 : 82,
                            child: Text(
                              formatSalesPeriod(point.periodStart, _interval),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                minHeight: 10,
                                value: maximum <= 0
                                    ? 0
                                    : (point.totalMinor / maximum).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 105,
                            child: Text(
                              formatMoney(
                                widget.currencyCode,
                                point.totalMinor,
                              ),
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
        ],
      ),
    );
  }
}

class _PaymentsPanel extends StatelessWidget {
  const _PaymentsPanel({
    required this.items,
    required this.currencyCode,
    required this.taxTotalMinor,
    required this.lowStockCount,
  });

  final List<PaymentTotal> items;
  final String currencyCode;
  final int taxTotalMinor;
  final int lowStockCount;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sales by payment channel',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const Text('No settled payments in this period')
          else
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_paymentLabel(item.method)),
                trailing: Text(
                  formatMoney(currencyCode, item.totalMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
          const Divider(height: 28),
          _FactRow(
            label: 'Tax collected',
            value: formatMoney(currencyCode, taxTotalMinor),
          ),
          const SizedBox(height: 10),
          _FactRow(label: 'Low-stock items', value: '$lowStockCount'),
        ],
      ),
    );
  }

  String _paymentLabel(String value) => switch (value) {
    'bank_transfer' => 'Bank transfer',
    'customer_credit' => 'Customer credit',
    _ => value[0].toUpperCase() + value.substring(1),
  };
}

class _SalesBreakdownPanel extends StatelessWidget {
  const _SalesBreakdownPanel({
    required this.width,
    required this.title,
    required this.icon,
    required this.items,
    required this.currencyCode,
    this.quantityDetail = false,
  });

  final double width;
  final String title;
  final IconData icon;
  final List<SalesBreakdownItem> items;
  final String currencyCode;
  final bool quantityDetail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No sales in this period'),
              )
            else
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    quantityDetail
                        ? '${_formatQuantity(item.quantity)} net units'
                        : '${item.orderCount} order${item.orderCount == 1 ? '' : 's'}',
                  ),
                  trailing: Text(
                    formatMoney(currencyCode, item.totalMinor),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

String _valuationDescription(InventoryValuationReport report) {
  switch (report.valuationMethod) {
    case 'fifo':
      return 'Current stock valued using FIFO batch layers where available';
    case 'standard_cost':
      return 'Current stock valued at the configured standard cost';
    default:
      return 'Current stock valued at warehouse weighted-average cost';
  }
}

class _InventoryValuationSection extends StatelessWidget {
  const _InventoryValuationSection({
    required this.report,
    required this.currencyCode,
    required this.canManage,
    required this.onConfigure,
  });

  final InventoryValuationReport report;
  final String currencyCode;
  final bool canManage;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Inventory valuation',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canManage)
              OutlinedButton.icon(
                onPressed: onConfigure,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Valuation method'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _valuationDescription(report),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.inventory_2_outlined,
                  label: 'Inventory value',
                  value: formatMoney(currencyCode, report.totalValueMinor),
                  detail: '${report.skuCount} distinct SKUs',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.warehouse_outlined,
                  label: 'On hand',
                  value: _quantityLabel(report.onHandQuantity),
                  detail: 'Units across accessible warehouses',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.bookmark_added_outlined,
                  label: 'Reserved',
                  value: _quantityLabel(report.reservedQuantity),
                  detail:
                      '${_quantityLabel(report.availableQuantity)} available',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.notification_important_outlined,
                  label: 'Low stock',
                  value: report.lowStockCount.toString(),
                  detail: 'Warehouse balances at reorder point',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final warehouse = _InventoryGroupPanel(
              title: 'By warehouse',
              icon: Icons.warehouse_outlined,
              groups: report.byWarehouse,
              currencyCode: currencyCode,
            );
            final category = _InventoryGroupPanel(
              title: 'By category',
              icon: Icons.category_outlined,
              groups: report.byCategory,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [warehouse, const SizedBox(height: 16), category],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: warehouse),
                const SizedBox(width: 16),
                Expanded(child: category),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InventoryGroupPanel extends StatelessWidget {
  const _InventoryGroupPanel({
    required this.title,
    required this.icon,
    required this.groups,
    required this.currencyCode,
  });

  final String title;
  final IconData icon;
  final List<InventoryValuationGroup> groups;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No inventory balances available'),
            )
          else
            for (final group in groups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_quantityLabel(group.onHandQuantity)} on hand · '
                  '${group.skuCount} SKU${group.skuCount == 1 ? '' : 's'}',
                ),
                trailing: Text(
                  formatMoney(currencyCode, group.totalValueMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
        ],
      ),
    );
  }
}

class _InventoryAgeingSection extends StatelessWidget {
  const _InventoryAgeingSection({
    required this.report,
    required this.currencyCode,
  });

  final InventoryAgeingReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd().format(report.asOfDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inventory ageing',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'FIFO ageing as of $date · '
          '${_quantityLabel(report.trackedQuantity)} tracked · '
          '${_quantityLabel(report.untrackedQuantity)} untracked',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1100
                ? (constraints.maxWidth - 64) / 5
                : constraints.maxWidth >= 680
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final bucket in report.buckets)
                  _AgeBucketCard(
                    width: width,
                    bucket: bucket,
                    currencyCode: currencyCode,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final warehouse = _AgeingGroupPanel(
              title: 'Ageing by warehouse',
              icon: Icons.warehouse_outlined,
              groups: report.byWarehouse,
              currencyCode: currencyCode,
            );
            final category = _AgeingGroupPanel(
              title: 'Ageing by category',
              icon: Icons.category_outlined,
              groups: report.byCategory,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [warehouse, const SizedBox(height: 16), category],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: warehouse),
                const SizedBox(width: 16),
                Expanded(child: category),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AgeBucketCard extends StatelessWidget {
  const _AgeBucketCard({
    required this.width,
    required this.bucket,
    required this.currencyCode,
  });

  final double width;
  final InventoryAgeBucket bucket;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bucket.label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Text(
              _quantityLabel(bucket.quantity),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${bucket.skuCount} SKU${bucket.skuCount == 1 ? '' : 's'} · '
              '${formatMoney(currencyCode, bucket.totalValueMinor)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgeingGroupPanel extends StatelessWidget {
  const _AgeingGroupPanel({
    required this.title,
    required this.icon,
    required this.groups,
    required this.currencyCode,
  });

  final String title;
  final IconData icon;
  final List<InventoryAgeingGroup> groups;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No inventory layers available'),
            )
          else
            for (final group in groups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_quantityLabel(group.quantity)} units · '
                  '${group.oldestAgeDays == null ? 'no tracked age' : 'oldest ${group.oldestAgeDays}d'} · '
                  '${_quantityLabel(group.olderThan90Quantity)} over 90d',
                ),
                trailing: Text(
                  formatMoney(currencyCode, group.totalValueMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
        ],
      ),
    );
  }
}

class _DeadStockSection extends StatelessWidget {
  const _DeadStockSection({required this.report, required this.currencyCode});

  final DeadStockReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMMMd().format(report.asOfDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dead stock analysis',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Positive inventory with no sale for ${report.inactivityDays}+ days as of $date. Never-sold stock is shown separately.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.inventory_2_outlined,
                  label: 'Dead-stock value',
                  value: formatMoney(currencyCode, report.deadValueMinor),
                  detail:
                      '${_percentageLabel(report.deadValueRate)} of inventory value',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.production_quantity_limits_outlined,
                  label: 'Dead-stock SKUs',
                  value: report.deadSkuCount.toString(),
                  detail: '${report.stockedSkuCount} stocked SKUs',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.new_releases_outlined,
                  label: 'Never sold',
                  value: report.neverSoldSkuCount.toString(),
                  detail: 'SKUs with no recorded sale',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.hourglass_bottom_outlined,
                  label: 'Inactive quantity',
                  value: _quantityLabel(report.deadQuantity),
                  detail:
                      '${_quantityLabel(report.deadReservedQuantity)} reserved',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Highest-value dead stock',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (report.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No dead stock at the 90-day threshold.'),
                )
              else
                for (final item in report.items.take(15))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${item.productName} · ${item.variantName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.sku} · ${item.warehouseName} · ${_quantityLabel(item.quantityOnHand)} on hand · ${item.neverSold ? 'never sold' : '${item.daysSinceLastSale} days inactive'}',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, item.stockValueMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final warehouses = _DeadStockGroupPanel(
              title: 'Dead stock by warehouse',
              icon: Icons.warehouse_outlined,
              groups: report.byWarehouse,
              currencyCode: currencyCode,
            );
            final categories = _DeadStockGroupPanel(
              title: 'Dead stock by category',
              icon: Icons.category_outlined,
              groups: report.byCategory,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [warehouses, const SizedBox(height: 16), categories],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: warehouses),
                const SizedBox(width: 16),
                Expanded(child: categories),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DeadStockGroupPanel extends StatelessWidget {
  const _DeadStockGroupPanel({
    required this.title,
    required this.icon,
    required this.groups,
    required this.currencyCode,
  });

  final String title;
  final IconData icon;
  final List<DeadStockGroup> groups;
  final String currencyCode;

  @override
  Widget build(BuildContext context) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No dead stock at the selected threshold.'),
          )
        else
          for (final group in groups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(group.name),
              subtitle: Text(
                '${group.skuCount} SKUs · ${group.neverSoldSkuCount} never sold · ${_quantityLabel(group.quantity)} units',
              ),
              trailing: Text(
                formatMoney(currencyCode, group.totalValueMinor),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
      ],
    ),
  );
}

class _AbcInventorySection extends StatelessWidget {
  const _AbcInventorySection({
    required this.report,
    required this.currencyCode,
  });

  final AbcInventoryReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ABC inventory analysis',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Products ranked by return-adjusted sales contribution. A covers the first ${report.aThreshold.toStringAsFixed(0)}%, B through ${report.bThreshold.toStringAsFixed(0)}%, and C the remainder.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.analytics_outlined,
                  label: 'Analyzed sales',
                  value: formatMoney(currencyCode, report.netSalesMinor),
                  detail: '${report.productCount} products',
                ),
                for (final item in report.classes)
                  _KpiCard(
                    width: width,
                    icon: _abcClassIcon(item.abcClass),
                    label: 'Class ${item.abcClass}',
                    value: formatMoney(currencyCode, item.netSalesMinor),
                    detail:
                        '${item.productCount} products · ${_percentageLabel(item.contributionRate)} of sales',
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.leaderboard_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Product classification',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (report.products.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No positive net product sales in this period.'),
                )
              else
                for (final product in report.products)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: _abcClassColor(
                        context,
                        product.abcClass,
                      ),
                      child: Text(
                        product.abcClass,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(product.productName),
                    subtitle: Text(
                      '${product.categoryName} · ${_percentageLabel(product.contributionRate)} share · ${_percentageLabel(product.cumulativeContributionRate)} cumulative · ${_quantityLabel(product.inventoryQuantity)} in stock',
                    ),
                    trailing: Text(
                      formatMoney(currencyCode, product.netSalesMinor),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

IconData _abcClassIcon(String abcClass) => switch (abcClass) {
  'A' => Icons.star_outline_rounded,
  'B' => Icons.trending_up_rounded,
  _ => Icons.more_horiz_rounded,
};

Color _abcClassColor(BuildContext context, String abcClass) =>
    switch (abcClass) {
      'A' => Colors.green.shade700,
      'B' => Colors.orange.shade800,
      _ => Theme.of(context).colorScheme.secondary,
    };

class _InventoryTurnoverSection extends StatelessWidget {
  const _InventoryTurnoverSection({
    required this.report,
    required this.currencyCode,
  });

  final InventoryTurnoverReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inventory turnover',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          '${report.periodDays}-day two-point average · '
          'current weighted-average inventory cost',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.shopping_cart_checkout_outlined,
                  label: 'Net COGS',
                  value: formatMoney(currencyCode, report.netCogsMinor),
                  detail: '${_quantityLabel(report.netUnitsSold)} net units',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.balance_outlined,
                  label: 'Average inventory',
                  value: formatMoney(
                    currencyCode,
                    report.averageInventoryValueMinor,
                  ),
                  detail: 'Beginning and ending average',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.sync_alt_rounded,
                  label: 'Turnover ratio',
                  value: _turnoverLabel(report.turnoverRatio),
                  detail: 'Net COGS ÷ average inventory',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.calendar_today_outlined,
                  label: 'Days on hand',
                  value: _daysOnHandLabel(report.daysOnHand),
                  detail: report.turnoverRatio == null
                      ? 'Requires non-zero inventory value'
                      : 'Estimated at current turnover',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final products = _TurnoverGroupPanel(
              title: 'Turnover by product',
              icon: Icons.inventory_2_outlined,
              groups: report.byProduct,
              currencyCode: currencyCode,
            );
            final categories = _TurnoverGroupPanel(
              title: 'Turnover by category',
              icon: Icons.category_outlined,
              groups: report.byCategory,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [products, const SizedBox(height: 16), categories],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: products),
                const SizedBox(width: 16),
                Expanded(child: categories),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TurnoverGroupPanel extends StatelessWidget {
  const _TurnoverGroupPanel({
    required this.title,
    required this.icon,
    required this.groups,
    required this.currencyCode,
  });

  final String title;
  final IconData icon;
  final List<InventoryTurnoverGroup> groups;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No inventory activity in this period'),
            )
          else
            for (final group in groups.take(12))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_quantityLabel(group.netUnitsSold)} net units · '
                  '${formatMoney(currencyCode, group.averageInventoryValueMinor)} average',
                ),
                trailing: Text(
                  _turnoverLabel(group.turnoverRatio),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
        ],
      ),
    );
  }
}

class _StockAlertSection extends StatelessWidget {
  const _StockAlertSection({
    required this.report,
    required this.currencyCode,
    required this.notifications,
    required this.canManage,
    required this.onRefreshNotifications,
    required this.onAcknowledgeNotification,
  });

  final StockAlertReport report;
  final String currencyCode;
  final List<StockAlertNotification> notifications;
  final bool canManage;
  final VoidCallback onRefreshNotifications;
  final ValueChanged<String> onAcknowledgeNotification;

  @override
  Widget build(BuildContext context) {
    final generated = DateFormat.yMMMd().add_jm().format(report.generatedAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stock alerts', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Available stock after reservations · refreshed $generated',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.notification_important_outlined,
                  label: 'Alert balances',
                  value: report.alertCount.toString(),
                  detail: '${report.affectedSkuCount} affected SKUs',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.remove_shopping_cart_outlined,
                  label: 'Out of stock',
                  value: report.outOfStockCount.toString(),
                  detail: '${report.belowSafetyStockCount} below safety stock',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.add_shopping_cart_outlined,
                  label: 'Minimum reorder',
                  value: _quantityLabel(report.suggestedOrderQuantity),
                  detail: 'Units needed to reach configured threshold',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.payments_outlined,
                  label: 'Estimated cost',
                  value: formatMoney(
                    currencyCode,
                    report.estimatedReorderCostMinor,
                  ),
                  detail: 'Using current weighted-average cost',
                ),
              ],
            );
          },
        ),
        if (report.unconfiguredThresholdCount > 0) ...[
          const SizedBox(height: 16),
          AppPanel(
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${report.unconfiguredThresholdCount} out-of-stock '
                    'balance${report.unconfiguredThresholdCount == 1 ? '' : 's'} '
                    'need a reorder point or safety-stock threshold.',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Items requiring attention',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (report.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'No stock alerts across accessible warehouses.',
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final (index, item) in report.items.indexed) ...[
                  if (index > 0) const Divider(height: 24),
                  _StockAlertItemRow(item: item, currencyCode: currencyCode),
                ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'In-app notifications',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (canManage)
                    OutlinedButton.icon(
                      onPressed: onRefreshNotifications,
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Refresh'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Notifications stay open until stock recovers or an inventory manager acknowledges them.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (notifications.isEmpty)
                const Text('No active stock notifications.')
              else
                for (final notification in notifications)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      notification.status == 'acknowledged'
                          ? Icons.done_all_rounded
                          : Icons.warning_amber_rounded,
                      color: _stockSeverityColor(
                        context,
                        notification.severity,
                      ),
                    ),
                    title: Text(
                      '${notification.productName} · ${notification.sku}',
                    ),
                    subtitle: Text(
                      '${notification.warehouseName} · '
                      '${_stockSeverityLabel(notification.severity)} · '
                      '${_quantityLabel(notification.availableQuantity)} available '
                      '(target ${_quantityLabel(notification.targetStock)})',
                    ),
                    trailing: notification.status == 'open' && canManage
                        ? TextButton(
                            onPressed: () =>
                                onAcknowledgeNotification(notification.id),
                            child: const Text('Acknowledge'),
                          )
                        : Text(
                            notification.status == 'acknowledged'
                                ? 'Acknowledged'
                                : 'Resolved',
                          ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            final warehouses = _StockAlertGroupPanel(
              title: 'Alerts by warehouse',
              icon: Icons.warehouse_outlined,
              groups: report.byWarehouse,
              currencyCode: currencyCode,
            );
            final categories = _StockAlertGroupPanel(
              title: 'Alerts by category',
              icon: Icons.category_outlined,
              groups: report.byCategory,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [warehouses, const SizedBox(height: 16), categories],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: warehouses),
                const SizedBox(width: 16),
                Expanded(child: categories),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StockAlertItemRow extends StatelessWidget {
  const _StockAlertItemRow({required this.item, required this.currencyCode});

  final StockAlertItem item;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final color = _stockSeverityColor(context, item.severity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.sku} · ${item.variantName}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _stockSeverityLabel(item.severity),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${item.branchName} · ${item.warehouseName} · '
          '${_quantityLabel(item.availableQuantity)} available · '
          '${_quantityLabel(item.reorderPoint)} reorder point · '
          '${_quantityLabel(item.safetyStock)} safety stock',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 7),
        Text(
          item.thresholdConfigured
              ? 'Minimum order ${_quantityLabel(item.suggestedOrderQuantity)} · '
                    '${formatMoney(currencyCode, item.suggestedOrderCostMinor)} estimated'
              : 'Set a reorder point or safety-stock threshold before replenishment.',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }
}

class _StockAlertGroupPanel extends StatelessWidget {
  const _StockAlertGroupPanel({
    required this.title,
    required this.icon,
    required this.groups,
    required this.currencyCode,
  });

  final String title;
  final IconData icon;
  final List<StockAlertGroup> groups;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No stock alerts available'),
            )
          else
            for (final group in groups)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${group.alertCount} alert${group.alertCount == 1 ? '' : 's'} · '
                  '${_quantityLabel(group.suggestedOrderQuantity)} minimum order',
                ),
                trailing: Text(
                  formatMoney(currencyCode, group.estimatedReorderCostMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
        ],
      ),
    );
  }
}

class _CustomerAnalyticsSection extends StatelessWidget {
  const _CustomerAnalyticsSection({
    required this.report,
    required this.currencyCode,
  });

  final CustomerAnalyticsReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer retention and lifetime value',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Identified customers only · walk-in orders remain in the capture-rate denominator',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.person_search_outlined,
                  label: 'Customer capture',
                  value: _percentageLabel(report.customerCaptureRate),
                  detail:
                      '${report.identifiedPeriodOrders} identified · ${report.walkInPeriodOrders} walk-in',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Returning rate',
                  value: _percentageLabel(report.retentionRate),
                  detail:
                      '${report.returningCustomers} returning · ${report.newCustomers} new',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.repeat_rounded,
                  label: 'Purchase frequency',
                  value: report.averageOrdersPerActiveCustomer == null
                      ? 'Not available'
                      : '${report.averageOrdersPerActiveCustomer!.toStringAsFixed(2)} orders',
                  detail: '${report.activeCustomers} active customers',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.loyalty_outlined,
                  label: 'Average net LTV',
                  value: report.averageLifetimeValueMinor == null
                      ? 'Not available'
                      : formatMoney(
                          currencyCode,
                          report.averageLifetimeValueMinor!,
                        ),
                  detail: '${report.lifetimeCustomerCount} lifetime customers',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _CustomerFact(
                label: 'Identified net revenue',
                value: formatMoney(
                  currencyCode,
                  report.identifiedPeriodNetRevenueMinor,
                ),
              ),
              _CustomerFact(
                label: 'Identified average order',
                value: report.averageIdentifiedOrderValueMinor == null
                    ? 'Not available'
                    : formatMoney(
                        currencyCode,
                        report.averageIdentifiedOrderValueMinor!,
                      ),
              ),
              _CustomerFact(
                label: 'Repeat-customer rate',
                value: _percentageLabel(report.repeatCustomerRate),
              ),
              _CustomerFact(
                label: 'Total net lifetime value',
                value: formatMoney(
                  currencyCode,
                  report.totalLifetimeValueMinor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final retention = _CustomerRetentionPanel(
              points: report.monthlyRetention,
              currencyCode: currencyCode,
            );
            final lifetime = _CustomerLifetimePanel(
              customers: report.topCustomers,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [retention, const SizedBox(height: 16), lifetime],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: retention),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: lifetime),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CustomerFact extends StatelessWidget {
  const _CustomerFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CustomerRetentionPanel extends StatelessWidget {
  const _CustomerRetentionPanel({
    required this.points,
    required this.currencyCode,
  });

  final List<CustomerRetentionPoint> points;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Monthly retention',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final point in points)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(DateFormat.yMMM().format(point.month)),
              subtitle: Text(
                '${point.activeCustomers} active · ${point.newCustomers} new · '
                '${point.returningCustomers} returning',
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _percentageLabel(point.retentionRate),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    formatMoney(currencyCode, point.netRevenueMinor),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerLifetimePanel extends StatelessWidget {
  const _CustomerLifetimePanel({
    required this.customers,
    required this.currencyCode,
  });

  final List<CustomerLifetimeValue> customers;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Top customers by net lifetime value',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (customers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'No identified-customer sales in the selected scope.',
              ),
            )
          else
            for (final customer in customers.take(20))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_customerStatusLabel(customer.periodStatus)} · '
                  '${customer.lifetimeOrderCount} lifetime orders · '
                  '${customer.daysSinceLastPurchase}d since purchase',
                ),
                trailing: Text(
                  formatMoney(currencyCode, customer.netLifetimeValueMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
        ],
      ),
    );
  }
}

class _CustomerCreditAgeingSection extends StatelessWidget {
  const _CustomerCreditAgeingSection({
    required this.report,
    required this.currencyCode,
  });

  final CustomerCreditAgeingReport report;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer credit ageing',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'As of ${DateFormat.yMMMd().format(report.asOfDate)} · age measured from the credit sale or adjustment date',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1000
                ? (constraints.maxWidth - 48) / 4
                : constraints.maxWidth >= 600
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _KpiCard(
                  width: width,
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Outstanding credit',
                  value: formatMoney(
                    currencyCode,
                    report.totalReceivablesMinor,
                  ),
                  detail:
                      '${report.customerCount} customers · ${report.openInvoiceCount} invoices',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.schedule_outlined,
                  label: 'Older than 60 days',
                  value: formatMoney(currencyCode, report.olderThan60Minor),
                  detail: _percentageLabel(report.olderThan60Rate),
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.speed_outlined,
                  label: 'Credit-limit use',
                  value: _percentageLabel(report.creditLimitUtilization),
                  detail:
                      '${report.overLimitCustomerCount} over limit · ${report.unlimitedCustomerCount} without limit',
                ),
                _KpiCard(
                  width: width,
                  icon: Icons.history_outlined,
                  label: 'Balance age',
                  value: report.weightedAverageAgeDays == null
                      ? 'Not available'
                      : '${report.weightedAverageAgeDays!.toStringAsFixed(1)} days',
                  detail: report.oldestAgeDays == null
                      ? 'No open balances'
                      : 'Oldest ${report.oldestAgeDays} days',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final buckets = _CreditAgeingBucketPanel(
              buckets: report.buckets,
              currencyCode: currencyCode,
            );
            final customers = _CustomerCreditExposurePanel(
              customers: report.customers,
              currencyCode: currencyCode,
            );
            if (!wide) {
              return Column(
                children: [buckets, const SizedBox(height: 16), customers],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: buckets),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: customers),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CreditAgeingBucketPanel extends StatelessWidget {
  const _CreditAgeingBucketPanel({
    required this.buckets,
    required this.currencyCode,
  });

  final List<CustomerCreditAgeingBucket> buckets;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.view_timeline_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Ageing buckets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final bucket in buckets)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(bucket.label),
              subtitle: Text(
                '${bucket.customerCount} customers · ${bucket.itemCount} items',
              ),
              trailing: Text(
                formatMoney(currencyCode, bucket.amountMinor),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerCreditExposurePanel extends StatelessWidget {
  const _CustomerCreditExposurePanel({
    required this.customers,
    required this.currencyCode,
  });

  final List<CustomerCreditExposure> customers;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.people_alt_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Customer exposure',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (customers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text('No outstanding customer-credit balances.'),
            )
          else
            for (final customer in customers.take(20))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${customer.openInvoiceCount} invoices · oldest ${customer.oldestAgeDays}d · '
                  '${_percentageLabel(customer.creditLimitUtilization)} of limit',
                ),
                trailing: Text(
                  formatMoney(currencyCode, customer.outstandingAmountMinor),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
        ],
      ),
    );
  }
}

String _percentageLabel(double? value) =>
    value == null ? 'Not available' : '${value.toStringAsFixed(2)}%';

String _customerStatusLabel(String value) => switch (value) {
  'new' => 'New',
  'returning' => 'Returning',
  'inactive' => 'Inactive',
  _ => value,
};

String _stockSeverityLabel(String value) => switch (value) {
  'out_of_stock' => 'Out of stock',
  'below_safety_stock' => 'Below safety',
  'reorder_point' => 'Reorder point',
  _ => value,
};

Color _stockSeverityColor(BuildContext context, String value) =>
    switch (value) {
      'out_of_stock' => Theme.of(context).colorScheme.error,
      'below_safety_stock' => Theme.of(context).colorScheme.tertiary,
      _ => Theme.of(context).colorScheme.primary,
    };

String _turnoverLabel(double? value) =>
    value == null ? 'Not available' : '${value.toStringAsFixed(2)}×';

String _daysOnHandLabel(double? value) =>
    value == null ? 'Not available' : '${value.toStringAsFixed(1)} days';

String _quantityLabel(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}
