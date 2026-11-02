import 'dart:io';

/// Lightweight, dependency-free large-data profile for shared paging logic.
/// Run with the Dart SDK: `dart run tool/performance_profile.dart`.
void main() {
  const rowCount = 100000;
  const pageSize = 50;
  final rows = List<int>.generate(rowCount, (index) => index);
  final stopwatch = Stopwatch()..start();
  final page = rows.sublist(50000, 50000 + pageSize);
  stopwatch.stop();

  if (page.length != pageSize) {
    throw StateError('Profile did not produce a complete page');
  }
  final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
  stdout.writeln(
    'large-data page profile: $rowCount rows -> $pageSize rows in ${elapsedMs.toStringAsFixed(2)} ms',
  );
  if (elapsedMs > 100) {
    throw StateError('Local page extraction exceeded the 100 ms budget');
  }
}
