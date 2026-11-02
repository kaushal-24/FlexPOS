import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

String csvCell(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp(r'[",\r\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}

String buildCsv(Iterable<Iterable<Object?>> rows) =>
    rows.map((row) => row.map(csvCell).join(',')).join('\r\n');

Future<Object?> saveCsvExport({
  required String fileName,
  required Iterable<Iterable<Object?>> rows,
}) => FilePicker.saveFile(
  dialogTitle: 'Export CSV',
  fileName: fileName,
  bytes: Uint8List.fromList(utf8.encode(buildCsv(rows))),
  mimeType: 'text/csv',
  type: FileType.custom,
  allowedExtensions: const ['csv'],
);
