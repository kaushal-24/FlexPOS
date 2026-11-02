import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large data page extraction stays within the local budget', () {
    const rowCount = 100000;
    const pageSize = 50;
    final rows = List<int>.generate(rowCount, (index) => index);

    final stopwatch = Stopwatch()..start();
    final page = rows.sublist(50000, 50000 + pageSize);
    stopwatch.stop();

    expect(page, hasLength(pageSize));
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });
}
