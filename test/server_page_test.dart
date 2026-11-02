import 'package:flexpos/core/data/server_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server JSON pages expose a bounded next cursor', () {
    final page = serverJsonPage([
      {'id': 'a', 'created_at': '2026-10-30T10:00:00Z'},
      {'id': 'b', 'created_at': '2026-10-30T09:00:00Z'},
    ], pageSize: 2);

    expect(page.items, hasLength(2));
    expect(page.hasMore, isTrue);
    expect(page.nextId, 'b');
    expect(page.nextCreatedAt, DateTime.parse('2026-10-30T09:00:00Z'));
  });

  test('short server pages terminate the cursor sequence', () {
    final page = serverJsonPage([
      {'id': 'only', 'created_at': '2026-10-30T10:00:00Z'},
    ], pageSize: 25);

    expect(page.hasMore, isFalse);
    expect(page.isEmpty, isFalse);
  });
}
