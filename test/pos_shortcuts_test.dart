import 'package:flexpos/features/pos/domain/pos_shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('POS keyboard shortcuts have unique keys and actions', () {
    expect(
      posShortcutDefinitions.map((shortcut) => shortcut.keyLabel).toSet(),
      hasLength(posShortcutDefinitions.length),
    );
    expect(
      posShortcutDefinitions.map((shortcut) => shortcut.action).toSet(),
      hasLength(posShortcutDefinitions.length),
    );
  });

  test('POS shortcuts cover discovery, payments, and guarded sale actions', () {
    final actions = posShortcutDefinitions
        .map((shortcut) => shortcut.action)
        .toSet();

    expect(
      actions,
      containsAll(const [
        PosShortcutAction.showHelp,
        PosShortcutAction.focusCatalog,
        PosShortcutAction.showHeldSales,
        PosShortcutAction.selectCash,
        PosShortcutAction.selectUpi,
        PosShortcutAction.selectRazorpay,
        PosShortcutAction.parkSale,
        PosShortcutAction.saveDraft,
        PosShortcutAction.completeSale,
        PosShortcutAction.cancelSale,
      ]),
    );
  });
}
