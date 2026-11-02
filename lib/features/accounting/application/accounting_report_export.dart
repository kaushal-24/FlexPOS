import 'dart:convert';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart' as xlsx;
import 'package:flexpos/features/accounting/domain/accounting_models.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Uint8List buildAccountingReportCsv({
  required AccountingDashboard data,
  required String businessName,
  required String currencyCode,
  required String periodLabel,
  required DateTime generatedAt,
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
}) {
  final rows = _accountingReportRows(
    data: data,
    businessName: businessName,
    currencyCode: currencyCode,
    periodLabel: periodLabel,
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
  );

  final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  return Uint8List.fromList([...utf8.encode('\uFEFF'), ...utf8.encode(csv)]);
}

List<List<Object?>> _accountingReportRows({
  required AccountingDashboard data,
  required String businessName,
  required String currencyCode,
  required String periodLabel,
  required DateTime generatedAt,
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
}) => <List<Object?>>[
  ['FlexPOS business report'],
  ['Business', businessName],
  ['Period', periodLabel],
  ['Generated', DateFormat('yyyy-MM-dd HH:mm').format(generatedAt)],
  ['Currency', currencyCode],
  [],
  ['Summary', 'Value'],
  ['Net sales', _decimalAmount(data.salesTotalMinor)],
  ['Tax collected', _decimalAmount(data.taxTotalMinor)],
  ['Expenses', _decimalAmount(data.expensesTotalMinor)],
  ['Outstanding receivables', _decimalAmount(data.outstandingReceivablesMinor)],
  ['Completed orders', data.orderCount],
  ['Low-stock items', data.lowStockCount],
  if (data.grossProfitMinor != null)
    ['Gross profit', _decimalAmount(data.grossProfitMinor!)],
  if (data.netProfitMinor != null)
    ['Net profit', _decimalAmount(data.netProfitMinor!)],
  if (data.netProfitMargin != null)
    ['Net profit margin', _percent(data.netProfitMargin)],
  [],
  ['Daily sales'],
  ['Date', 'Orders', 'Net sales ($currencyCode)'],
  for (final point in data.dailySales)
    [
      DateFormat('yyyy-MM-dd').format(point.date),
      point.orders,
      _decimalAmount(point.totalMinor),
    ],
  [],
  ['Settled payments'],
  ['Payment method', 'Amount ($currencyCode)'],
  for (final payment in data.paymentBreakdown)
    [_paymentLabel(payment.method), _decimalAmount(payment.totalMinor)],
  ..._csvBreakdownRows(
    title: 'Sales by branch',
    items: data.branchBreakdown,
    currencyCode: currencyCode,
  ),
  ..._csvBreakdownRows(
    title: 'Sales by employee',
    items: data.employeeBreakdown,
    currencyCode: currencyCode,
  ),
  ..._csvBreakdownRows(
    title: 'Sales by product',
    items: data.productBreakdown,
    currencyCode: currencyCode,
    quantityColumn: true,
  ),
  ..._csvBreakdownRows(
    title: 'Sales by category',
    items: data.categoryBreakdown,
    currencyCode: currencyCode,
    quantityColumn: true,
  ),
  if (inventoryValuation != null)
    ..._csvInventoryValuationRows(
      report: inventoryValuation,
      currencyCode: currencyCode,
    ),
  if (inventoryAgeing != null)
    ..._csvInventoryAgeingRows(
      report: inventoryAgeing,
      currencyCode: currencyCode,
    ),
  if (deadStock != null)
    ..._csvDeadStockRows(report: deadStock, currencyCode: currencyCode),
  if (abcInventory != null)
    ..._csvAbcInventoryRows(report: abcInventory, currencyCode: currencyCode),
  if (inventoryTurnover != null)
    ..._csvInventoryTurnoverRows(
      report: inventoryTurnover,
      currencyCode: currencyCode,
    ),
  if (stockAlerts != null)
    ..._csvStockAlertRows(report: stockAlerts, currencyCode: currencyCode),
  if (customerAnalytics != null)
    ..._csvCustomerAnalyticsRows(
      report: customerAnalytics,
      currencyCode: currencyCode,
    ),
  if (customerCreditAgeing != null)
    ..._csvCustomerCreditAgeingRows(
      report: customerCreditAgeing,
      currencyCode: currencyCode,
    ),
  if (salesTargetComparison != null)
    ..._csvSalesTargetComparisonRows(
      report: salesTargetComparison,
      currencyCode: currencyCode,
    ),
  if (salesForecast != null)
    ..._csvSalesForecastRows(report: salesForecast, currencyCode: currencyCode),
  if (registerStaffPerformance != null)
    ..._csvRegisterStaffPerformanceRows(
      report: registerStaffPerformance,
      currencyCode: currencyCode,
    ),
  if (salesAdjustments != null)
    ..._csvSalesAdjustmentsRows(
      report: salesAdjustments,
      currencyCode: currencyCode,
    ),
  if (promotionPerformance != null)
    ..._csvPromotionPerformanceRows(
      report: promotionPerformance,
      currencyCode: currencyCode,
    ),
  if (purchaseSupplierPerformance != null)
    ..._csvPurchaseSupplierPerformanceRows(
      report: purchaseSupplierPerformance,
      currencyCode: currencyCode,
    ),
];

Uint8List buildAccountingReportExcel({
  required AccountingDashboard data,
  required String businessName,
  required String currencyCode,
  required String periodLabel,
  required DateTime generatedAt,
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
}) {
  final rows = _accountingReportRows(
    data: data,
    businessName: businessName,
    currencyCode: currencyCode,
    periodLabel: periodLabel,
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
  );
  final workbook = xlsx.Excel.createExcel();
  workbook.rename('Sheet1', 'Business report');
  workbook.setDefaultSheet('Business report');
  final sheet = workbook['Business report'];
  final maximumColumns = rows.fold<int>(
    1,
    (maximum, row) => row.length > maximum ? row.length : maximum,
  );
  final columnWidths = List<double>.filled(maximumColumns, 12);
  List<String> headers = const [];

  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.isEmpty) continue;
    final isTitle = rowIndex == 0;
    final isSection = !isTitle && row.length == 1;
    final isHeader = _isExcelHeaderRow(row);
    if (isHeader) {
      headers = [for (final value in row) value?.toString() ?? ''];
    }
    if (isTitle || isSection) {
      sheet.merge(
        xlsx.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        xlsx.CellIndex.indexByColumnRow(
          columnIndex: maximumColumns - 1,
          rowIndex: rowIndex,
        ),
      );
    }
    for (var columnIndex = 0; columnIndex < row.length; columnIndex++) {
      final raw = row[columnIndex];
      final header = columnIndex < headers.length ? headers[columnIndex] : '';
      final parsed = _excelCell(raw, header: header, forceText: isHeader);
      final cell = sheet.cell(
        xlsx.CellIndex.indexByColumnRow(
          columnIndex: columnIndex,
          rowIndex: rowIndex,
        ),
      );
      cell.value = parsed.value;
      cell.cellStyle = _excelStyle(
        kind: isTitle
            ? _ExcelStyleKind.title
            : isSection
            ? _ExcelStyleKind.section
            : isHeader
            ? _ExcelStyleKind.header
            : _ExcelStyleKind.body,
        valueKind: parsed.kind,
      );
      final displayLength = raw?.toString().length ?? 0;
      final desiredWidth = (displayLength + 3).clamp(12, 34).toDouble();
      if (desiredWidth > columnWidths[columnIndex]) {
        columnWidths[columnIndex] = desiredWidth;
      }
    }
  }

  for (var columnIndex = 0; columnIndex < maximumColumns; columnIndex++) {
    final width = columnIndex == 0
        ? columnWidths[columnIndex].clamp(24, 38).toDouble()
        : columnWidths[columnIndex].clamp(12, 28).toDouble();
    sheet.setColumnWidth(columnIndex, width);
  }

  final bytes = workbook.save();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Excel report generation failed.');
  }
  return Uint8List.fromList(bytes);
}

enum _ExcelStyleKind { title, section, header, body }

enum _ExcelValueKind { text, integer, decimal, percent, date, dateTime }

class _ExcelCell {
  const _ExcelCell(this.value, this.kind);

  final xlsx.CellValue? value;
  final _ExcelValueKind kind;
}

_ExcelCell _excelCell(
  Object? value, {
  required String header,
  required bool forceText,
}) {
  if (value == null) return const _ExcelCell(null, _ExcelValueKind.text);
  if (value is int) {
    return _ExcelCell(xlsx.IntCellValue(value), _ExcelValueKind.integer);
  }
  if (value is double) {
    return _ExcelCell(xlsx.DoubleCellValue(value), _ExcelValueKind.decimal);
  }
  if (value is bool) {
    return _ExcelCell(xlsx.BoolCellValue(value), _ExcelValueKind.text);
  }
  if (value is DateTime) {
    return _ExcelCell(
      xlsx.DateTimeCellValue.fromDateTime(value),
      _ExcelValueKind.dateTime,
    );
  }
  final text = value.toString();
  if (forceText || _excelTextHeader(header)) {
    return _ExcelCell(xlsx.TextCellValue(text), _ExcelValueKind.text);
  }
  final percent = RegExp(r'^-?\d+(?:\.\d+)?%$');
  if (percent.hasMatch(text)) {
    return _ExcelCell(
      xlsx.DoubleCellValue(
        double.parse(text.substring(0, text.length - 1)) / 100,
      ),
      _ExcelValueKind.percent,
    );
  }
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (date.hasMatch(text)) {
    final parsed = DateTime.parse(text);
    return _ExcelCell(
      xlsx.DateCellValue(
        year: parsed.year,
        month: parsed.month,
        day: parsed.day,
      ),
      _ExcelValueKind.date,
    );
  }
  final dateTime = DateTime.tryParse(text);
  if (dateTime != null && text.contains(':')) {
    return _ExcelCell(
      xlsx.DateTimeCellValue.fromDateTime(dateTime),
      _ExcelValueKind.dateTime,
    );
  }
  if (RegExp(r'^-?\d+$').hasMatch(text)) {
    return _ExcelCell(
      xlsx.IntCellValue(int.parse(text)),
      _ExcelValueKind.integer,
    );
  }
  if (RegExp(r'^-?\d+\.\d+$').hasMatch(text)) {
    return _ExcelCell(
      xlsx.DoubleCellValue(double.parse(text)),
      _ExcelValueKind.decimal,
    );
  }
  return _ExcelCell(xlsx.TextCellValue(text), _ExcelValueKind.text);
}

bool _excelTextHeader(String value) {
  final normalized = value.toLowerCase();
  return normalized == 'sku' ||
      normalized == 'code' ||
      normalized.contains('email') ||
      normalized.contains('phone') ||
      normalized.endsWith(' id');
}

bool _isExcelHeaderRow(List<Object?> row) {
  if (row.length < 2 || row.any((value) => value is! String)) return false;
  const firstCellHeaders = {
    'Summary',
    'Date',
    'Payment method',
    'Name',
    'Metric',
    'Age',
    'Product',
    'Month',
    'Customer',
    'Bucket',
    'Branch',
    'Staff',
    'Supplier',
  };
  return firstCellHeaders.contains(row.first);
}

xlsx.CellStyle _excelStyle({
  required _ExcelStyleKind kind,
  required _ExcelValueKind valueKind,
}) {
  final style = xlsx.CellStyle(
    fontFamily: xlsx.getFontFamily(xlsx.FontFamily.Arial),
    fontSize: kind == _ExcelStyleKind.title ? 15 : 10,
    bold: kind != _ExcelStyleKind.body,
    fontColorHex: xlsx.ExcelColor.fromHexString(
      kind == _ExcelStyleKind.header ? '#FFFFFF' : '#172033',
    ),
    backgroundColorHex: xlsx.ExcelColor.fromHexString(switch (kind) {
      _ExcelStyleKind.title => '#FFFFFF',
      _ExcelStyleKind.section => '#DCE8F8',
      _ExcelStyleKind.header => '#1F4E78',
      _ExcelStyleKind.body => '#FFFFFF',
    }),
    verticalAlign: xlsx.VerticalAlign.Center,
    horizontalAlign: kind == _ExcelStyleKind.header
        ? xlsx.HorizontalAlign.Center
        : xlsx.HorizontalAlign.Left,
    textWrapping: xlsx.TextWrapping.WrapText,
    bottomBorder: xlsx.Border(
      borderStyle: kind == _ExcelStyleKind.body
          ? xlsx.BorderStyle.Hair
          : xlsx.BorderStyle.Thin,
      borderColorHex: xlsx.ExcelColor.fromHexString('#D9E2F3'),
    ),
  );
  style.numberFormat = switch (valueKind) {
    _ExcelValueKind.integer => const xlsx.CustomNumericNumFormat(
      formatCode: '#,##0',
    ),
    _ExcelValueKind.decimal => const xlsx.CustomNumericNumFormat(
      formatCode: '#,##0.00',
    ),
    _ExcelValueKind.percent => const xlsx.CustomNumericNumFormat(
      formatCode: '0.0%',
    ),
    _ExcelValueKind.date => const xlsx.CustomDateTimeNumFormat(
      formatCode: 'yyyy-mm-dd',
    ),
    _ExcelValueKind.dateTime => xlsx.CustomDateTimeNumFormat(
      formatCode: 'yyyy-mm-dd hh:mm',
    ),
    _ExcelValueKind.text => xlsx.NumFormat.standard_0,
  };
  return style;
}

Future<Uint8List> buildAccountingReportPdf({
  required AccountingDashboard data,
  required String businessName,
  required String currencyCode,
  required String periodLabel,
  required DateTime generatedAt,
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
  final document = pw.Document(
    title: '$businessName business report',
    author: 'FlexPOS',
    subject: 'Business report for $periodLabel',
  );
  final generatedLabel = DateFormat('yyyy-MM-dd HH:mm').format(generatedAt);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        pw.Text(
          businessName,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Business report - $periodLabel',
          style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
        ),
        pw.Text(
          'Generated $generatedLabel | Currency $currencyCode',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 20),
        _sectionTitle('Summary'),
        pw.TableHelper.fromTextArray(
          headers: const ['Metric', 'Value'],
          data: [
            ['Net sales', _money(currencyCode, data.salesTotalMinor)],
            ['Tax collected', _money(currencyCode, data.taxTotalMinor)],
            ['Expenses', _money(currencyCode, data.expensesTotalMinor)],
            [
              'Outstanding receivables',
              _money(currencyCode, data.outstandingReceivablesMinor),
            ],
            ['Completed orders', data.orderCount.toString()],
            ['Low-stock items', data.lowStockCount.toString()],
            if (data.grossProfitMinor != null)
              ['Gross profit', _money(currencyCode, data.grossProfitMinor!)],
            if (data.netProfitMinor != null)
              ['Net profit', _money(currencyCode, data.netProfitMinor!)],
            if (data.netProfitMargin != null)
              ['Net profit margin', _percent(data.netProfitMargin)],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1),
          },
        ),
        pw.SizedBox(height: 22),
        _sectionTitle('Daily sales'),
        if (data.dailySales.isEmpty)
          pw.Text('No completed sales in this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Orders', 'Net sales'],
            data: [
              for (final point in data.dailySales)
                [
                  DateFormat('yyyy-MM-dd').format(point.date),
                  point.orders.toString(),
                  _money(currencyCode, point.totalMinor),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
          ),
        pw.SizedBox(height: 22),
        _sectionTitle('Settled payments'),
        if (data.paymentBreakdown.isEmpty)
          pw.Text('No settled payments in this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Payment method', 'Amount'],
            data: [
              for (final payment in data.paymentBreakdown)
                [
                  _paymentLabel(payment.method),
                  _money(currencyCode, payment.totalMinor),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
            },
          ),
        ..._pdfBreakdownSection(
          title: 'Sales by branch',
          items: data.branchBreakdown,
          currencyCode: currencyCode,
        ),
        ..._pdfBreakdownSection(
          title: 'Sales by employee',
          items: data.employeeBreakdown,
          currencyCode: currencyCode,
        ),
        ..._pdfBreakdownSection(
          title: 'Sales by product',
          items: data.productBreakdown,
          currencyCode: currencyCode,
          quantityColumn: true,
        ),
        ..._pdfBreakdownSection(
          title: 'Sales by category',
          items: data.categoryBreakdown,
          currencyCode: currencyCode,
          quantityColumn: true,
        ),
        if (inventoryValuation != null)
          ..._pdfInventoryValuationSection(
            report: inventoryValuation,
            currencyCode: currencyCode,
          ),
        if (inventoryAgeing != null)
          ..._pdfInventoryAgeingSection(
            report: inventoryAgeing,
            currencyCode: currencyCode,
          ),
        if (deadStock != null)
          ..._pdfDeadStockSection(
            report: deadStock,
            currencyCode: currencyCode,
          ),
        if (abcInventory != null)
          ..._pdfAbcInventorySection(
            report: abcInventory,
            currencyCode: currencyCode,
          ),
        if (inventoryTurnover != null)
          ..._pdfInventoryTurnoverSection(
            report: inventoryTurnover,
            currencyCode: currencyCode,
          ),
        if (stockAlerts != null)
          ..._pdfStockAlertSection(
            report: stockAlerts,
            currencyCode: currencyCode,
          ),
        if (customerAnalytics != null)
          ..._pdfCustomerAnalyticsSection(
            report: customerAnalytics,
            currencyCode: currencyCode,
          ),
        if (customerCreditAgeing != null)
          ..._pdfCustomerCreditAgeingSection(
            report: customerCreditAgeing,
            currencyCode: currencyCode,
          ),
        if (salesTargetComparison != null)
          ..._pdfSalesTargetComparisonSection(
            report: salesTargetComparison,
            currencyCode: currencyCode,
          ),
        if (salesForecast != null)
          ..._pdfSalesForecastSection(
            report: salesForecast,
            currencyCode: currencyCode,
          ),
        if (registerStaffPerformance != null)
          ..._pdfRegisterStaffPerformanceSection(
            report: registerStaffPerformance,
            currencyCode: currencyCode,
          ),
        if (salesAdjustments != null)
          ..._pdfSalesAdjustmentsSection(
            report: salesAdjustments,
            currencyCode: currencyCode,
          ),
        if (promotionPerformance != null)
          ..._pdfPromotionPerformanceSection(
            report: promotionPerformance,
            currencyCode: currencyCode,
          ),
        if (purchaseSupplierPerformance != null)
          ..._pdfPurchaseSupplierPerformanceSection(
            report: purchaseSupplierPerformance,
            currencyCode: currencyCode,
          ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _sectionTitle(String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(
    value,
    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
  ),
);

String _money(String currencyCode, int minor) =>
    '$currencyCode ${_decimalAmount(minor)}';

String _decimalAmount(int minor) => (minor / 100).toStringAsFixed(2);

String _quantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _ratio(double? value) =>
    value == null ? 'Not available' : value.toStringAsFixed(2);

List<List<Object?>> _csvBreakdownRows({
  required String title,
  required List<SalesBreakdownItem> items,
  required String currencyCode,
  bool quantityColumn = false,
}) => [
  [],
  [title],
  [
    'Name',
    quantityColumn ? 'Net quantity' : 'Orders',
    'Amount ($currencyCode)',
  ],
  for (final item in items)
    [
      item.name,
      quantityColumn ? _quantity(item.quantity) : item.orderCount,
      _decimalAmount(item.totalMinor),
    ],
];

List<List<Object?>> _csvInventoryValuationRows({
  required InventoryValuationReport report,
  required String currencyCode,
}) => [
  [],
  ['Inventory valuation'],
  ['Metric', 'Value'],
  ['Current value ($currencyCode)', _decimalAmount(report.totalValueMinor)],
  ['On hand', _quantity(report.onHandQuantity)],
  ['Reserved', _quantity(report.reservedQuantity)],
  ['Available', _quantity(report.availableQuantity)],
  ['Distinct SKUs', report.skuCount],
  ['Low-stock balances', report.lowStockCount],
  [],
  ['Inventory by warehouse'],
  [
    'Name',
    'SKUs',
    'On hand',
    'Reserved',
    'Available',
    'Low stock',
    'Value ($currencyCode)',
  ],
  for (final group in report.byWarehouse)
    [
      group.name,
      group.skuCount,
      _quantity(group.onHandQuantity),
      _quantity(group.reservedQuantity),
      _quantity(group.availableQuantity),
      group.lowStockCount,
      _decimalAmount(group.totalValueMinor),
    ],
  [],
  ['Inventory by category'],
  [
    'Name',
    'SKUs',
    'On hand',
    'Reserved',
    'Available',
    'Low stock',
    'Value ($currencyCode)',
  ],
  for (final group in report.byCategory)
    [
      group.name,
      group.skuCount,
      _quantity(group.onHandQuantity),
      _quantity(group.reservedQuantity),
      _quantity(group.availableQuantity),
      group.lowStockCount,
      _decimalAmount(group.totalValueMinor),
    ],
];

List<List<Object?>> _csvInventoryAgeingRows({
  required InventoryAgeingReport report,
  required String currencyCode,
}) => [
  [],
  ['Inventory ageing'],
  ['As of', DateFormat('yyyy-MM-dd').format(report.asOfDate)],
  ['Method', report.method.toUpperCase()],
  ['Total quantity', _quantity(report.totalQuantity)],
  ['Tracked quantity', _quantity(report.trackedQuantity)],
  ['Untracked quantity', _quantity(report.untrackedQuantity)],
  ['Total value ($currencyCode)', _decimalAmount(report.totalValueMinor)],
  ['Oldest tracked layer (days)', report.oldestAgeDays ?? ''],
  [],
  ['Age buckets'],
  ['Age', 'SKUs', 'Quantity', 'Value ($currencyCode)'],
  for (final bucket in report.buckets)
    [
      bucket.label,
      bucket.skuCount,
      _quantity(bucket.quantity),
      _decimalAmount(bucket.totalValueMinor),
    ],
  ..._csvAgeingGroupRows(
    title: 'Ageing by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._csvAgeingGroupRows(
    title: 'Ageing by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<List<Object?>> _csvAgeingGroupRows({
  required String title,
  required List<InventoryAgeingGroup> groups,
  required String currencyCode,
}) => [
  [],
  [title],
  [
    'Name',
    'SKUs',
    'Quantity',
    'Oldest days',
    'Over 90 days',
    'Value ($currencyCode)',
  ],
  for (final group in groups)
    [
      group.name,
      group.skuCount,
      _quantity(group.quantity),
      group.oldestAgeDays ?? '',
      _quantity(group.olderThan90Quantity),
      _decimalAmount(group.totalValueMinor),
    ],
];

List<List<Object?>> _csvDeadStockRows({
  required DeadStockReport report,
  required String currencyCode,
}) => [
  [],
  ['Dead stock analysis'],
  ['As of', DateFormat('yyyy-MM-dd').format(report.asOfDate)],
  ['Inactivity threshold (days)', report.inactivityDays],
  ['Metric', 'Value'],
  ['Stocked SKUs', report.stockedSkuCount],
  ['Dead-stock SKUs', report.deadSkuCount],
  ['Never-sold SKUs', report.neverSoldSkuCount],
  ['Dead-stock positions', report.deadPositionCount],
  ['Dead-stock quantity', _quantity(report.deadQuantity)],
  ['Reserved dead-stock quantity', _quantity(report.deadReservedQuantity)],
  ['Dead-stock value ($currencyCode)', _decimalAmount(report.deadValueMinor)],
  [
    'Total inventory value ($currencyCode)',
    _decimalAmount(report.totalValueMinor),
  ],
  ['Dead-stock value rate', _percent(report.deadValueRate)],
  [],
  ['Dead-stock items'],
  [
    'Product',
    'Variant',
    'SKU',
    'Warehouse',
    'Category',
    'On hand',
    'Reserved',
    'Available',
    'Average cost ($currencyCode)',
    'Stock value ($currencyCode)',
    'Last sale',
    'Days inactive',
    'Last inbound',
    'Never sold',
  ],
  for (final item in report.items)
    [
      item.productName,
      item.variantName,
      item.sku,
      item.warehouseName,
      item.categoryName,
      _quantity(item.quantityOnHand),
      _quantity(item.quantityReserved),
      _quantity(item.availableQuantity),
      _decimalAmount(item.averageCostMinor),
      _decimalAmount(item.stockValueMinor),
      item.lastSaleAt == null
          ? 'Never'
          : DateFormat('yyyy-MM-dd').format(item.lastSaleAt!),
      item.daysSinceLastSale ?? '',
      item.lastInboundAt == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(item.lastInboundAt!),
      item.neverSold ? 'Yes' : 'No',
    ],
  ..._csvDeadStockGroupRows(
    title: 'Dead stock by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._csvDeadStockGroupRows(
    title: 'Dead stock by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<List<Object?>> _csvDeadStockGroupRows({
  required String title,
  required List<DeadStockGroup> groups,
  required String currencyCode,
}) => [
  [],
  [title],
  [
    'Name',
    'SKUs',
    'Positions',
    'Never sold',
    'Quantity',
    'Value ($currencyCode)',
  ],
  for (final group in groups)
    [
      group.name,
      group.skuCount,
      group.positionCount,
      group.neverSoldSkuCount,
      _quantity(group.quantity),
      _decimalAmount(group.totalValueMinor),
    ],
];

List<List<Object?>> _csvAbcInventoryRows({
  required AbcInventoryReport report,
  required String currencyCode,
}) => [
  [],
  ['ABC inventory analysis'],
  [
    'Period',
    '${DateFormat('yyyy-MM-dd').format(report.periodStart)} to '
        '${DateFormat('yyyy-MM-dd').format(report.periodEnd)}',
  ],
  ['Method', 'Cumulative return-adjusted sales value'],
  ['A threshold', _percent(report.aThreshold)],
  ['B threshold', _percent(report.bThreshold)],
  ['Metric', 'Value'],
  ['Analyzed products', report.productCount],
  ['Net quantity', _quantity(report.netQuantity)],
  ['Net sales ($currencyCode)', _decimalAmount(report.netSalesMinor)],
  ['Inventory quantity', _quantity(report.inventoryQuantity)],
  [
    'Inventory value ($currencyCode)',
    _decimalAmount(report.inventoryValueMinor),
  ],
  [],
  ['ABC class summary'],
  [
    'Class',
    'Products',
    'Net quantity',
    'Net sales ($currencyCode)',
    'Contribution',
    'Inventory quantity',
    'Inventory value ($currencyCode)',
  ],
  for (final item in report.classes)
    [
      item.abcClass,
      item.productCount,
      _quantity(item.netQuantity),
      _decimalAmount(item.netSalesMinor),
      _percent(item.contributionRate),
      _quantity(item.inventoryQuantity),
      _decimalAmount(item.inventoryValueMinor),
    ],
  [],
  ['ABC product detail'],
  [
    'Product',
    'Category',
    'Class',
    'Net quantity',
    'Net sales ($currencyCode)',
    'Contribution',
    'Cumulative contribution',
    'Inventory quantity',
    'Inventory value ($currencyCode)',
  ],
  for (final product in report.products)
    [
      product.productName,
      product.categoryName,
      product.abcClass,
      _quantity(product.netQuantity),
      _decimalAmount(product.netSalesMinor),
      _percent(product.contributionRate),
      _percent(product.cumulativeContributionRate),
      _quantity(product.inventoryQuantity),
      _decimalAmount(product.inventoryValueMinor),
    ],
];

List<List<Object?>> _csvInventoryTurnoverRows({
  required InventoryTurnoverReport report,
  required String currencyCode,
}) => [
  [],
  ['Inventory turnover'],
  ['Metric', 'Value'],
  ['Period days', report.periodDays],
  ['Net COGS ($currencyCode)', _decimalAmount(report.netCogsMinor)],
  ['Net units sold', _quantity(report.netUnitsSold)],
  [
    'Beginning inventory ($currencyCode)',
    _decimalAmount(report.beginningInventoryValueMinor),
  ],
  [
    'Ending inventory ($currencyCode)',
    _decimalAmount(report.endingInventoryValueMinor),
  ],
  [
    'Average inventory ($currencyCode)',
    _decimalAmount(report.averageInventoryValueMinor),
  ],
  ['Turnover ratio', _ratio(report.turnoverRatio)],
  ['Days on hand', _ratio(report.daysOnHand)],
  ..._csvTurnoverGroupRows(
    title: 'Turnover by product',
    groups: report.byProduct,
    currencyCode: currencyCode,
  ),
  ..._csvTurnoverGroupRows(
    title: 'Turnover by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<List<Object?>> _csvTurnoverGroupRows({
  required String title,
  required List<InventoryTurnoverGroup> groups,
  required String currencyCode,
}) => [
  [],
  [title],
  [
    'Name',
    'Net units',
    'Net COGS ($currencyCode)',
    'Average inventory ($currencyCode)',
    'Turnover',
    'Days on hand',
  ],
  for (final group in groups)
    [
      group.name,
      _quantity(group.netUnitsSold),
      _decimalAmount(group.netCogsMinor),
      _decimalAmount(group.averageInventoryValueMinor),
      _ratio(group.turnoverRatio),
      _ratio(group.daysOnHand),
    ],
];

List<List<Object?>> _csvStockAlertRows({
  required StockAlertReport report,
  required String currencyCode,
}) => [
  [],
  ['Stock alerts'],
  ['Metric', 'Value'],
  ['Alert balances', report.alertCount],
  ['Affected SKUs', report.affectedSkuCount],
  ['Out of stock', report.outOfStockCount],
  ['Below safety stock', report.belowSafetyStockCount],
  ['At reorder point', report.reorderPointCount],
  ['Threshold configuration required', report.unconfiguredThresholdCount],
  ['Minimum reorder quantity', _quantity(report.suggestedOrderQuantity)],
  [
    'Estimated reorder cost ($currencyCode)',
    _decimalAmount(report.estimatedReorderCostMinor),
  ],
  [],
  ['Stock alert detail'],
  [
    'Product',
    'Variant',
    'SKU',
    'Severity',
    'Branch',
    'Warehouse',
    'Available',
    'Reorder point',
    'Safety stock',
    'Minimum order',
    'Estimated cost ($currencyCode)',
    'Threshold configured',
  ],
  for (final item in report.items)
    [
      item.productName,
      item.variantName,
      item.sku,
      _stockSeverityLabel(item.severity),
      item.branchName,
      item.warehouseName,
      _quantity(item.availableQuantity),
      _quantity(item.reorderPoint),
      _quantity(item.safetyStock),
      _quantity(item.suggestedOrderQuantity),
      _decimalAmount(item.suggestedOrderCostMinor),
      item.thresholdConfigured ? 'Yes' : 'No',
    ],
  ..._csvStockAlertGroupRows(
    title: 'Stock alerts by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._csvStockAlertGroupRows(
    title: 'Stock alerts by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<List<Object?>> _csvStockAlertGroupRows({
  required String title,
  required List<StockAlertGroup> groups,
  required String currencyCode,
}) => [
  [],
  [title],
  [
    'Name',
    'Alerts',
    'Out of stock',
    'Below safety',
    'At reorder point',
    'Minimum order',
    'Estimated cost ($currencyCode)',
  ],
  for (final group in groups)
    [
      group.name,
      group.alertCount,
      group.outOfStockCount,
      group.belowSafetyStockCount,
      group.reorderPointCount,
      _quantity(group.suggestedOrderQuantity),
      _decimalAmount(group.estimatedReorderCostMinor),
    ],
];

List<List<Object?>> _csvCustomerAnalyticsRows({
  required CustomerAnalyticsReport report,
  required String currencyCode,
}) => [
  [],
  ['Customer retention and lifetime value'],
  ['Metric', 'Value'],
  ['Period days', report.periodDays],
  ['Total orders', report.totalPeriodOrders],
  ['Identified-customer orders', report.identifiedPeriodOrders],
  ['Walk-in orders', report.walkInPeriodOrders],
  ['Customer capture rate', _percent(report.customerCaptureRate)],
  ['Active customers', report.activeCustomers],
  ['New customers', report.newCustomers],
  ['Returning customers', report.returningCustomers],
  ['Returning-customer rate', _percent(report.retentionRate)],
  ['Repeat customers', report.repeatCustomers],
  ['Repeat-customer rate', _percent(report.repeatCustomerRate)],
  ['Orders per active customer', _ratio(report.averageOrdersPerActiveCustomer)],
  [
    'Identified net revenue ($currencyCode)',
    _decimalAmount(report.identifiedPeriodNetRevenueMinor),
  ],
  [
    'Identified average order value ($currencyCode)',
    report.averageIdentifiedOrderValueMinor == null
        ? 'Not available'
        : _decimalAmount(report.averageIdentifiedOrderValueMinor!),
  ],
  ['Lifetime customers', report.lifetimeCustomerCount],
  [
    'Total net lifetime value ($currencyCode)',
    _decimalAmount(report.totalLifetimeValueMinor),
  ],
  [
    'Average net lifetime value ($currencyCode)',
    report.averageLifetimeValueMinor == null
        ? 'Not available'
        : _decimalAmount(report.averageLifetimeValueMinor!),
  ],
  [],
  ['Monthly customer retention'],
  [
    'Month',
    'Active',
    'New',
    'Returning',
    'Returning rate',
    'Net revenue ($currencyCode)',
  ],
  for (final point in report.monthlyRetention)
    [
      DateFormat('yyyy-MM').format(point.month),
      point.activeCustomers,
      point.newCustomers,
      point.returningCustomers,
      _percent(point.retentionRate),
      _decimalAmount(point.netRevenueMinor),
    ],
  [],
  ['Customer lifetime value'],
  [
    'Customer',
    'Status',
    'Lifetime orders',
    'Net LTV ($currencyCode)',
    'Average order ($currencyCode)',
    'Period orders',
    'Period net revenue ($currencyCode)',
    'Last purchase',
    'Days since purchase',
  ],
  for (final customer in report.topCustomers)
    [
      customer.name,
      _customerStatusLabel(customer.periodStatus),
      customer.lifetimeOrderCount,
      _decimalAmount(customer.netLifetimeValueMinor),
      _decimalAmount(customer.averageOrderValueMinor),
      customer.periodOrderCount,
      _decimalAmount(customer.periodNetRevenueMinor),
      DateFormat('yyyy-MM-dd').format(customer.lastPurchaseAt),
      customer.daysSinceLastPurchase,
    ],
];

List<List<Object?>> _csvCustomerCreditAgeingRows({
  required CustomerCreditAgeingReport report,
  required String currencyCode,
}) => [
  [],
  ['Customer credit ageing'],
  ['As of', DateFormat('yyyy-MM-dd').format(report.asOfDate)],
  ['Age basis', 'Credit sale or adjustment date'],
  ['Metric', 'Value'],
  [
    'Outstanding receivables ($currencyCode)',
    _decimalAmount(report.totalReceivablesMinor),
  ],
  ['Customers with balances', report.customerCount],
  ['Open credit invoices', report.openInvoiceCount],
  ['Open debit adjustments', report.openAdjustmentCount],
  ['Oldest balance (days)', report.oldestAgeDays ?? 'Not available'],
  ['Weighted average age (days)', _ratio(report.weightedAverageAgeDays)],
  [
    'Older than 60 days ($currencyCode)',
    _decimalAmount(report.olderThan60Minor),
  ],
  ['Older than 60 days rate', _percent(report.olderThan60Rate)],
  [
    'Credit limit in scope ($currencyCode)',
    _decimalAmount(report.totalCreditLimitMinor),
  ],
  ['Credit limit utilization', _percent(report.creditLimitUtilization)],
  ['Customers over limit', report.overLimitCustomerCount],
  ['Customers without a limit', report.unlimitedCustomerCount],
  [
    'Unapplied credit adjustments ($currencyCode)',
    _decimalAmount(report.unappliedCreditAdjustmentsMinor),
  ],
  [],
  ['Ageing buckets'],
  ['Bucket', 'Amount ($currencyCode)', 'Customers', 'Items'],
  for (final bucket in report.buckets)
    [
      bucket.label,
      _decimalAmount(bucket.amountMinor),
      bucket.customerCount,
      bucket.itemCount,
    ],
  [],
  ['Customer credit exposure'],
  [
    'Customer',
    'Outstanding ($currencyCode)',
    'Credit limit ($currencyCode)',
    'Utilization',
    '0-30 ($currencyCode)',
    '31-60 ($currencyCode)',
    '61-90 ($currencyCode)',
    '91+ ($currencyCode)',
    'Oldest days',
    'Open invoices',
  ],
  for (final customer in report.customers)
    [
      customer.name,
      _decimalAmount(customer.outstandingAmountMinor),
      _decimalAmount(customer.creditLimitMinor),
      _percent(customer.creditLimitUtilization),
      _decimalAmount(customer.age0To30Minor),
      _decimalAmount(customer.age31To60Minor),
      _decimalAmount(customer.age61To90Minor),
      _decimalAmount(customer.age91PlusMinor),
      customer.oldestAgeDays,
      customer.openInvoiceCount,
    ],
];

List<List<Object?>> _csvSalesTargetComparisonRows({
  required SalesTargetComparisonReport report,
  required String currencyCode,
}) => [
  [],
  ['Sales targets and period comparison'],
  [
    'Current period',
    '${DateFormat('yyyy-MM-dd').format(report.periodStart)} to '
        '${DateFormat('yyyy-MM-dd').format(report.periodEnd)}',
  ],
  [
    'Comparison period',
    '${DateFormat('yyyy-MM-dd').format(report.comparisonStart)} to '
        '${DateFormat('yyyy-MM-dd').format(report.comparisonEnd)}',
  ],
  ['Metric', 'Current', 'Previous / target', 'Change / achievement'],
  [
    'Net sales ($currencyCode)',
    _decimalAmount(report.currentSalesMinor),
    _decimalAmount(report.previousSalesMinor),
    _percent(report.salesChangeRate),
  ],
  [
    'Completed orders',
    report.currentOrders,
    report.previousOrders,
    _percent(report.orderChangeRate),
  ],
  [
    'Average order value ($currencyCode)',
    report.currentAverageOrderValueMinor == null
        ? 'Not available'
        : _decimalAmount(report.currentAverageOrderValueMinor!),
    report.previousAverageOrderValueMinor == null
        ? 'Not available'
        : _decimalAmount(report.previousAverageOrderValueMinor!),
    '',
  ],
  [
    'Sales target ($currencyCode)',
    _decimalAmount(report.currentSalesMinor),
    report.targetAmountMinor == null
        ? 'Not configured'
        : _decimalAmount(report.targetAmountMinor!),
    _percent(report.targetAchievementRate),
  ],
  [
    'Targeted branches',
    report.targetedBranchCount,
    report.accessibleBranchCount,
  ],
  [],
  ['Branch sales targets'],
  [
    'Branch',
    'Current sales ($currencyCode)',
    'Previous sales ($currencyCode)',
    'Sales change',
    'Target ($currencyCode)',
    'Achievement',
    'Gap ($currencyCode)',
    'Orders',
    'Notes',
  ],
  for (final branch in report.branches)
    [
      branch.name,
      _decimalAmount(branch.currentSalesMinor),
      _decimalAmount(branch.previousSalesMinor),
      _percent(branch.salesChangeRate),
      branch.targetAmountMinor == null
          ? 'Not configured'
          : _decimalAmount(branch.targetAmountMinor!),
      _percent(branch.targetAchievementRate),
      branch.targetGapMinor == null
          ? 'Not available'
          : _decimalAmount(branch.targetGapMinor!),
      branch.currentOrders,
      branch.targetNotes ?? '',
    ],
];

List<pw.Widget> _pdfSalesTargetComparisonSection({
  required SalesTargetComparisonReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Sales targets and period comparison'),
  pw.Text(
    '${DateFormat('yyyy-MM-dd').format(report.periodStart)} to '
    '${DateFormat('yyyy-MM-dd').format(report.periodEnd)} versus '
    '${DateFormat('yyyy-MM-dd').format(report.comparisonStart)} to '
    '${DateFormat('yyyy-MM-dd').format(report.comparisonEnd)}',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Current', 'Previous / target', 'Change'],
    data: [
      [
        'Net sales',
        _money(currencyCode, report.currentSalesMinor),
        _money(currencyCode, report.previousSalesMinor),
        _percent(report.salesChangeRate),
      ],
      [
        'Completed orders',
        report.currentOrders.toString(),
        report.previousOrders.toString(),
        _percent(report.orderChangeRate),
      ],
      [
        'Average order',
        report.currentAverageOrderValueMinor == null
            ? 'Not available'
            : _money(currencyCode, report.currentAverageOrderValueMinor!),
        report.previousAverageOrderValueMinor == null
            ? 'Not available'
            : _money(currencyCode, report.previousAverageOrderValueMinor!),
        '-',
      ],
      [
        'Sales target',
        _money(currencyCode, report.currentSalesMinor),
        report.targetAmountMinor == null
            ? 'Not configured'
            : _money(currencyCode, report.targetAmountMinor!),
        _percent(report.targetAchievementRate),
      ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Branch targets'),
  if (report.branches.isEmpty)
    pw.Text('No accessible branches.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Branch',
        'Current',
        'Previous',
        'Change',
        'Target',
        'Achieved',
      ],
      data: [
        for (final branch in report.branches)
          [
            branch.name,
            _money(currencyCode, branch.currentSalesMinor),
            _money(currencyCode, branch.previousSalesMinor),
            _percent(branch.salesChangeRate),
            branch.targetAmountMinor == null
                ? 'Not set'
                : _money(currencyCode, branch.targetAmountMinor!),
            _percent(branch.targetAchievementRate),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      columnWidths: const {0: pw.FlexColumnWidth(1.6)},
    ),
];

List<List<Object?>> _csvSalesForecastRows({
  required SalesForecastReport report,
  required String currencyCode,
}) => [
  [],
  ['Sales forecast'],
  [
    'History period',
    '${DateFormat('yyyy-MM-dd').format(report.historyStart)} to '
        '${DateFormat('yyyy-MM-dd').format(report.historyEnd)}',
  ],
  [
    'Forecast period',
    '${DateFormat('yyyy-MM-dd').format(report.forecastStart)} to '
        '${DateFormat('yyyy-MM-dd').format(report.forecastEnd)}',
  ],
  ['Method', 'Weekday seasonality with linear trend'],
  ['Data quality', _forecastQualityLabel(report.dataQuality)],
  ['Active history days', report.activeHistoryDays, report.historyDays],
  [
    'Historical sales ($currencyCode)',
    _decimalAmount(report.historicalSalesMinor),
  ],
  [
    'Historical daily average ($currencyCode)',
    _decimalAmount(report.historicalDailyAverageMinor),
  ],
  [
    'Projected sales ($currencyCode)',
    _decimalAmount(report.projectedSalesMinor),
  ],
  ['Projected low ($currencyCode)', _decimalAmount(report.projectedLowMinor)],
  ['Projected high ($currencyCode)', _decimalAmount(report.projectedHighMinor)],
  [
    'Projected daily average ($currencyCode)',
    _decimalAmount(report.projectedDailyAverageMinor),
  ],
  ['Projected daily-average change', _percent(report.projectedChangeRate)],
  ['Trend', _forecastTrendLabel(report.trendDirection)],
  [],
  ['Daily forecast'],
  [
    'Date',
    'Estimate ($currencyCode)',
    'Lower estimate ($currencyCode)',
    'Upper estimate ($currencyCode)',
  ],
  for (final point in report.forecast)
    [
      DateFormat('yyyy-MM-dd').format(point.date),
      _decimalAmount(point.estimateMinor),
      _decimalAmount(point.lowerEstimateMinor),
      _decimalAmount(point.upperEstimateMinor),
    ],
];

List<List<Object?>> _csvRegisterStaffPerformanceRows({
  required RegisterStaffPerformanceReport report,
  required String currencyCode,
}) => [
  [],
  ['Register reconciliation and staff performance'],
  ['Closed shifts', report.shiftsClosed],
  ['Balanced shifts', report.balancedShifts],
  ['Over shifts', report.overShifts],
  ['Short shifts', report.shortShifts],
  ['Expected cash ($currencyCode)', _decimalAmount(report.expectedCashMinor)],
  ['Counted cash ($currencyCode)', _decimalAmount(report.closingCashMinor)],
  ['Net variance ($currencyCode)', _decimalAmount(report.netVarianceMinor)],
  [
    'Absolute variance ($currencyCode)',
    _decimalAmount(report.absoluteVarianceMinor),
  ],
  ['Overage ($currencyCode)', _decimalAmount(report.overageMinor)],
  ['Shortage ($currencyCode)', _decimalAmount(report.shortageMinor)],
  [],
  ['Staff performance'],
  [
    'Staff',
    'Email',
    'Orders',
    'Net sales ($currencyCode)',
    'Average order ($currencyCode)',
    'Returns processed',
    'Closed shifts',
    'Balanced',
    'Over',
    'Short',
    'Net variance ($currencyCode)',
    'Absolute variance ($currencyCode)',
  ],
  for (final staff in report.staff)
    [
      staff.name,
      staff.email,
      staff.orders,
      _decimalAmount(staff.netSalesMinor),
      staff.averageOrderValueMinor == null
          ? ''
          : _decimalAmount(staff.averageOrderValueMinor!),
      staff.returnsProcessed,
      staff.shiftsClosed,
      staff.balancedShifts,
      staff.overShifts,
      staff.shortShifts,
      _decimalAmount(staff.netVarianceMinor),
      _decimalAmount(staff.absoluteVarianceMinor),
    ],
  [],
  ['Register reconciliation'],
  [
    'Branch',
    'Register',
    'Code',
    'Closed shifts',
    'Balanced',
    'Over',
    'Short',
    'Expected cash ($currencyCode)',
    'Counted cash ($currencyCode)',
    'Net variance ($currencyCode)',
    'Absolute variance ($currencyCode)',
  ],
  for (final register in report.registers)
    [
      register.branchName,
      register.name,
      register.code,
      register.shiftsClosed,
      register.balancedShifts,
      register.overShifts,
      register.shortShifts,
      _decimalAmount(register.expectedCashMinor),
      _decimalAmount(register.closingCashMinor),
      _decimalAmount(register.netVarianceMinor),
      _decimalAmount(register.absoluteVarianceMinor),
    ],
];

List<List<Object?>> _csvSalesAdjustmentsRows({
  required SalesAdjustmentsReport report,
  required String currencyCode,
}) => [
  [],
  ['Sales adjustments: discounts, returns, and refunds'],
  ['Metric', 'Value'],
  ['Completed sales', report.saleCount],
  ['Discounted sales', report.discountedSaleCount],
  ['Sale subtotal ($currencyCode)', _decimalAmount(report.saleSubtotalMinor)],
  [
    'Total discounts ($currencyCode)',
    _decimalAmount(report.discountTotalMinor),
  ],
  [
    'Line discounts ($currencyCode)',
    _decimalAmount(report.lineDiscountTotalMinor),
  ],
  [
    'Order discounts ($currencyCode)',
    _decimalAmount(report.orderDiscountTotalMinor),
  ],
  ['Discount rate', _percent(report.discountRate)],
  ['Completed returns', report.returnCount],
  ['Returned quantity', _quantity(report.returnedQuantity)],
  ['Refund value ($currencyCode)', _decimalAmount(report.refundTotalMinor)],
  [
    'Returned discounts ($currencyCode)',
    _decimalAmount(report.returnedDiscountTotalMinor),
  ],
  [
    'Settled refunds ($currencyCode)',
    _decimalAmount(report.settledRefundTotalMinor),
  ],
  [
    'Pending refunds ($currencyCode)',
    _decimalAmount(report.pendingRefundTotalMinor),
  ],
  [
    'Failed refunds ($currencyCode)',
    _decimalAmount(report.failedRefundTotalMinor),
  ],
  [
    'Credit notes issued ($currencyCode)',
    _decimalAmount(report.creditNoteTotalMinor),
  ],
  [],
  ['Refund allocation'],
  ['Method', 'Status', 'Returns', 'Amount ($currencyCode)'],
  for (final item in report.refundAllocations)
    [
      _paymentLabel(item.method),
      _paymentLabel(item.status),
      item.returnCount,
      _decimalAmount(item.amountMinor),
    ],
  [],
  ['Return reasons'],
  ['Reason', 'Returns', 'Refund value ($currencyCode)'],
  for (final item in report.returnReasons)
    [item.reason, item.returnCount, _decimalAmount(item.refundTotalMinor)],
  [],
  ['Returned products'],
  [
    'Product',
    'Variant',
    'SKU',
    'Quantity',
    'Returns',
    'Refund value ($currencyCode)',
  ],
  for (final item in report.returnedProducts)
    [
      item.productName,
      item.variantName,
      item.sku,
      _quantity(item.quantity),
      item.returnCount,
      _decimalAmount(item.refundTotalMinor),
    ],
  [],
  ['Discounts by branch'],
  [
    'Branch',
    'Sales',
    'Discounted sales',
    'Subtotal ($currencyCode)',
    'Discount ($currencyCode)',
    'Rate',
  ],
  for (final item in report.branchDiscounts)
    [
      item.branchName,
      item.saleCount,
      item.discountedSaleCount,
      _decimalAmount(item.saleSubtotalMinor),
      _decimalAmount(item.discountTotalMinor),
      _percent(item.discountRate),
    ],
];

List<List<Object?>> _csvPromotionPerformanceRows({
  required PromotionPerformanceReport report,
  required String currencyCode,
}) => [
  [],
  ['Promotion performance'],
  ['Metric', 'Value'],
  ['Promotions', report.promotionCount],
  ['Active promotions', report.activePromotionCount],
  ['Campaigns used', report.campaignsUsed],
  ['Redemptions', report.redemptionCount],
  ['Unique customers', report.uniqueCustomerCount],
  [
    'Discounts granted ($currencyCode)',
    _decimalAmount(report.discountTotalMinor),
  ],
  [
    'Attributed subtotal ($currencyCode)',
    _decimalAmount(report.attributedSubtotalMinor),
  ],
  [
    'Attributed sales ($currencyCode)',
    _decimalAmount(report.attributedSalesMinor),
  ],
  [
    'Average order value ($currencyCode)',
    report.averageOrderValueMinor == null
        ? 'Not available'
        : _decimalAmount(report.averageOrderValueMinor!),
  ],
  ['Discount rate', _percent(report.discountRate)],
  [],
  ['Campaign performance'],
  [
    'Campaign',
    'Code',
    'Branch',
    'Status',
    'Redemptions',
    'Customers',
    'Discount ($currencyCode)',
    'Attributed sales ($currencyCode)',
    'Average order ($currencyCode)',
    'Discount rate',
  ],
  for (final campaign in report.campaigns)
    [
      campaign.name,
      campaign.code,
      campaign.branchName,
      campaign.isActive ? 'Active' : 'Inactive',
      campaign.redemptionCount,
      campaign.uniqueCustomerCount,
      _decimalAmount(campaign.discountTotalMinor),
      _decimalAmount(campaign.attributedSalesMinor),
      campaign.averageOrderValueMinor == null
          ? 'Not available'
          : _decimalAmount(campaign.averageOrderValueMinor!),
      _percent(campaign.discountRate),
    ],
  [],
  ['Daily campaign activity'],
  [
    'Date',
    'Redemptions',
    'Discount ($currencyCode)',
    'Attributed sales ($currencyCode)',
  ],
  for (final point in report.daily)
    [
      DateFormat('yyyy-MM-dd').format(point.day),
      point.redemptionCount,
      _decimalAmount(point.discountTotalMinor),
      _decimalAmount(point.attributedSalesMinor),
    ],
];

List<List<Object?>> _csvPurchaseSupplierPerformanceRows({
  required PurchaseSupplierPerformanceReport report,
  required String currencyCode,
}) => [
  [],
  ['Purchase and supplier performance'],
  ['Metric', 'Value'],
  ['Purchase orders', report.orderCount],
  ['Received orders', report.receivedOrderCount],
  ['Partially received orders', report.partiallyReceivedOrderCount],
  ['Open orders', report.openOrderCount],
  ['Cancelled orders', report.cancelledOrderCount],
  ['Overdue orders', report.overdueOrderCount],
  ['On-time deliveries', report.onTimeOrderCount],
  ['Late deliveries', report.lateOrderCount],
  ['On-time delivery rate', _percent(report.onTimeRate)],
  ['Ordered total ($currencyCode)', _decimalAmount(report.orderedTotalMinor)],
  ['Received cost ($currencyCode)', _decimalAmount(report.receivedCostMinor)],
  ['Ordered quantity', _quantity(report.orderedQuantity)],
  ['Received quantity', _quantity(report.receivedQuantity)],
  ['Outstanding quantity', _quantity(report.outstandingQuantity)],
  [
    'Outstanding item cost ($currencyCode)',
    _decimalAmount(report.outstandingItemCostMinor),
  ],
  ['Goods receipts', report.receiptCount],
  ['Average lead time (days)', _ratio(report.averageLeadDays)],
  [],
  ['Supplier performance'],
  [
    'Supplier',
    'Orders',
    'Received',
    'Open',
    'Cancelled',
    'Overdue',
    'Ordered total ($currencyCode)',
    'Received cost ($currencyCode)',
    'Ordered qty',
    'Received qty',
    'Outstanding qty',
    'On-time rate',
    'Average lead days',
  ],
  for (final supplier in report.suppliers)
    [
      supplier.supplierName,
      supplier.orderCount,
      supplier.receivedOrderCount,
      supplier.openOrderCount,
      supplier.cancelledOrderCount,
      supplier.overdueOrderCount,
      _decimalAmount(supplier.orderedTotalMinor),
      _decimalAmount(supplier.receivedCostMinor),
      _quantity(supplier.orderedQuantity),
      _quantity(supplier.receivedQuantity),
      _quantity(supplier.outstandingQuantity),
      _percent(supplier.onTimeRate),
      _ratio(supplier.averageLeadDays),
    ],
  [],
  ['Purchased products'],
  [
    'Product',
    'Variant',
    'SKU',
    'Suppliers',
    'Orders',
    'Ordered qty',
    'Received qty',
    'Outstanding qty',
    'Ordered item cost ($currencyCode)',
  ],
  for (final product in report.products)
    [
      product.productName,
      product.variantName,
      product.sku,
      product.supplierCount,
      product.orderCount,
      _quantity(product.orderedQuantity),
      _quantity(product.receivedQuantity),
      _quantity(product.outstandingQuantity),
      _decimalAmount(product.orderedItemCostMinor),
    ],
];

List<pw.Widget> _pdfPromotionPerformanceSection({
  required PromotionPerformanceReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Promotion performance'),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Promotions', report.promotionCount.toString()],
      ['Active promotions', report.activePromotionCount.toString()],
      ['Campaigns used', report.campaignsUsed.toString()],
      ['Redemptions', report.redemptionCount.toString()],
      ['Unique customers', report.uniqueCustomerCount.toString()],
      ['Discounts granted', _money(currencyCode, report.discountTotalMinor)],
      [
        'Attributed subtotal',
        _money(currencyCode, report.attributedSubtotalMinor),
      ],
      ['Attributed sales', _money(currencyCode, report.attributedSalesMinor)],
      [
        'Average order value',
        report.averageOrderValueMinor == null
            ? 'Not available'
            : _money(currencyCode, report.averageOrderValueMinor!),
      ],
      ['Discount rate', _percent(report.discountRate)],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Campaign performance'),
  if (report.campaigns.isEmpty)
    pw.Text('No promotions or redemptions in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Campaign',
        'Code',
        'Branch',
        'Redemptions',
        'Customers',
        'Discount',
        'Attributed sales',
      ],
      data: [
        for (final campaign in report.campaigns)
          [
            campaign.name,
            campaign.code,
            campaign.branchName,
            campaign.redemptionCount.toString(),
            campaign.uniqueCustomerCount.toString(),
            _money(currencyCode, campaign.discountTotalMinor),
            _money(currencyCode, campaign.attributedSalesMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
  if (report.daily.isNotEmpty) ...[
    pw.SizedBox(height: 18),
    _sectionTitle('Daily campaign activity'),
    pw.TableHelper.fromTextArray(
      headers: const ['Date', 'Redemptions', 'Discount', 'Attributed sales'],
      data: [
        for (final point in report.daily)
          [
            DateFormat('yyyy-MM-dd').format(point.day),
            point.redemptionCount.toString(),
            _money(currencyCode, point.discountTotalMinor),
            _money(currencyCode, point.attributedSalesMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
  ],
];

List<pw.Widget> _pdfPurchaseSupplierPerformanceSection({
  required PurchaseSupplierPerformanceReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Purchase and supplier performance'),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Purchase orders', report.orderCount.toString()],
      [
        'Received / partial / open',
        '${report.receivedOrderCount} / ${report.partiallyReceivedOrderCount} / ${report.openOrderCount}',
      ],
      [
        'Cancelled / overdue',
        '${report.cancelledOrderCount} / ${report.overdueOrderCount}',
      ],
      ['Ordered total', _money(currencyCode, report.orderedTotalMinor)],
      ['Received cost', _money(currencyCode, report.receivedCostMinor)],
      [
        'Ordered / received / outstanding qty',
        '${_quantity(report.orderedQuantity)} / ${_quantity(report.receivedQuantity)} / ${_quantity(report.outstandingQuantity)}',
      ],
      [
        'Outstanding item cost',
        _money(currencyCode, report.outstandingItemCostMinor),
      ],
      ['On-time delivery rate', _percent(report.onTimeRate)],
      ['Average lead time', '${_ratio(report.averageLeadDays)} days'],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Supplier performance'),
  if (report.suppliers.isEmpty)
    pw.Text('No purchase orders in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Supplier',
        'Orders',
        'Open',
        'Overdue',
        'Ordered',
        'Received',
        'On time',
      ],
      data: [
        for (final supplier in report.suppliers)
          [
            supplier.supplierName,
            supplier.orderCount.toString(),
            supplier.openOrderCount.toString(),
            supplier.overdueOrderCount.toString(),
            _money(currencyCode, supplier.orderedTotalMinor),
            _money(currencyCode, supplier.receivedCostMinor),
            _percent(supplier.onTimeRate),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
  pw.SizedBox(height: 18),
  _sectionTitle('Top purchased products'),
  if (report.products.isEmpty)
    pw.Text('No purchase-order items in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Product',
        'SKU',
        'Suppliers',
        'Ordered',
        'Received',
        'Outstanding',
        'Cost',
      ],
      data: [
        for (final product in report.products)
          [
            product.productName,
            product.sku,
            product.supplierCount.toString(),
            _quantity(product.orderedQuantity),
            _quantity(product.receivedQuantity),
            _quantity(product.outstandingQuantity),
            _money(currencyCode, product.orderedItemCostMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
];

List<pw.Widget> _pdfSalesAdjustmentsSection({
  required SalesAdjustmentsReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Sales adjustments: discounts, returns, and refunds'),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      [
        'Completed / discounted sales',
        '${report.saleCount} / ${report.discountedSaleCount}',
      ],
      ['Total discounts', _money(currencyCode, report.discountTotalMinor)],
      [
        'Line / order discounts',
        '${_money(currencyCode, report.lineDiscountTotalMinor)} / ${_money(currencyCode, report.orderDiscountTotalMinor)}',
      ],
      ['Discount rate', _percent(report.discountRate)],
      [
        'Returns / returned quantity',
        '${report.returnCount} / ${_quantity(report.returnedQuantity)}',
      ],
      ['Refund value', _money(currencyCode, report.refundTotalMinor)],
      [
        'Settled / pending refunds',
        '${_money(currencyCode, report.settledRefundTotalMinor)} / ${_money(currencyCode, report.pendingRefundTotalMinor)}',
      ],
      [
        'Credit notes issued',
        _money(currencyCode, report.creditNoteTotalMinor),
      ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Returned products'),
  if (report.returnedProducts.isEmpty)
    pw.Text('No completed returns in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Product', 'Variant', 'SKU', 'Qty', 'Returns', 'Value'],
      data: [
        for (final item in report.returnedProducts)
          [
            item.productName,
            item.variantName,
            item.sku,
            _quantity(item.quantity),
            item.returnCount.toString(),
            _money(currencyCode, item.refundTotalMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
  pw.SizedBox(height: 18),
  _sectionTitle('Refund allocation'),
  if (report.refundAllocations.isEmpty)
    pw.Text('No refund allocations in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Method', 'Status', 'Returns', 'Amount'],
      data: [
        for (final item in report.refundAllocations)
          [
            _paymentLabel(item.method),
            _paymentLabel(item.status),
            item.returnCount.toString(),
            _money(currencyCode, item.amountMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
  pw.SizedBox(height: 8),
  pw.Text(
    'Promotion-attributed sales are summarized in the Promotion performance section below.',
    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
  ),
];

List<pw.Widget> _pdfRegisterStaffPerformanceSection({
  required RegisterStaffPerformanceReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Register reconciliation and staff performance'),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Closed shifts', report.shiftsClosed.toString()],
      [
        'Balanced / over / short',
        '${report.balancedShifts} / ${report.overShifts} / ${report.shortShifts}',
      ],
      ['Expected cash', _money(currencyCode, report.expectedCashMinor)],
      ['Counted cash', _money(currencyCode, report.closingCashMinor)],
      ['Net variance', _money(currencyCode, report.netVarianceMinor)],
      ['Absolute variance', _money(currencyCode, report.absoluteVarianceMinor)],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Staff performance'),
  if (report.staff.isEmpty)
    pw.Text('No active staff found.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Staff',
        'Orders',
        'Net sales',
        'Average order',
        'Returns',
        'Shifts',
        'Variance',
      ],
      data: [
        for (final staff in report.staff)
          [
            staff.name,
            staff.orders.toString(),
            _money(currencyCode, staff.netSalesMinor),
            staff.averageOrderValueMinor == null
                ? '-'
                : _money(currencyCode, staff.averageOrderValueMinor!),
            staff.returnsProcessed.toString(),
            staff.shiftsClosed.toString(),
            _money(currencyCode, staff.netVarianceMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    ),
  pw.SizedBox(height: 18),
  _sectionTitle('Register reconciliation'),
  if (report.registers.isEmpty)
    pw.Text('No accessible registers found.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Register',
        'Branch',
        'Shifts',
        'Balanced',
        'Over',
        'Short',
        'Variance',
      ],
      data: [
        for (final register in report.registers)
          [
            register.name,
            register.branchName,
            register.shiftsClosed.toString(),
            register.balancedShifts.toString(),
            register.overShifts.toString(),
            register.shortShifts.toString(),
            _money(currencyCode, register.netVarianceMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
    ),
];

List<pw.Widget> _pdfSalesForecastSection({
  required SalesForecastReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Sales forecast'),
  pw.Text(
    '${DateFormat('yyyy-MM-dd').format(report.forecastStart)} to '
    '${DateFormat('yyyy-MM-dd').format(report.forecastEnd)} | '
    '${_forecastQualityLabel(report.dataQuality)} data quality',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Projected sales', _money(currencyCode, report.projectedSalesMinor)],
      [
        'Indicative range',
        '${_money(currencyCode, report.projectedLowMinor)} - '
            '${_money(currencyCode, report.projectedHighMinor)}',
      ],
      [
        'Projected daily average',
        _money(currencyCode, report.projectedDailyAverageMinor),
      ],
      ['Change vs history', _percent(report.projectedChangeRate)],
      ['Trend', _forecastTrendLabel(report.trendDirection)],
      [
        'History coverage',
        '${report.activeHistoryDays} active of ${report.historyDays} days',
      ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Daily forecast'),
  pw.TableHelper.fromTextArray(
    headers: const ['Date', 'Estimate', 'Lower', 'Upper'],
    data: [
      for (final point in report.forecast)
        [
          DateFormat('yyyy-MM-dd').format(point.date),
          _money(currencyCode, point.estimateMinor),
          _money(currencyCode, point.lowerEstimateMinor),
          _money(currencyCode, point.upperEstimateMinor),
        ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 7),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  ),
  pw.SizedBox(height: 8),
  pw.Text(
    'Forecasts are estimates, not guaranteed revenue. The range uses historical model residuals.',
    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
  ),
];

List<pw.Widget> _pdfBreakdownSection({
  required String title,
  required List<SalesBreakdownItem> items,
  required String currencyCode,
  bool quantityColumn = false,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle(title),
  if (items.isEmpty)
    pw.Text('No sales in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: ['Name', quantityColumn ? 'Net quantity' : 'Orders', 'Amount'],
      data: [
        for (final item in items)
          [
            item.name,
            quantityColumn
                ? _quantity(item.quantity)
                : item.orderCount.toString(),
            _money(currencyCode, item.totalMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
      },
    ),
];

List<pw.Widget> _pdfInventoryValuationSection({
  required InventoryValuationReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Inventory valuation'),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Current value', _money(currencyCode, report.totalValueMinor)],
      ['On hand', _quantity(report.onHandQuantity)],
      ['Reserved', _quantity(report.reservedQuantity)],
      ['Available', _quantity(report.availableQuantity)],
      ['Distinct SKUs', report.skuCount.toString()],
      ['Low-stock balances', report.lowStockCount.toString()],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  ),
  ..._pdfInventoryGroupSection(
    title: 'Inventory by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._pdfInventoryGroupSection(
    title: 'Inventory by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<pw.Widget> _pdfInventoryAgeingSection({
  required InventoryAgeingReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Inventory ageing'),
  pw.Text(
    'As of ${DateFormat('yyyy-MM-dd').format(report.asOfDate)} | '
    '${report.method.toUpperCase()} consumption',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Age', 'SKUs', 'Quantity', 'Value'],
    data: [
      for (final bucket in report.buckets)
        [
          bucket.label,
          bucket.skuCount.toString(),
          _quantity(bucket.quantity),
          _money(currencyCode, bucket.totalValueMinor),
        ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  ..._pdfAgeingGroupSection(
    title: 'Ageing by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._pdfAgeingGroupSection(
    title: 'Ageing by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<pw.Widget> _pdfAgeingGroupSection({
  required String title,
  required List<InventoryAgeingGroup> groups,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 18),
  _sectionTitle(title),
  if (groups.isEmpty)
    pw.Text('No inventory layers available.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Name', 'Qty', 'Oldest', 'Over 90', 'Value'],
      data: [
        for (final group in groups)
          [
            group.name,
            _quantity(group.quantity),
            group.oldestAgeDays == null ? '-' : '${group.oldestAgeDays}d',
            _quantity(group.olderThan90Quantity),
            _money(currencyCode, group.totalValueMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(0.8),
        2: pw.FlexColumnWidth(0.8),
        3: pw.FlexColumnWidth(0.8),
        4: pw.FlexColumnWidth(1.2),
      },
    ),
];

List<pw.Widget> _pdfDeadStockSection({
  required DeadStockReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Dead stock analysis'),
  pw.Text(
    'As of ${DateFormat('yyyy-MM-dd').format(report.asOfDate)} | '
    'No sale for ${report.inactivityDays}+ days',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      [
        'Dead-stock SKUs',
        '${report.deadSkuCount} of ${report.stockedSkuCount}',
      ],
      ['Never sold', report.neverSoldSkuCount.toString()],
      ['Dead quantity', _quantity(report.deadQuantity)],
      ['Dead-stock value', _money(currencyCode, report.deadValueMinor)],
      ['Share of inventory value', _percent(report.deadValueRate)],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Highest-value dead stock'),
  if (report.items.isEmpty)
    pw.Text('No dead stock at the selected threshold.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Product',
        'SKU',
        'Warehouse',
        'Qty',
        'Inactive',
        'Value',
      ],
      data: [
        for (final item in report.items.take(30))
          [
            item.productName,
            item.sku,
            item.warehouseName,
            _quantity(item.quantityOnHand),
            item.neverSold ? 'Never sold' : '${item.daysSinceLastSale}d',
            _money(currencyCode, item.stockValueMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
  ..._pdfDeadStockGroupSection(
    title: 'Dead stock by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._pdfDeadStockGroupSection(
    title: 'Dead stock by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<pw.Widget> _pdfDeadStockGroupSection({
  required String title,
  required List<DeadStockGroup> groups,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 18),
  _sectionTitle(title),
  if (groups.isEmpty)
    pw.Text('No dead stock at the selected threshold.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Name',
        'SKUs',
        'Positions',
        'Never sold',
        'Qty',
        'Value',
      ],
      data: [
        for (final group in groups)
          [
            group.name,
            group.skuCount.toString(),
            group.positionCount.toString(),
            group.neverSoldSkuCount.toString(),
            _quantity(group.quantity),
            _money(currencyCode, group.totalValueMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
];

List<pw.Widget> _pdfAbcInventorySection({
  required AbcInventoryReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('ABC inventory analysis'),
  pw.Text(
    '${DateFormat('yyyy-MM-dd').format(report.periodStart)} to '
    '${DateFormat('yyyy-MM-dd').format(report.periodEnd)} | '
    'A through ${report.aThreshold.toStringAsFixed(0)}%, '
    'B through ${report.bThreshold.toStringAsFixed(0)}%',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const [
      'Class',
      'Products',
      'Net sales',
      'Contribution',
      'Inventory value',
    ],
    data: [
      for (final item in report.classes)
        [
          item.abcClass,
          item.productCount.toString(),
          _money(currencyCode, item.netSalesMinor),
          _percent(item.contributionRate),
          _money(currencyCode, item.inventoryValueMinor),
        ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Product classification'),
  if (report.products.isEmpty)
    pw.Text('No positive net product sales in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Product',
        'Category',
        'Class',
        'Net sales',
        'Share',
        'Cumulative',
        'Stock value',
      ],
      data: [
        for (final product in report.products)
          [
            product.productName,
            product.categoryName,
            product.abcClass,
            _money(currencyCode, product.netSalesMinor),
            _percent(product.contributionRate),
            _percent(product.cumulativeContributionRate),
            _money(currencyCode, product.inventoryValueMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    ),
];

List<pw.Widget> _pdfInventoryTurnoverSection({
  required InventoryTurnoverReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Inventory turnover'),
  pw.Text(
    '${report.periodDays}-day period | Two-point average inventory at current weighted-average cost',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Net COGS', _money(currencyCode, report.netCogsMinor)],
      ['Net units sold', _quantity(report.netUnitsSold)],
      [
        'Average inventory',
        _money(currencyCode, report.averageInventoryValueMinor),
      ],
      ['Turnover ratio', _ratio(report.turnoverRatio)],
      ['Days on hand', _ratio(report.daysOnHand)],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  ..._pdfTurnoverGroupSection(
    title: 'Turnover by product',
    groups: report.byProduct,
    currencyCode: currencyCode,
  ),
  ..._pdfTurnoverGroupSection(
    title: 'Turnover by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<pw.Widget> _pdfStockAlertSection({
  required StockAlertReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Stock alerts'),
  pw.Text(
    'Minimum replenishment reaches the greater of reorder point and safety stock.',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Alert balances', report.alertCount.toString()],
      ['Affected SKUs', report.affectedSkuCount.toString()],
      ['Out of stock', report.outOfStockCount.toString()],
      ['Below safety stock', report.belowSafetyStockCount.toString()],
      ['At reorder point', report.reorderPointCount.toString()],
      ['Minimum reorder quantity', _quantity(report.suggestedOrderQuantity)],
      [
        'Estimated reorder cost',
        _money(currencyCode, report.estimatedReorderCostMinor),
      ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Stock alert detail'),
  if (report.items.isEmpty)
    pw.Text('No stock alerts across accessible warehouses.')
  else
    pw.TableHelper.fromTextArray(
      headers: const [
        'Product / SKU',
        'Severity',
        'Warehouse',
        'Available',
        'Min order',
        'Est. cost',
      ],
      data: [
        for (final item in report.items)
          [
            '${item.productName} / ${item.sku}',
            _stockSeverityLabel(item.severity),
            item.warehouseName,
            _quantity(item.availableQuantity),
            _quantity(item.suggestedOrderQuantity),
            _money(currencyCode, item.suggestedOrderCostMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 7),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.1),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(0.7),
        4: pw.FlexColumnWidth(0.7),
        5: pw.FlexColumnWidth(1),
      },
    ),
  ..._pdfStockAlertGroupSection(
    title: 'Stock alerts by warehouse',
    groups: report.byWarehouse,
    currencyCode: currencyCode,
  ),
  ..._pdfStockAlertGroupSection(
    title: 'Stock alerts by category',
    groups: report.byCategory,
    currencyCode: currencyCode,
  ),
];

List<pw.Widget> _pdfStockAlertGroupSection({
  required String title,
  required List<StockAlertGroup> groups,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 18),
  _sectionTitle(title),
  if (groups.isEmpty)
    pw.Text('No stock alerts available.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Name', 'Alerts', 'Out', 'Safety', 'Min order', 'Cost'],
      data: [
        for (final group in groups)
          [
            group.name,
            group.alertCount.toString(),
            group.outOfStockCount.toString(),
            group.belowSafetyStockCount.toString(),
            _quantity(group.suggestedOrderQuantity),
            _money(currencyCode, group.estimatedReorderCostMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    ),
];

List<pw.Widget> _pdfCustomerAnalyticsSection({
  required CustomerAnalyticsReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Customer retention and lifetime value'),
  pw.Text(
    'Identified customers only; walk-in orders remain in the capture-rate denominator.',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      ['Customer capture rate', _percent(report.customerCaptureRate)],
      ['Active customers', report.activeCustomers.toString()],
      ['New customers', report.newCustomers.toString()],
      ['Returning customers', report.returningCustomers.toString()],
      ['Returning-customer rate', _percent(report.retentionRate)],
      ['Repeat-customer rate', _percent(report.repeatCustomerRate)],
      [
        'Orders per active customer',
        _ratio(report.averageOrdersPerActiveCustomer),
      ],
      [
        'Identified net revenue',
        _money(currencyCode, report.identifiedPeriodNetRevenueMinor),
      ],
      [
        'Identified average order',
        report.averageIdentifiedOrderValueMinor == null
            ? 'Not available'
            : _money(currencyCode, report.averageIdentifiedOrderValueMinor!),
      ],
      [
        'Total net lifetime value',
        _money(currencyCode, report.totalLifetimeValueMinor),
      ],
      [
        'Average net lifetime value',
        report.averageLifetimeValueMinor == null
            ? 'Not available'
            : _money(currencyCode, report.averageLifetimeValueMinor!),
      ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Monthly customer retention'),
  pw.TableHelper.fromTextArray(
    headers: const ['Month', 'Active', 'New', 'Returning', 'Rate', 'Revenue'],
    data: [
      for (final point in report.monthlyRetention)
        [
          DateFormat('yyyy-MM').format(point.month),
          point.activeCustomers.toString(),
          point.newCustomers.toString(),
          point.returningCustomers.toString(),
          _percent(point.retentionRate),
          _money(currencyCode, point.netRevenueMinor),
        ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Top customers by net lifetime value'),
  if (report.topCustomers.isEmpty)
    pw.Text('No identified-customer sales are available.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Customer', 'Status', 'Orders', 'Net LTV', 'Avg order'],
      data: [
        for (final customer in report.topCustomers)
          [
            customer.name,
            _customerStatusLabel(customer.periodStatus),
            customer.lifetimeOrderCount.toString(),
            _money(currencyCode, customer.netLifetimeValueMinor),
            _money(currencyCode, customer.averageOrderValueMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(0.7),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.1),
      },
    ),
];

List<pw.Widget> _pdfCustomerCreditAgeingSection({
  required CustomerCreditAgeingReport report,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 22),
  _sectionTitle('Customer credit ageing'),
  pw.Text(
    'As of ${DateFormat('yyyy-MM-dd').format(report.asOfDate)}; balances are aged from the credit-sale or adjustment date.',
    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
  ),
  pw.SizedBox(height: 8),
  pw.TableHelper.fromTextArray(
    headers: const ['Metric', 'Value'],
    data: [
      [
        'Outstanding receivables',
        _money(currencyCode, report.totalReceivablesMinor),
      ],
      ['Customers with balances', report.customerCount.toString()],
      ['Open credit invoices', report.openInvoiceCount.toString()],
      [
        'Weighted average age',
        report.weightedAverageAgeDays == null
            ? 'Not available'
            : '${report.weightedAverageAgeDays!.toStringAsFixed(1)} days',
      ],
      [
        'Older than 60 days',
        '${_money(currencyCode, report.olderThan60Minor)} (${_percent(report.olderThan60Rate)})',
      ],
      ['Credit limit utilization', _percent(report.creditLimitUtilization)],
      ['Customers over limit', report.overLimitCustomerCount.toString()],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Ageing buckets'),
  pw.TableHelper.fromTextArray(
    headers: const ['Bucket', 'Amount', 'Customers', 'Items'],
    data: [
      for (final bucket in report.buckets)
        [
          bucket.label,
          _money(currencyCode, bucket.amountMinor),
          bucket.customerCount.toString(),
          bucket.itemCount.toString(),
        ],
    ],
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  ),
  pw.SizedBox(height: 18),
  _sectionTitle('Customer exposure'),
  if (report.customers.isEmpty)
    pw.Text('No outstanding customer-credit balances.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Customer', 'Outstanding', 'Limit', 'Use', 'Oldest'],
      data: [
        for (final customer in report.customers)
          [
            customer.name,
            _money(currencyCode, customer.outstandingAmountMinor),
            _money(currencyCode, customer.creditLimitMinor),
            _percent(customer.creditLimitUtilization),
            '${customer.oldestAgeDays} days',
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(0.8),
        4: pw.FlexColumnWidth(0.8),
      },
    ),
];

List<pw.Widget> _pdfTurnoverGroupSection({
  required String title,
  required List<InventoryTurnoverGroup> groups,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 18),
  _sectionTitle(title),
  if (groups.isEmpty)
    pw.Text('No inventory activity in this period.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Name', 'Units', 'COGS', 'Avg inventory', 'Turnover'],
      data: [
        for (final group in groups)
          [
            group.name,
            _quantity(group.netUnitsSold),
            _money(currencyCode, group.netCogsMinor),
            _money(currencyCode, group.averageInventoryValueMinor),
            _ratio(group.turnoverRatio),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(0.7),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(0.8),
      },
    ),
];

List<pw.Widget> _pdfInventoryGroupSection({
  required String title,
  required List<InventoryValuationGroup> groups,
  required String currencyCode,
}) => [
  pw.SizedBox(height: 18),
  _sectionTitle(title),
  if (groups.isEmpty)
    pw.Text('No inventory balances available.')
  else
    pw.TableHelper.fromTextArray(
      headers: const ['Name', 'SKUs', 'On hand', 'Available', 'Value'],
      data: [
        for (final group in groups)
          [
            group.name,
            group.skuCount.toString(),
            _quantity(group.onHandQuantity),
            _quantity(group.availableQuantity),
            _money(currencyCode, group.totalValueMinor),
          ],
      ],
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(0.7),
        2: pw.FlexColumnWidth(0.9),
        3: pw.FlexColumnWidth(0.9),
        4: pw.FlexColumnWidth(1.2),
      },
    ),
];

String _paymentLabel(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _stockSeverityLabel(String value) => switch (value) {
  'out_of_stock' => 'Out of stock',
  'below_safety_stock' => 'Below safety stock',
  'reorder_point' => 'At reorder point',
  _ => value,
};

String _percent(double? value) =>
    value == null ? 'Not available' : '${value.toStringAsFixed(2)}%';

String _customerStatusLabel(String value) => switch (value) {
  'new' => 'New',
  'returning' => 'Returning',
  'inactive' => 'Inactive',
  _ => value,
};

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
  'insufficient_data' => 'Insufficient history',
  _ => value,
};

String _csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (text.isNotEmpty && '=+-@'.contains(text[0])) {
    text = "'$text";
  }
  if (text.contains(',') || text.contains('"') || text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}
