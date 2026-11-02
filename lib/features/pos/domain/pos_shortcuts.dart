enum PosShortcutAction {
  showHelp,
  focusCatalog,
  showHeldSales,
  selectCash,
  selectUpi,
  selectRazorpay,
  parkSale,
  saveDraft,
  completeSale,
  cancelSale,
}

class PosShortcutDefinition {
  const PosShortcutDefinition({
    required this.action,
    required this.keyLabel,
    required this.title,
    required this.description,
  });

  final PosShortcutAction action;
  final String keyLabel;
  final String title;
  final String description;
}

const posShortcutDefinitions = <PosShortcutDefinition>[
  PosShortcutDefinition(
    action: PosShortcutAction.showHelp,
    keyLabel: 'F1',
    title: 'Show shortcuts',
    description: 'Open this keyboard reference.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.focusCatalog,
    keyLabel: 'F2',
    title: 'Scan or search',
    description: 'Focus and select the product barcode/search field.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.showHeldSales,
    keyLabel: 'F3',
    title: 'Held sales',
    description: 'Open parked sales to resume or manage them.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.selectCash,
    keyLabel: 'F4',
    title: 'Cash payment',
    description: 'Select cash as the checkout method.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.selectUpi,
    keyLabel: 'F5',
    title: 'UPI payment',
    description: 'Select UPI as the checkout method.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.selectRazorpay,
    keyLabel: 'F6',
    title: 'Razorpay payment',
    description: 'Select Razorpay UPI as the checkout method.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.parkSale,
    keyLabel: 'F8',
    title: 'Park sale',
    description: 'Park or update the current held sale.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.saveDraft,
    keyLabel: 'F9',
    title: 'Save draft',
    description: 'Save or update the current sales draft.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.completeSale,
    keyLabel: 'F10',
    title: 'Complete sale',
    description: 'Start checkout using the selected payment method.',
  ),
  PosShortcutDefinition(
    action: PosShortcutAction.cancelSale,
    keyLabel: 'Esc',
    title: 'Cancel sale',
    description: 'Open the guarded cancel-sale confirmation.',
  ),
];
