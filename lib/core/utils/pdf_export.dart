import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> buildTablePdf({
  required String title,
  required List<String> headers,
  required List<List<Object?>> rows,
}) async {
  final document = pw.Document(title: title, author: 'FlexPOS');
  final normalizedRows = rows
      .map((row) => row.map((cell) => cell?.toString() ?? '').toList())
      .toList(growable: false);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Text(
        title,
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      build: (_) => [
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: normalizedRows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey100,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 4,
          ),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        ),
      ],
    ),
  );
  return document.save();
}

Future<Object?> savePdfExport({
  required String fileName,
  required String title,
  required List<String> headers,
  required List<List<Object?>> rows,
}) async {
  final bytes = await buildTablePdf(title: title, headers: headers, rows: rows);
  return FilePicker.saveFile(
    dialogTitle: 'Save PDF export',
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/pdf',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
}
