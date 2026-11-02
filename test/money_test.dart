import 'package:flexpos/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMoneyToMinor', () {
    test('parses whole and decimal amounts exactly', () {
      expect(parseMoneyToMinor('12'), 1200);
      expect(parseMoneyToMinor('12.3'), 1230);
      expect(parseMoneyToMinor('12.34'), 1234);
      expect(parseMoneyToMinor('1,234.50'), 123450);
    });

    test('rejects negative, malformed, and over-precise amounts', () {
      expect(parseMoneyToMinor('-1'), isNull);
      expect(parseMoneyToMinor('1.234'), isNull);
      expect(parseMoneyToMinor('abc'), isNull);
      expect(parseMoneyToMinor(''), isNull);
    });
  });
}
