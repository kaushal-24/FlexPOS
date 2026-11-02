import 'package:flexpos/core/widgets/data_list_controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pagination helpers expose stable pages and a minimum page', () {
    expect(pageCountFor(0), 1);
    expect(pageCountFor(26), 2);
    expect(
      pageItems(List<int>.generate(26, (index) => index), 0),
      List<int>.generate(25, (index) => index),
    );
    expect(pageItems(List<int>.generate(26, (index) => index), 1), [25]);
    expect(pageItems(const <int>[], 0), isEmpty);
    expect(pageItems([1, 2], 5), isEmpty);
  });
}
