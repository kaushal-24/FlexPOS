import 'dart:async';
import 'dart:ui' as ui;

import 'package:flexpos/core/utils/money.dart';
import 'package:flexpos/core/widgets/app_panel.dart';
import 'package:flexpos/core/widgets/data_page_skeleton.dart';
import 'package:flexpos/core/widgets/empty_state.dart';
import 'package:flexpos/core/widgets/product_image.dart';
import 'package:flexpos/core/providers/core_providers.dart';
import 'package:flexpos/app/theme/app_motion.dart';
import 'package:flexpos/core/security/biometric_reentry.dart';
import 'package:flexpos/core/security/crud_permissions.dart';
import 'package:flexpos/features/auth/data/auth_repository.dart';
import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flexpos/features/catalog/domain/catalog_models.dart';
import 'package:flexpos/features/customers/data/customer_repository.dart';
import 'package:flexpos/features/customers/domain/customer_models.dart';
import 'package:flexpos/features/inventory/data/inventory_repository.dart';
import 'package:flexpos/features/inventory/domain/inventory_models.dart';
import 'package:flexpos/features/pos/domain/pos_calculations.dart';
import 'package:flexpos/features/pos/domain/pos_catalog_filter.dart';
import 'package:flexpos/features/pos/domain/pos_shortcuts.dart';
import 'package:flexpos/features/pos/presentation/barcode_camera_devices.dart';
import 'package:flexpos/features/payments/data/razorpay_checkout.dart';
import 'package:flexpos/features/promotions/data/promotion_repository.dart';
import 'package:flexpos/features/receipts/presentation/receipt_dialog.dart';
import 'package:flexpos/features/registers/data/register_repository.dart';
import 'package:flexpos/features/registers/domain/register_models.dart';
import 'package:flexpos/features/tenants/domain/business_workspace.dart';
import 'package:flexpos/features/tenants/data/tenant_repository.dart';
import 'package:flexpos/features/tenants/presentation/tenant_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final Map<String, int> _cart = {};
  final Map<String, String> _cartNotes = {};
  final TextEditingController _catalogSearchController =
      TextEditingController();
  final FocusNode _catalogSearchFocusNode = FocusNode(
    debugLabel: 'POS catalog scanner input',
  );
  String _query = '';
  String? _categoryId;
  bool _favoritesOnly = false;
  bool _recentOnly = false;
  String? _warehouseId;
  String? _shiftId;
  String? _customerId;
  String _paymentMethod = 'cash';
  String _creditNoteNumber = '';
  String _giftCardNumber = '';
  int _orderDiscountMinor = 0;
  int _serviceChargeMinor = 0;
  int _cashRoundingMinor = 0;
  String _couponCode = '';
  final Map<String, int> _cartPriceOverrides = {};
  bool _checkingOut = false;
  bool _holdingCart = false;
  bool _savingDraft = false;
  bool _savingQuote = false;
  bool _savingOrder = false;
  String? _resumedHeldCartId;
  String? _resumedHeldCartLabel;
  String? _resumedDraftId;
  String? _resumedDraftTitle;
  String? _resumedQuoteId;
  String? _resumedQuoteTitle;
  DateTime? _resumedQuoteValidUntil;
  SalesOrder? _resumedSalesOrder;
  bool _salesOrderDirty = false;

  @override
  void initState() {
    super.initState();
    // Put the POS in scanner-ready mode as soon as its first frame is
    // mounted. Hardware scanners behave like a keyboard and need a focused
    // text field before they send the first code.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCatalogSearch();
    });
  }

  @override
  void dispose() {
    _catalogSearchController.dispose();
    _catalogSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider).value;
    final snapshot = ref.watch(catalogSnapshotProvider);
    final heldCarts =
        ref.watch(heldPosCartsProvider).value ?? const <HeldPosCart>[];
    final drafts = ref.watch(posDraftsProvider).value ?? const <PosDraft>[];
    final quotes = ref.watch(salesQuotesProvider).value ?? const <SalesQuote>[];
    final salesOrders =
        ref.watch(salesOrdersProvider).value ?? const <SalesOrder>[];
    final customers = ref.watch(customersProvider).value ?? const <Customer>[];
    final registerData =
        ref.watch(registerOperationsProvider).value ??
        RegisterOperationsSnapshot.empty;
    if (workspace == null) {
      return const EmptyState(
        icon: Icons.add_business_outlined,
        title: 'Select a business',
        message: 'A business workspace is required to open the register.',
      );
    }
    if (!workspace.canCreate('sales')) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'POS access is restricted',
        message: 'Your role does not include permission to create sales.',
      );
    }
    return snapshot.when(
      loading: () => const DataPageSkeleton(sectionLabel: 'point of sale'),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not open POS',
        message: error.toString(),
        action: FilledButton.icon(
          onPressed: () => ref.invalidate(catalogSnapshotProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ),
      data: (data) => _buildRegister(
        context,
        workspace,
        data,
        customers,
        registerData,
        heldCarts,
        drafts,
        quotes,
        salesOrders,
      ),
    );
  }

  Widget _buildRegister(
    BuildContext context,
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
    RegisterOperationsSnapshot registerData,
    List<HeldPosCart> heldCarts,
    List<PosDraft> drafts,
    List<SalesQuote> quotes,
    List<SalesOrder> salesOrders,
  ) {
    if (data.warehouses.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'POS inventory is not configured',
        message: 'Ask an administrator to assign inventory to this branch before taking a sale.',
      );
    }
    final selectedWarehouse =
        data.warehouses.any((item) => item.id == _warehouseId)
        ? data.warehouses.firstWhere((item) => item.id == _warehouseId)
        : data.warehouses.first;
    _warehouseId = selectedWarehouse.id;
    final currentUserId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final canManageRegisters = workspace.canUpdate('registers');
    final scopedShifts = registerData.openShifts
        .where(
          (shift) =>
              shift.branchId == selectedWarehouse.branchId &&
              (canManageRegisters || shift.openedBy == currentUserId),
        )
        .toList(growable: false);
    final cashierShifts = scopedShifts
        .where((shift) => shift.openedBy == currentUserId)
        .toList(growable: false);
    final openShifts = canManageRegisters ? scopedShifts : cashierShifts;
    // Cashiers are attached to their own open shift automatically. Managers
    // and administrators can see every open shift for the selected branch so
    // they can supervise or take over a register without being locked to a
    // personal shift.
    final selectedShift =
        openShifts.where((shift) => shift.id == _shiftId).firstOrNull ??
        openShifts.firstOrNull;
    _shiftId = selectedShift?.id;
    final selectedCustomerGroupId = customers
        .where((customer) => customer.id == _customerId)
        .firstOrNull
        ?.groupId;
    data = data.withEffectivePrices(
      customerId: _customerId,
      customerGroupId: selectedCustomerGroupId,
      branchId: selectedWarehouse.branchId,
    );
    final selectedCategoryId =
        data.categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;
    _categoryId = selectedCategoryId;
    final products = filterPosCatalog(
      products: data.products,
      query: _query,
      categoryId: selectedCategoryId,
      favoritesOnly: _favoritesOnly,
    );
    final recentProductIds =
        ref
            .read(sharedPreferencesProvider)
            .getStringList(_recentProductsKey(workspace.businessId)) ??
        const <String>[];
    final visibleProducts = _recentOnly
        ? products
              .where((product) => recentProductIds.contains(product.variantId))
              .toList(growable: false)
        : products;
    final registerBusy =
        _checkingOut ||
        _holdingCart ||
        _savingDraft ||
        _savingQuote ||
        _savingOrder;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): _showPosShortcutHelp,
        const SingleActivator(LogicalKeyboardKey.f2): _focusCatalogSearch,
        const SingleActivator(LogicalKeyboardKey.f3): () {
          if (!registerBusy) _showHeldCarts(workspace, data, customers);
        },
        const SingleActivator(LogicalKeyboardKey.f4): () {
          if (!registerBusy) _selectPaymentShortcut('cash');
        },
        const SingleActivator(LogicalKeyboardKey.f5): () {
          if (!registerBusy) _selectPaymentShortcut('upi');
        },
        const SingleActivator(LogicalKeyboardKey.f6): () {
          if (!registerBusy) _selectPaymentShortcut('razorpay');
        },
        const SingleActivator(LogicalKeyboardKey.f8): () {
          if (!registerBusy) _holdCart(workspace, selectedWarehouse);
        },
        const SingleActivator(LogicalKeyboardKey.f9): () {
          if (!registerBusy) _saveDraft(workspace, selectedWarehouse);
        },
        const SingleActivator(LogicalKeyboardKey.f10): () {
          if (!registerBusy) {
            _checkout(
              workspace,
              data,
              selectedWarehouse,
              customers,
              selectedShift,
            );
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!registerBusy) _cancelCurrentSale();
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final catalog = _CatalogPane(
              products: visibleProducts,
              categories: data.categories,
              selectedCategoryId: selectedCategoryId,
              favoritesOnly: _favoritesOnly,
              hasFavorites: data.products.any((product) => product.isFavorite),
              recentOnly: _recentOnly,
              hasRecentProducts: recentProductIds.any(
                (id) => data.products.any((product) => product.variantId == id),
              ),
              data: data,
              warehouseId: selectedWarehouse.id,
              currencyCode: workspace.currencyCode,
              canCreateCustomItem: workspace.permissionCodes.contains(
                'sales.custom_item',
              ),
              searchController: _catalogSearchController,
              searchFocusNode: _catalogSearchFocusNode,
              queryChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              submitSearch: (value) =>
                  _submitCatalogInput(value, data, selectedWarehouse.id),
              focusSearch: _focusCatalogSearch,
              scanBarcode: () =>
                  _showBarcodeScanner(data, selectedWarehouse.id),
              categoryChanged: (value) => setState(() {
                _categoryId = value;
                _favoritesOnly = false;
                _recentOnly = false;
              }),
              favoritesChanged: (value) => setState(() {
                _favoritesOnly = value;
                _recentOnly = false;
                if (value) _categoryId = null;
              }),
              recentChanged: (value) => setState(() {
                _recentOnly = value;
                _favoritesOnly = false;
                if (value) _categoryId = null;
              }),
              addProduct: (product) {
                _addProduct(product, data, selectedWarehouse.id);
                // A cashier may add a product by tapping the catalog and then
                // immediately scan the next one. Restore scanner focus after
                // the cart rebuild so no F2 press is required.
                _focusCatalogSearchAfterFrame();
              },
              createCustomItem: () => _createCustomSaleItem(workspace, data),
            );
            final cart = _CartPane(
              workspace: workspace,
              data: data,
              cart: _cart,
              cartNotes: _cartNotes,
              openShifts: openShifts,
              shiftId: selectedShift?.id,
              canManageRegisters: canManageRegisters,
              openShift: () => context.push('/registers'),
              customers: customers,
              customerId: _customerId,
              paymentMethod: _paymentMethod,
              orderDiscountMinor: _orderDiscountMinor,
              serviceChargeMinor: _serviceChargeMinor,
              roundingMinor: _cashRoundingMinor,
              canDiscount: workspace.permissionCodes.contains('sales.discount'),
              canServiceCharge:
                  workspace.permissionCodes.contains('sales.service_charge') &&
                  _resumedSalesOrder == null,
              canCashRounding:
                  workspace.permissionCodes.contains('sales.cash_rounding') &&
                  _resumedSalesOrder == null &&
                  _paymentMethod == 'cash',
              canPriceOverride: workspace.permissionCodes.contains(
                'sales.discount',
              ),
              cartPriceOverrides: _cartPriceOverrides,
              checkingOut: _checkingOut,
              holdingCart: _holdingCart,
              savingDraft: _savingDraft,
              savingQuote: _savingQuote,
              savingOrder: _savingOrder,
              heldCartCount: heldCarts.length,
              draftCount: drafts.length,
              quoteCount: quotes.length,
              salesOrderCount: salesOrders.length,
              resumedHeldCartLabel: _resumedHeldCartLabel,
              resumedDraftTitle: _resumedDraftTitle,
              resumedQuoteTitle: _resumedQuoteTitle,
              resumedSalesOrder: _resumedSalesOrder,
              salesOrderDirty: _salesOrderDirty,
              showShortcuts: _showPosShortcutHelp,
              paymentChanged: (value) => setState(() {
                final normalized = _normalizePosPaymentMethod(value);
                _paymentMethod = normalized;
                if (normalized != 'cash') {
                  _cashRoundingMinor = 0;
                }
              }),
              customerChanged: (value) => setState(() {
                _customerId = value;
                _couponCode = '';
                _orderDiscountMinor = 0;
                if (_resumedSalesOrder != null) _salesOrderDirty = true;
              }),
              increment: (product) =>
                  _addProduct(product, data, selectedWarehouse.id),
              decrement: _decrementProduct,
              editItemNote: _editItemNote,
              editPriceOverride: (product) =>
                  _editPriceOverride(product, workspace),
              editDiscount: () => _editDiscount(workspace, data),
              editServiceCharge: () => _editServiceCharge(workspace, data),
              editCashRounding: () => _editCashRounding(workspace, data),
              couponCode: _couponCode,
              applyCoupon: () =>
                  _applyCoupon(workspace, data, selectedWarehouse),
              removeCoupon: () => setState(() {
                _couponCode = '';
                _orderDiscountMinor = 0;
                if (_resumedSalesOrder != null) _salesOrderDirty = true;
              }),
              removeDiscount: () => setState(() {
                _orderDiscountMinor = 0;
                _couponCode = '';
                if (_resumedSalesOrder != null) _salesOrderDirty = true;
              }),
              removeServiceCharge: () => setState(() {
                _serviceChargeMinor = 0;
              }),
              removeCashRounding: () => setState(() {
                _cashRoundingMinor = 0;
              }),
              holdCart: () => _holdCart(workspace, selectedWarehouse),
              showHeldCarts: () => _showHeldCarts(workspace, data, customers),
              saveDraft: () => _saveDraft(workspace, selectedWarehouse),
              showDrafts: () => _showDrafts(workspace, data, customers),
              saveQuote: () => _saveQuote(workspace, data, selectedWarehouse),
              showQuotes: () => _showQuotes(workspace, data, customers),
              saveSalesOrder: () =>
                  _saveSalesOrder(workspace, data, selectedWarehouse),
              showSalesOrders: () =>
                  _showSalesOrders(workspace, data, customers),
              cancelSale: _cancelCurrentSale,
              checkout: () => _checkout(
                workspace,
                data,
                selectedWarehouse,
                customers,
                selectedShift,
              ),
            );
            if (wide) {
              // Give the checkout pane enough room for customer, payment,
              // totals, and action controls. The catalog keeps its own grid
              // sizing instead of stretching to consume the whole viewport.
              final cartWidth = constraints.maxWidth >= 1500 ? 480.0 : 420.0;
              return Row(
                children: [
                  Expanded(flex: 3, child: catalog),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  SizedBox(width: cartWidth, child: cart),
                ],
              );
            }
            return Column(
              children: [
                // Keep both panes bounded and independently scrollable on
                // narrow screens. A fixed cart height overflows short
                // browser/mobile viewports once payment actions are visible.
                Flexible(flex: 4, child: catalog),
                Flexible(flex: 6, child: cart),
              ],
            );
          },
        ),
      ),
    );
  }

  void _focusCatalogSearch() {
    if (!mounted) return;
    _catalogSearchFocusNode.requestFocus();
    _catalogSearchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _catalogSearchController.text.length,
    );
  }

  void _focusCatalogSearchAfterFrame() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusCatalogSearch();
    });
  }

  void _selectPaymentShortcut(String method) {
    setState(() => _paymentMethod = _normalizePosPaymentMethod(method));
    _focusCatalogSearch();
  }

  Future<_UpiPaymentConfirmation?> _showElectronicPaymentDialog({
    required String currencyCode,
    required int amountMinor,
    required String gatewayName,
  }) async {
    if (!mounted) return null;
    // Wait until the checkout button's frame has settled before pushing a
    // root-level dialog. This keeps the QR confirmation visible even when
    // checkout is launched from a responsive/nested POS layout.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    return showDialog<_UpiPaymentConfirmation>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => _UpiPaymentDialog(
        currencyCode: currencyCode,
        amountMinor: amountMinor,
        gatewayName: gatewayName,
      ),
    );
  }

  Future<RazorpayCheckoutResult> _runRazorpayCheckout({
    required CatalogRepository repository,
    required String paymentId,
    required int amountMinor,
    required String currencyCode,
    required String invoiceNumber,
  }) async {
    final order = await repository.createRazorpayOrder(paymentId: paymentId);
    final keyId = order['key_id']?.toString().trim() ?? '';
    final orderId = order['order_id']?.toString().trim() ?? '';
    final amountPaise = int.tryParse(order['amount']?.toString() ?? '');
    final orderCurrency =
        order['currency']?.toString().trim().toUpperCase() ?? '';
    final expectedCurrency = currencyCode.trim().toUpperCase();
    if (keyId.isEmpty ||
        orderId.isEmpty ||
        amountPaise == null ||
        orderCurrency.isEmpty) {
      throw StateError('Razorpay returned an incomplete checkout order.');
    }
    if (amountPaise != amountMinor || orderCurrency != expectedCurrency) {
      throw StateError('Razorpay order amount does not match this sale.');
    }
    final result = await openRazorpayCheckout(
      RazorpayCheckoutRequest(
        keyId: keyId,
        orderId: orderId,
        amountPaise: amountPaise,
        currencyCode: orderCurrency,
        description: 'FlexPOS sale $invoiceNumber',
        customerEmail: ref.read(supabaseClientProvider).auth.currentUser?.email,
      ),
    );
    if (!result.isSuccess) return result;
    await repository.verifyRazorpayPayment(
      paymentId: paymentId,
      orderId: result.orderId!,
      razorpayPaymentId: result.paymentId!,
      signature: result.signature!,
    );
    return result;
  }

  Future<void> _showPosShortcutHelp() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.keyboard_alt_outlined),
        title: const Text('POS keyboard shortcuts'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final shortcut in posShortcutDefinitions)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: 54,
                      child: Text(
                        shortcut.keyLabel,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    title: Text(shortcut.title),
                    subtitle: Text(shortcut.description),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _submitCatalogInput(
    String input,
    CatalogSnapshot data,
    String warehouseId, {
    bool focusSearch = true,
  }) {
    final product = findExactBarcodeProduct(data.products, input);
    if (product == null) {
      if (input.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Barcode detected (${input.trim()}), but it is not in the active catalog.',
            ),
          ),
        );
      }
      if (focusSearch) _focusCatalogSearchAfterFrame();
      return;
    }
    _addProduct(product, data, warehouseId);
    _catalogSearchController.clear();
    setState(() => _query = '');
    if (focusSearch) _focusCatalogSearchAfterFrame();
  }

  Future<void> _showBarcodeScanner(
    CatalogSnapshot data,
    String warehouseId,
  ) async {
    if (!_cameraScannerSupported) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.no_photography_outlined),
          title: const Text('Camera scanning unavailable'),
          content: const Text(
            'This build does not provide camera access. Use the barcode field '
            'with a keyboard-wedge or USB scanner instead.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Use manual scan'),
            ),
          ],
        ),
      );
      _focusCatalogSearchAfterFrame();
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _BarcodeScannerDialog(
        onDetected: (value) {
          if (!mounted) return;
          _submitCatalogInput(value, data, warehouseId, focusSearch: false);
        },
      ),
    );
    // The camera dialog temporarily owns focus. Return to the hardware
    // scanner field as soon as it closes so the next scan is immediate.
    _focusCatalogSearchAfterFrame();
  }

  bool get _cameraScannerSupported {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  Future<void> _createCustomSaleItem(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
  ) async {
    if (_resumedSalesOrder != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Custom items cannot be added to a committed sales order.',
          ),
        ),
      );
      return;
    }
    final request = await showDialog<_CustomSaleItemRequest>(
      context: context,
      builder: (context) => _CustomSaleItemDialog(
        currencyCode: workspace.currencyCode,
        taxRates: data.taxRates,
      ),
    );
    if (request == null || !mounted) return;
    final unit = data.units.firstOrNull;
    if (unit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create an active unit before adding custom items.'),
        ),
      );
      return;
    }
    try {
      final product = await ref
          .read(catalogRepositoryProvider)
          .createCustomSaleItem(
            businessId: workspace.businessId,
            unitId: unit.id,
            taxRateId: request.taxRateId,
            name: request.name,
            priceMinor: request.priceMinor,
          );
      if (!mounted) return;
      ref.invalidate(catalogSnapshotProvider);
      await ref.read(catalogSnapshotProvider.future);
      if (!mounted) return;
      setState(() {
        _cart[product.variantId] = request.quantity;
        _orderDiscountMinor = 0;
        _couponCode = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} added to the sale.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add custom item: $error')),
      );
    }
  }

  void _addProduct(
    CatalogProduct product,
    CatalogSnapshot data,
    String warehouseId,
  ) {
    final next = (_cart[product.variantId] ?? 0) + 1;
    final ownReservation =
        _resumedSalesOrder?.reservedByVariant[product.variantId] ?? 0;
    if (product.trackInventory &&
        next >
            data.stockForWarehouse(product.variantId, warehouseId) +
                ownReservation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Insufficient stock for ${product.name}.')),
      );
      return;
    }
    setState(() {
      _cart[product.variantId] = next;
      _orderDiscountMinor = 0;
      _couponCode = '';
      if (_resumedSalesOrder != null) _salesOrderDirty = true;
    });
  }

  void _decrementProduct(CatalogProduct product) {
    final current = _cart[product.variantId] ?? 0;
    setState(() {
      _orderDiscountMinor = 0;
      _couponCode = '';
      if (_resumedSalesOrder != null) _salesOrderDirty = true;
      if (current <= 1) {
        _cart.remove(product.variantId);
        _cartNotes.remove(product.variantId);
        _cartPriceOverrides.remove(product.variantId);
      } else {
        _cart[product.variantId] = current - 1;
      }
    });
  }

  Future<void> _editItemNote(CatalogProduct product) async {
    final controller = TextEditingController(
      text: _cartNotes[product.variantId] ?? '',
    );
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Note for ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 240,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Item note',
            hintText: 'Special request or packing instruction',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || note == null) return;
    setState(() {
      final normalized = note.trim();
      if (normalized.isEmpty) {
        _cartNotes.remove(product.variantId);
      } else {
        _cartNotes[product.variantId] = normalized;
      }
    });
  }

  Future<void> _holdCart(
    BusinessWorkspace workspace,
    WarehouseOption warehouse,
  ) async {
    if (_cart.isEmpty ||
        _holdingCart ||
        _savingDraft ||
        _savingQuote ||
        _savingOrder ||
        _checkingOut) {
      return;
    }
    final labelController = TextEditingController(
      text:
          _resumedHeldCartLabel ??
          'Held ${DateFormat('MMM d, h:mm a').format(DateTime.now())}',
    );
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.pause_circle_outline_rounded),
        title: Text(
          _resumedHeldCartId == null ? 'Park this sale' : 'Update held sale',
        ),
        content: TextField(
          controller: labelController,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'Table 4 or customer name',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, labelController.text.trim()),
            child: const Text('Park sale'),
          ),
        ],
      ),
    );
    labelController.dispose();
    if (label == null || !mounted) return;
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a label for the held sale.')),
      );
      return;
    }
    setState(() => _holdingCart = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .holdPosCart(
            businessId: workspace.businessId,
            branchId: warehouse.branchId,
            warehouseId: warehouse.id,
            customerId: _customerId,
            label: label,
            paymentMethod: _paymentMethod,
            orderDiscountMinor: _orderDiscountMinor,
            quantitiesByVariant: Map<String, int>.from(_cart),
            heldCartId: _resumedHeldCartId,
          );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _cartNotes.clear();
        _customerId = null;
        _paymentMethod = 'cash';
        _creditNoteNumber = '';
        _giftCardNumber = '';
        _orderDiscountMinor = 0;
        _serviceChargeMinor = 0;
        _cashRoundingMinor = 0;
        _couponCode = '';
        _cartPriceOverrides.clear();
        _resumedHeldCartId = null;
        _resumedHeldCartLabel = null;
        _resumedDraftId = null;
        _resumedDraftTitle = null;
        _resumedQuoteId = null;
        _resumedQuoteTitle = null;
        _resumedQuoteValidUntil = null;
        _resumedSalesOrder = null;
        _salesOrderDirty = false;
      });
      ref.invalidate(heldPosCartsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“$label” is parked and available to resume.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _holdingCart = false);
    }
  }

  Future<void> _showHeldCarts(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) async {
    List<HeldPosCart> heldCarts;
    try {
      heldCarts = await ref
          .read(catalogRepositoryProvider)
          .fetchHeldPosCarts(workspace.businessId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    if (heldCarts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('There are no held sales.')));
      return;
    }
    final action = await showDialog<_HeldCartAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.pause_circle_outline_rounded),
        title: const Text('Held sales'),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: heldCarts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final cart = heldCarts[index];
                return ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: Text(cart.label),
                  subtitle: Text(
                    '${cart.itemCount} items · ${DateFormat.yMMMd().add_jm().format(cart.updatedAt)}',
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    _HeldCartAction(cart: cart, discard: false),
                  ),
                  trailing: IconButton(
                    tooltip: 'Discard held sale',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => Navigator.pop(
                      context,
                      _HeldCartAction(cart: cart, discard: true),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action.discard) {
      await _discardHeldCart(action.cart);
      return;
    }
    if (_cart.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current sale?'),
          content: const Text(
            'The current cart is not parked. Resuming this held sale will replace it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace and resume'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _resumeHeldCart(action.cart, workspace, data, customers);
  }

  Future<void> _discardHeldCart(HeldPosCart cart) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard held sale?'),
        content: Text('“${cart.label}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep sale'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).discardHeldPosCart(cart.id);
      ref.invalidate(heldPosCartsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('“${cart.label}” was discarded.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _resumeHeldCart(
    HeldPosCart heldCart,
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) {
    if (!data.warehouses.any((item) => item.id == heldCart.warehouseId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The held sale warehouse is no longer available.'),
        ),
      );
      return;
    }
    final productIds = data.products.map((item) => item.variantId).toSet();
    if (heldCart.items.any((item) => !productIds.contains(item.variantId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A product in this held sale is no longer available.'),
        ),
      );
      return;
    }
    final canDiscount = workspace.permissionCodes.contains('sales.discount');
    setState(() {
      _warehouseId = heldCart.warehouseId;
      _cartNotes.clear();
      _cart
        ..clear()
        ..addAll(heldCart.quantitiesByVariant);
      _customerId = customers.any((item) => item.id == heldCart.customerId)
          ? heldCart.customerId
          : null;
      _paymentMethod = _normalizePosPaymentMethod(heldCart.paymentMethod);
      _creditNoteNumber = '';
      _giftCardNumber = '';
      _orderDiscountMinor = canDiscount ? heldCart.orderDiscountMinor : 0;
      _shiftId = null;
      _resumedHeldCartId = heldCart.id;
      _resumedHeldCartLabel = heldCart.label;
      _resumedDraftId = null;
      _resumedDraftTitle = null;
      _resumedQuoteId = null;
      _resumedQuoteTitle = null;
      _resumedQuoteValidUntil = null;
      _resumedSalesOrder = null;
      _salesOrderDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '“${heldCart.label}” resumed. Stock and prices will be revalidated at checkout.',
        ),
      ),
    );
  }

  Future<void> _saveDraft(
    BusinessWorkspace workspace,
    WarehouseOption warehouse,
  ) async {
    if (_cart.isEmpty ||
        _savingDraft ||
        _holdingCart ||
        _savingQuote ||
        _savingOrder ||
        _checkingOut) {
      return;
    }
    final titleController = TextEditingController(
      text:
          _resumedDraftTitle ??
          'Draft ${DateFormat('MMM d, h:mm a').format(DateTime.now())}',
    );
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.description_outlined),
        title: Text(
          _resumedDraftId == null ? 'Save sales draft' : 'Update sales draft',
        ),
        content: TextField(
          controller: titleController,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Draft title',
            hintText: 'Tomorrow order or quote follow-up',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, titleController.text.trim()),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );
    titleController.dispose();
    if (title == null || !mounted) return;
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title for the sales draft.')),
      );
      return;
    }
    setState(() => _savingDraft = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .savePosDraft(
            businessId: workspace.businessId,
            branchId: warehouse.branchId,
            warehouseId: warehouse.id,
            customerId: _customerId,
            title: title,
            paymentMethod: _paymentMethod,
            orderDiscountMinor: _orderDiscountMinor,
            quantitiesByVariant: Map<String, int>.from(_cart),
            draftId: _resumedDraftId,
          );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _cartNotes.clear();
        _customerId = null;
        _paymentMethod = 'cash';
        _creditNoteNumber = '';
        _giftCardNumber = '';
        _orderDiscountMinor = 0;
        _serviceChargeMinor = 0;
        _cashRoundingMinor = 0;
        _couponCode = '';
        _cartPriceOverrides.clear();
        _resumedHeldCartId = null;
        _resumedHeldCartLabel = null;
        _resumedDraftId = null;
        _resumedDraftTitle = null;
        _resumedQuoteId = null;
        _resumedQuoteTitle = null;
        _resumedQuoteValidUntil = null;
        _resumedSalesOrder = null;
        _salesOrderDirty = false;
      });
      ref.invalidate(posDraftsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('“$title” was saved as a draft.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingDraft = false);
    }
  }

  Future<void> _showDrafts(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) async {
    List<PosDraft> drafts;
    try {
      drafts = await ref
          .read(catalogRepositoryProvider)
          .fetchPosDrafts(workspace.businessId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no sales drafts.')),
      );
      return;
    }
    final action = await showDialog<_DraftAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.description_outlined),
        title: const Text('Sales drafts'),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: drafts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final draft = drafts[index];
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(draft.title),
                  subtitle: Text(
                    '${draft.itemCount} items · ${DateFormat.yMMMd().add_jm().format(draft.updatedAt)}',
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    _DraftAction(draft: draft, delete: false),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete sales draft',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => Navigator.pop(
                      context,
                      _DraftAction(draft: draft, delete: true),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action.delete) {
      await _deleteDraft(action.draft);
      return;
    }
    if (_cart.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current sale?'),
          content: const Text(
            'The current cart is not saved. Opening this draft will replace it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace and open'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _resumeDraft(action.draft, workspace, data, customers);
  }

  Future<void> _deleteDraft(PosDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sales draft?'),
        content: Text('“${draft.title}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).deletePosDraft(draft.id);
      ref.invalidate(posDraftsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('“${draft.title}” was deleted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _resumeDraft(
    PosDraft draft,
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) {
    if (!data.warehouses.any((item) => item.id == draft.warehouseId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The draft warehouse is no longer available.'),
        ),
      );
      return;
    }
    final productIds = data.products.map((item) => item.variantId).toSet();
    if (draft.items.any((item) => !productIds.contains(item.variantId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A product in this draft is no longer available.'),
        ),
      );
      return;
    }
    final canDiscount = workspace.permissionCodes.contains('sales.discount');
    setState(() {
      _warehouseId = draft.warehouseId;
      _cartNotes.clear();
      _cart
        ..clear()
        ..addAll(draft.quantitiesByVariant);
      _customerId = customers.any((item) => item.id == draft.customerId)
          ? draft.customerId
          : null;
      _paymentMethod = _normalizePosPaymentMethod(draft.paymentMethod);
      _creditNoteNumber = '';
      _giftCardNumber = '';
      _orderDiscountMinor = canDiscount ? draft.orderDiscountMinor : 0;
      _shiftId = null;
      _resumedHeldCartId = null;
      _resumedHeldCartLabel = null;
      _resumedDraftId = draft.id;
      _resumedDraftTitle = draft.title;
      _resumedQuoteId = null;
      _resumedQuoteTitle = null;
      _resumedQuoteValidUntil = null;
      _resumedSalesOrder = null;
      _salesOrderDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '“${draft.title}” opened. Stock and prices will be revalidated at checkout.',
        ),
      ),
    );
  }

  Future<void> _saveQuote(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    WarehouseOption warehouse,
  ) async {
    if (_cart.isEmpty ||
        _savingQuote ||
        _holdingCart ||
        _savingDraft ||
        _savingOrder ||
        _checkingOut) {
      return;
    }
    final now = DateTime.now();
    final details = await showDialog<_QuoteDetails>(
      context: context,
      builder: (context) => _SalesQuoteDialog(
        initialTitle:
            _resumedQuoteTitle ??
            'Quotation ${DateFormat('MMM d, h:mm a').format(now)}',
        initialValidUntil:
            _resumedQuoteValidUntil ?? now.add(const Duration(days: 30)),
        updating: _resumedQuoteId != null,
      ),
    );
    if (details == null || !mounted) return;
    final items = _cart.entries
        .map(
          (entry) => (
            product: data.products.firstWhere(
              (product) => product.variantId == entry.key,
            ),
            quantity: entry.value,
          ),
        )
        .toList(growable: false);
    setState(() => _savingQuote = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .saveSalesQuote(
            businessId: workspace.businessId,
            branchId: warehouse.branchId,
            warehouseId: warehouse.id,
            customerId: _customerId,
            title: details.title,
            validUntil: details.validUntil,
            items: items,
            orderDiscountMinor: _orderDiscountMinor,
            quoteId: _resumedQuoteId,
          );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _cartNotes.clear();
        _customerId = null;
        _paymentMethod = 'cash';
        _creditNoteNumber = '';
        _giftCardNumber = '';
        _orderDiscountMinor = 0;
        _serviceChargeMinor = 0;
        _cashRoundingMinor = 0;
        _couponCode = '';
        _cartPriceOverrides.clear();
        _resumedHeldCartId = null;
        _resumedHeldCartLabel = null;
        _resumedDraftId = null;
        _resumedDraftTitle = null;
        _resumedQuoteId = null;
        _resumedQuoteTitle = null;
        _resumedQuoteValidUntil = null;
        _resumedSalesOrder = null;
        _salesOrderDirty = false;
      });
      ref.invalidate(salesQuotesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“${details.title}” was saved as quotation valid through ${DateFormat.yMMMd().format(details.validUntil)}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingQuote = false);
    }
  }

  Future<void> _showQuotes(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) async {
    List<SalesQuote> quotes;
    try {
      quotes = await ref
          .read(catalogRepositoryProvider)
          .fetchSalesQuotes(workspace.businessId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    if (quotes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no open quotations.')),
      );
      return;
    }
    final action = await showDialog<_QuoteAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.request_quote_outlined),
        title: const Text('Open quotations'),
        content: SizedBox(
          width: 620,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.64,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: quotes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final quote = quotes[index];
                final validity = quote.isExpired
                    ? 'Expired ${DateFormat.yMMMd().format(quote.validUntil)}'
                    : 'Valid through ${DateFormat.yMMMd().format(quote.validUntil)}';
                return ListTile(
                  enabled: !quote.isExpired,
                  leading: Icon(
                    quote.isExpired
                        ? Icons.event_busy_outlined
                        : Icons.request_quote_outlined,
                  ),
                  title: Text(quote.title),
                  subtitle: Text(
                    '${quote.quoteNumber} · ${quote.itemCount} items · ${formatMoney(workspace.currencyCode, quote.grandTotalMinor)}\n$validity',
                  ),
                  isThreeLine: true,
                  onTap: quote.isExpired
                      ? null
                      : () => Navigator.pop(
                          context,
                          _QuoteAction(quote: quote, cancel: false),
                        ),
                  trailing: IconButton(
                    tooltip: 'Cancel quotation',
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () => Navigator.pop(
                      context,
                      _QuoteAction(quote: quote, cancel: true),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action.cancel) {
      await _cancelQuote(action.quote);
      return;
    }
    if (_cart.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current sale?'),
          content: const Text(
            'The current cart is not saved. Opening this quotation will replace it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace and open'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _resumeQuote(action.quote, workspace, data, customers);
  }

  Future<void> _cancelQuote(SalesQuote quote) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: const Text('Cancel quotation?'),
        content: Text(
          '“${quote.title}” (${quote.quoteNumber}) will be retained in history as cancelled and can no longer be converted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep quotation'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel quotation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).cancelSalesQuote(quote.id);
      if (_resumedQuoteId == quote.id && mounted) {
        setState(() {
          _resumedQuoteId = null;
          _resumedQuoteTitle = null;
          _resumedQuoteValidUntil = null;
        });
      }
      ref.invalidate(salesQuotesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('“${quote.title}” was cancelled.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _resumeQuote(
    SalesQuote quote,
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) {
    if (quote.isExpired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This quotation has expired.')),
      );
      return;
    }
    if (!data.warehouses.any((item) => item.id == quote.warehouseId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The quotation warehouse is no longer available.'),
        ),
      );
      return;
    }
    final productIds = data.products.map((item) => item.variantId).toSet();
    if (quote.items.any((item) => !productIds.contains(item.variantId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A product in this quotation is no longer available.'),
        ),
      );
      return;
    }
    final canDiscount = workspace.permissionCodes.contains('sales.discount');
    setState(() {
      _warehouseId = quote.warehouseId;
      _cartNotes.clear();
      _cart
        ..clear()
        ..addAll(quote.quantitiesByVariant);
      _customerId = customers.any((item) => item.id == quote.customerId)
          ? quote.customerId
          : null;
      _paymentMethod = 'cash';
      _creditNoteNumber = '';
      _giftCardNumber = '';
      _orderDiscountMinor = canDiscount ? quote.discountTotalMinor : 0;
      _shiftId = null;
      _resumedHeldCartId = null;
      _resumedHeldCartLabel = null;
      _resumedDraftId = null;
      _resumedDraftTitle = null;
      _resumedQuoteId = quote.id;
      _resumedQuoteTitle = quote.title;
      _resumedQuoteValidUntil = quote.validUntil;
      _resumedSalesOrder = null;
      _salesOrderDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '“${quote.title}” opened. Current prices and stock will be revalidated at checkout.',
        ),
      ),
    );
  }

  Future<void> _saveSalesOrder(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    WarehouseOption warehouse,
  ) async {
    if (_cart.isEmpty ||
        _savingOrder ||
        _savingQuote ||
        _holdingCart ||
        _savingDraft ||
        _checkingOut) {
      return;
    }
    final now = DateTime.now();
    final details = await showDialog<_SalesOrderDetails>(
      context: context,
      builder: (context) => _SalesOrderDialog(
        initialTitle:
            _resumedSalesOrder?.title ??
            'Sales order ${DateFormat('MMM d, h:mm a').format(now)}',
        initialDeliveryOn:
            _resumedSalesOrder?.requestedDeliveryOn ??
            now.add(const Duration(days: 7)),
        updating: _resumedSalesOrder != null,
      ),
    );
    if (details == null || !mounted) return;
    final items = _cart.entries
        .map(
          (entry) => (
            product: data.products.firstWhere(
              (product) => product.variantId == entry.key,
            ),
            quantity: entry.value,
          ),
        )
        .toList(growable: false);
    setState(() => _savingOrder = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .saveSalesOrder(
            businessId: workspace.businessId,
            branchId: warehouse.branchId,
            warehouseId: warehouse.id,
            customerId: _customerId,
            title: details.title,
            requestedDeliveryOn: details.deliveryOn,
            items: items,
            orderDiscountMinor: _orderDiscountMinor,
            salesOrderId: _resumedSalesOrder?.id,
          );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _cartNotes.clear();
        _customerId = null;
        _paymentMethod = 'cash';
        _creditNoteNumber = '';
        _giftCardNumber = '';
        _orderDiscountMinor = 0;
        _serviceChargeMinor = 0;
        _cashRoundingMinor = 0;
        _couponCode = '';
        _cartPriceOverrides.clear();
        _resumedHeldCartId = null;
        _resumedHeldCartLabel = null;
        _resumedDraftId = null;
        _resumedDraftTitle = null;
        _resumedQuoteId = null;
        _resumedQuoteTitle = null;
        _resumedQuoteValidUntil = null;
        _resumedSalesOrder = null;
        _salesOrderDirty = false;
      });
      ref.invalidate(salesOrdersProvider);
      ref.invalidate(catalogSnapshotProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“${details.title}” was saved and its stock is reserved for ${DateFormat.yMMMd().format(details.deliveryOn)}.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _showSalesOrders(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) async {
    List<SalesOrder> orders;
    try {
      orders = await ref
          .read(catalogRepositoryProvider)
          .fetchSalesOrders(workspace.businessId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return;
    }
    if (!mounted) return;
    if (orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There are no open sales orders.')),
      );
      return;
    }
    final action = await showDialog<_SalesOrderAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.inventory_2_outlined),
        title: const Text('Open sales orders'),
        content: SizedBox(
          width: 640,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.64,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: orders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = orders[index];
                final delivery = order.isOverdue
                    ? 'Overdue · ${DateFormat.yMMMd().format(order.requestedDeliveryOn)}'
                    : 'Delivery ${DateFormat.yMMMd().format(order.requestedDeliveryOn)}';
                return ListTile(
                  leading: Icon(
                    order.isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.inventory_2_outlined,
                  ),
                  title: Text(order.title),
                  subtitle: Text(
                    '${order.orderNumber} · ${order.itemCount} items · ${formatMoney(workspace.currencyCode, order.grandTotalMinor)}\n$delivery · stock reserved',
                  ),
                  isThreeLine: true,
                  onTap: () => Navigator.pop(
                    context,
                    _SalesOrderAction(order: order, cancel: false),
                  ),
                  trailing: IconButton(
                    tooltip: 'Cancel sales order',
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () => Navigator.pop(
                      context,
                      _SalesOrderAction(order: order, cancel: true),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action.cancel) {
      await _cancelSalesOrder(action.order);
      return;
    }
    if (_cart.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current sale?'),
          content: const Text(
            'The current cart is not saved. Opening this sales order will replace it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace and open'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _resumeSalesOrder(action.order, workspace, data, customers);
  }

  Future<void> _cancelSalesOrder(SalesOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: const Text('Cancel sales order?'),
        content: Text(
          '“${order.title}” (${order.orderNumber}) will be retained as cancelled and its stock reservation will be released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(catalogRepositoryProvider).cancelSalesOrder(order.id);
      if (_resumedSalesOrder?.id == order.id && mounted) {
        setState(() {
          _resumedSalesOrder = null;
          _salesOrderDirty = false;
        });
      }
      ref.invalidate(salesOrdersProvider);
      ref.invalidate(catalogSnapshotProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '“${order.title}” was cancelled; stock was released.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  void _resumeSalesOrder(
    SalesOrder order,
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    List<Customer> customers,
  ) {
    if (!data.warehouses.any((item) => item.id == order.warehouseId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The sales order warehouse is no longer available.'),
        ),
      );
      return;
    }
    final productIds = data.products.map((item) => item.variantId).toSet();
    if (order.items.any((item) => !productIds.contains(item.variantId))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A product in this sales order is no longer available.',
          ),
        ),
      );
      return;
    }
    final canDiscount = workspace.permissionCodes.contains('sales.discount');
    setState(() {
      _warehouseId = order.warehouseId;
      _cartNotes.clear();
      _cart
        ..clear()
        ..addAll(order.quantitiesByVariant);
      _customerId = customers.any((item) => item.id == order.customerId)
          ? order.customerId
          : null;
      _paymentMethod = 'cash';
      _creditNoteNumber = '';
      _giftCardNumber = '';
      _orderDiscountMinor = canDiscount ? order.orderDiscountMinor : 0;
      _shiftId = null;
      _resumedHeldCartId = null;
      _resumedHeldCartLabel = null;
      _resumedDraftId = null;
      _resumedDraftTitle = null;
      _resumedQuoteId = null;
      _resumedQuoteTitle = null;
      _resumedQuoteValidUntil = null;
      _resumedSalesOrder = order;
      _salesOrderDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '“${order.title}” opened with reserved stock and its committed order total.',
        ),
      ),
    );
  }

  Future<void> _checkGiftCard(BusinessWorkspace workspace) async {
    final cardNumber = _giftCardNumber.trim();
    if (cardNumber.isEmpty) return;
    try {
      final card = await ref
          .read(catalogRepositoryProvider)
          .lookupGiftCard(
            businessId: workspace.businessId,
            cardNumber: cardNumber,
          );
      if (!mounted) return;
      final customerMessage = card.customerId == null
          ? 'Usable by any customer'
          : card.customerId == _customerId
          ? 'Bound to the selected customer'
          : 'Bound to a different customer';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            card.isActive ? Icons.card_giftcard_rounded : Icons.block_outlined,
          ),
          title: Text('Gift card •••• ${card.lastFour}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TotalRow(
                label: 'Available balance',
                value: formatMoney(card.currencyCode, card.balanceMinor),
              ),
              const SizedBox(height: 10),
              Text('Status: ${card.status}'),
              const SizedBox(height: 4),
              Text(customerMessage),
              if (card.expiresAt != null) ...[
                const SizedBox(height: 4),
                Text('Expires: ${DateFormat.yMMMd().format(card.expiresAt!)}'),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check gift card: $error')),
      );
    }
  }

  Future<void> _issueGiftCard(
    BusinessWorkspace workspace,
    WarehouseOption warehouse,
    List<Customer> customers,
  ) async {
    final selectedCustomer = customers
        .where((customer) => customer.id == _customerId)
        .firstOrNull;
    final request = await showDialog<_GiftCardIssueRequest>(
      context: context,
      builder: (context) => _GiftCardIssueDialog(
        currencyCode: workspace.currencyCode,
        customerName: selectedCustomer?.name,
      ),
    );
    if (request == null || !mounted) return;
    try {
      final card = await ref
          .read(catalogRepositoryProvider)
          .issueGiftCard(
            businessId: workspace.businessId,
            branchId: warehouse.branchId,
            initialAmountMinor: request.amountMinor,
            customerId: selectedCustomer?.id,
            expiresAt: request.expiresAt,
          );
      if (!mounted) return;
      setState(() {
        // Gift cards are managed from the administration flows, not used as a
        // cashier tender. Keep the active sale on a supported method.
        _paymentMethod = 'cash';
        _giftCardNumber = card.number;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.card_giftcard_rounded),
          title: const Text('Gift card issued'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Copy this bearer number now. It is shown in full only when issued.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SelectableText(
                card.number,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _TotalRow(
                label: 'Balance',
                value: formatMoney(card.currencyCode, card.balanceMinor),
              ),
              if (card.expiresAt != null) ...[
                const SizedBox(height: 6),
                _TotalRow(
                  label: 'Expires',
                  value: DateFormat.yMMMd().format(card.expiresAt!),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Use for this sale'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not issue gift card: $error')),
      );
    }
  }

  Future<void> _cancelCurrentSale() async {
    if (_cart.isEmpty ||
        _checkingOut ||
        _holdingCart ||
        _savingDraft ||
        _savingQuote ||
        _savingOrder) {
      return;
    }
    final savedCopyDescription = _resumedHeldCartLabel != null
        ? 'The held sale “$_resumedHeldCartLabel” will remain available.'
        : _resumedDraftTitle != null
        ? 'The draft “$_resumedDraftTitle” will remain available.'
        : _resumedQuoteTitle != null
        ? 'The quotation “$_resumedQuoteTitle” will remain available.'
        : _resumedSalesOrder != null
        ? 'The sales order “${_resumedSalesOrder!.title}” and its stock reservation will remain available.'
        : 'This cart has not been saved.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.remove_shopping_cart_outlined),
        title: const Text('Cancel current sale?'),
        content: Text(
          'All items and unsaved changes in the current cart will be cleared. '
          '$savedCopyDescription',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel sale'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _cart.clear();
      _cartNotes.clear();
      _customerId = null;
      _paymentMethod = 'cash';
      _creditNoteNumber = '';
      _giftCardNumber = '';
      _orderDiscountMinor = 0;
      _serviceChargeMinor = 0;
      _cashRoundingMinor = 0;
      _couponCode = '';
      _cartPriceOverrides.clear();
      _resumedHeldCartId = null;
      _resumedHeldCartLabel = null;
      _resumedDraftId = null;
      _resumedDraftTitle = null;
      _resumedQuoteId = null;
      _resumedQuoteTitle = null;
      _resumedQuoteValidUntil = null;
      _resumedSalesOrder = null;
      _salesOrderDirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The current sale was cancelled.')),
    );
  }

  Future<void> _checkout(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    WarehouseOption warehouse,
    List<Customer> customers,
    RegisterShift? shift,
  ) async {
    if (_cart.isEmpty ||
        _checkingOut ||
        _holdingCart ||
        _savingDraft ||
        _savingQuote ||
        _savingOrder) {
      return;
    }
    final resumedSalesOrder = _resumedSalesOrder;
    if (resumedSalesOrder != null && _salesOrderDirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Update the sales order to reserve the edited quantities before fulfillment.',
          ),
        ),
      );
      return;
    }
    final tenantRepository = ref.read(tenantRepositoryProvider);
    bool cashierPinConfigured;
    try {
      cashierPinConfigured = await tenantRepository.hasCashierPin(
        workspace.businessId,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not verify cashier security: $error')),
        );
      }
      return;
    }
    if (cashierPinConfigured) {
      if (!mounted) return;
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _CashierPinDialog(),
      );
      bool pinAccepted = false;
      if (pin != null) {
        try {
          pinAccepted = await tenantRepository.verifyCashierPin(
            businessId: workspace.businessId,
            pin: pin,
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not verify cashier PIN: $error')),
            );
          }
        }
      }
      if (!pinAccepted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cashier PIN was not accepted.')),
          );
        }
        return;
      }
    }
    final items = _cart.entries
        .map((entry) {
          final product = data.products.firstWhere(
            (product) => product.variantId == entry.key,
          );
          return (
            product: product.copyWith(
              priceMinor: _cartPriceOverrides[entry.key],
            ),
            quantity: entry.value,
          );
        })
        .toList(growable: false);
    final totals = calculatePosTotals(
      items,
      orderDiscountMinor: _orderDiscountMinor,
      serviceChargeMinor: _serviceChargeMinor,
      roundingMinor: _cashRoundingMinor,
    );
    var serializedUnitIdsByVariant = <String, List<String>>{};
    if (resumedSalesOrder == null &&
        items.any((item) => item.product.trackingMode != 'none')) {
      if (_paymentMethod == 'credit_note' || _paymentMethod == 'gift_card') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Serialized units currently require a cash or electronic POS payment.',
            ),
          ),
        );
        return;
      }
      final availableUnits = await ref.read(
        serializedInventoryUnitsProvider.future,
      );
      if (!mounted) return;
      final selectedUnits = await showDialog<Map<String, List<String>>>(
        context: context,
        builder: (context) => _SerializedSaleDialog(
          items: items
              .where((item) => item.product.trackingMode != 'none')
              .toList(growable: false),
          warehouseId: warehouse.id,
          units: availableUnits,
        ),
      );
      if (selectedUnits == null || !mounted) return;
      serializedUnitIdsByVariant = selectedUnits;
    }
    final total = resumedSalesOrder?.grandTotalMinor ?? totals.totalMinor;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The sale total must be greater than zero.'),
        ),
      );
      return;
    }
    if (_serviceChargeMinor > 0 &&
        (resumedSalesOrder != null ||
            _paymentMethod == 'credit_note' ||
            _paymentMethod == 'gift_card')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Service charges require a standard POS payment and cannot be added to a sales-order fulfillment.',
          ),
        ),
      );
      return;
    }
    if (_cashRoundingMinor != 0 &&
        (resumedSalesOrder != null || _paymentMethod != 'cash')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash rounding is available only for cash sales.'),
        ),
      );
      return;
    }
    if (resumedSalesOrder != null &&
        items.any((item) => item.product.trackingMode != 'none')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Serialized sales-order fulfillment is not available until unit selection is added to order fulfillment.',
          ),
        ),
      );
      return;
    }
    final paymentLines = [
      PosPaymentLine(method: _paymentMethod, amountMinor: total),
    ];
    var cashChangeMinor = 0;
    if (_paymentMethod == 'cash') {
      final cashResult = await showDialog<_CashPaymentResult>(
        context: context,
        builder: (context) => _CashPaymentDialog(
          currencyCode: workspace.currencyCode,
          cashDueMinor: total,
        ),
      );
      if (cashResult == null || !mounted) return;
      cashChangeMinor = cashResult.changeMinor;
    }
    if (_paymentMethod != 'razorpay' &&
        paymentLines.any((line) => line.method == 'razorpay')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Razorpay Checkout must be used as the sole payment method for a sale.',
          ),
        ),
      );
      return;
    }
    final customerCreditMinor = paymentLines
        .where((line) => line.method == 'customer_credit')
        .fold(0, (sum, line) => sum + line.amountMinor);
    if (customerCreditMinor > 0) {
      if (_customerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a customer before using customer credit.'),
          ),
        );
        return;
      }
      final customer = customers.firstWhere((item) => item.id == _customerId);
      if (customer.creditLimitMinor <= 0 ||
          customerCreditMinor > customer.creditLimitMinor) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This sale exceeds the customer credit limit.'),
          ),
        );
        return;
      }
    }
    if (resumedSalesOrder != null && _paymentMethod == 'credit_note') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Credit-note redemption is not supported for sales-order fulfillment.',
          ),
        ),
      );
      return;
    }
    if (resumedSalesOrder != null && _paymentMethod == 'gift_card') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gift-card redemption is not supported for sales-order fulfillment.',
          ),
        ),
      );
      return;
    }
    if (_paymentMethod == 'credit_note' && _creditNoteNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the credit note number.')),
      );
      return;
    }
    if (_paymentMethod == 'gift_card' && _giftCardNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the gift-card number.')),
      );
      return;
    }
    _UpiPaymentConfirmation? upiConfirmation;
    if (_paymentMethod == 'upi') {
      upiConfirmation = await _showElectronicPaymentDialog(
        currencyCode: workspace.currencyCode,
        amountMinor: total,
        gatewayName: 'UPI',
      );
      if (upiConfirmation == null || !mounted) return;
    }
    final resumedHeldCartId = _resumedHeldCartId;
    final resumedDraftId = _resumedDraftId;
    final resumedQuoteId = _resumedQuoteId;
    Object? savedCartCleanupError;
    Object? quoteConversionError;
    Object? upiConfirmationError;
    setState(() => _checkingOut = true);
    try {
      final repository = ref.read(catalogRepositoryProvider);
      final rawResult = resumedSalesOrder == null
          ? await repository.completeSale(
              businessId: workspace.businessId,
              branchId: warehouse.branchId,
              warehouseId: warehouse.id,
              items: items,
              paymentMethod: _paymentMethod,
              paymentLines: _paymentMethod == 'credit_note'
                  ? null
                  : paymentLines,
              creditNoteNumber: _paymentMethod == 'credit_note'
                  ? _creditNoteNumber
                  : null,
              giftCardNumber: _paymentMethod == 'gift_card'
                  ? _giftCardNumber
                  : null,
              customerId: _customerId,
              registerId: shift?.registerId,
              shiftId: shift?.id,
              couponCode: _couponCode.isEmpty ? null : _couponCode,
              orderDiscountMinor: _orderDiscountMinor,
              serviceChargeMinor: _serviceChargeMinor,
              roundingMinor: _cashRoundingMinor,
              priceOverrideByVariant: Map<String, int>.from(
                _cartPriceOverrides,
              ),
              noteByVariant: _cartNotes,
              serializedUnitIdsByVariant: serializedUnitIdsByVariant,
            )
          : await repository.fulfillSalesOrder(
              salesOrderId: resumedSalesOrder.id,
              paymentLines: paymentLines,
              totalMinor: total,
              registerId: shift?.registerId,
              shiftId: shift?.id,
            );
      var result = Map<String, dynamic>.from(rawResult);
      if (resumedSalesOrder == null) {
        await _rememberRecentlySold(
          workspace.businessId,
          items.map((item) => item.product.variantId),
        );
      }
      if (_paymentMethod == 'razorpay') {
        final paymentId = await repository.findPendingUpiPaymentId(
          result['sale_id'] as String,
        );
        final checkoutResult = await _runRazorpayCheckout(
          repository: repository,
          paymentId: paymentId,
          amountMinor: total,
          currencyCode: workspace.currencyCode,
          invoiceNumber:
              result['invoice_number']?.toString() ??
              result['sale_id'].toString(),
        );
        if (!checkoutResult.isSuccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  checkoutResult.errorMessage ?? 'Razorpay Checkout was cancelled. The sale remains pending.',
                ),
              ),
            );
          }
          return;
        }
        result = {...result, 'payment_status': 'paid'};
      }
      if (_paymentMethod == 'upi' && upiConfirmation != null) {
        try {
          final paymentId = await repository.findPendingUpiPaymentId(
            result['sale_id'] as String,
          );
          await repository.confirmUpiPayment(
            paymentId: paymentId,
            operationId: createUuidV4(),
            status: upiConfirmation.status,
            reference: upiConfirmation.reference,
            note: upiConfirmation.status == 'settled'
                ? 'UPI payment confirmed as successful during POS checkout.'
                : 'UPI payment confirmed as failed during POS checkout.',
          );
          result = {
            ...result,
            'payment_status': upiConfirmation.status == 'settled'
                ? 'paid'
                : 'unpaid',
          };
        } catch (error) {
          // The sale remains safely pending if confirmation cannot be recorded.
          upiConfirmationError = error;
        }
      }
      if (resumedHeldCartId != null) {
        try {
          await ref
              .read(catalogRepositoryProvider)
              .discardHeldPosCart(resumedHeldCartId);
        } catch (error) {
          savedCartCleanupError = error;
        }
      }
      if (resumedDraftId != null) {
        try {
          await ref
              .read(catalogRepositoryProvider)
              .deletePosDraft(resumedDraftId);
        } catch (error) {
          savedCartCleanupError = error;
        }
      }
      if (resumedQuoteId != null) {
        try {
          await ref
              .read(catalogRepositoryProvider)
              .convertSalesQuote(resumedQuoteId, result['sale_id'] as String);
        } catch (error) {
          quoteConversionError = error;
        }
      }
      _cart.clear();
      _cartNotes.clear();
      _orderDiscountMinor = 0;
      _serviceChargeMinor = 0;
      _cashRoundingMinor = 0;
      _couponCode = '';
      _cartPriceOverrides.clear();
      _creditNoteNumber = '';
      _giftCardNumber = '';
      _resumedHeldCartId = null;
      _resumedHeldCartLabel = null;
      _resumedDraftId = null;
      _resumedDraftTitle = null;
      _resumedQuoteId = null;
      _resumedQuoteTitle = null;
      _resumedQuoteValidUntil = null;
      _resumedSalesOrder = null;
      _salesOrderDirty = false;
      ref.invalidate(catalogSnapshotProvider);
      ref.invalidate(heldPosCartsProvider);
      ref.invalidate(posDraftsProvider);
      ref.invalidate(salesQuotesProvider);
      ref.invalidate(salesOrdersProvider);
      ref.invalidate(salesProvider);
      ref.invalidate(filteredSalesProvider);
      if (!mounted) return;
      final viewReceipt = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, size: 48),
          title: const Text('Sale completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(result['invoice_number']?.toString() ?? ''),
              const SizedBox(height: 8),
              Text(
                formatMoney(workspace.currencyCode, total),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                upiConfirmationError != null
                    ? 'UPI sale recorded as pending; confirmation could not be saved'
                    : _paymentMethod == 'upi' &&
                          upiConfirmation?.status == 'failed'
                    ? 'UPI payment marked failed; payment was not received'
                    : result['payment_status'] == 'paid'
                    ? 'Payment settled'
                    : customerCreditMinor > 0
                    ? 'Added to the customer credit statement'
                    : 'Payment recorded as pending until provider settlement',
                textAlign: TextAlign.center,
              ),
              if (cashChangeMinor > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Change ${formatMoney(workspace.currencyCode, cashChangeMinor)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ],
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View receipt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('New sale'),
            ),
          ],
        ),
      );
      if (viewReceipt == true && mounted) {
        await showReceiptDialog(
          context: context,
          ref: ref,
          businessId: workspace.businessId,
          saleId: result['sale_id'] as String,
        );
      }
      if (savedCartCleanupError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The sale completed, but its saved copy could not be removed. You can delete it from Held sales or Drafts.',
            ),
          ),
        );
      }
      if (quoteConversionError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The sale completed, but the quotation could not be marked as converted. It remains available under Quotations.',
            ),
          ),
        );
      }
      if (upiConfirmationError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The sale completed, but the UPI result could not be recorded. It remains pending for reconciliation.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  static String _recentProductsKey(String businessId) =>
      'pos_recently_sold_products_$businessId';

  Future<void> _rememberRecentlySold(
    String businessId,
    Iterable<String> variantIds,
  ) async {
    final preferences = ref.read(sharedPreferencesProvider);
    final existing =
        preferences.getStringList(_recentProductsKey(businessId)) ??
        const <String>[];
    final ordered = <String>[];
    for (final id in [...variantIds, ...existing]) {
      if (id.isNotEmpty && !ordered.contains(id)) ordered.add(id);
      if (ordered.length == 16) break;
    }
    await preferences.setStringList(_recentProductsKey(businessId), ordered);
  }

  Future<void> _applyCoupon(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
    WarehouseOption warehouse,
  ) async {
    if (_cart.isEmpty) return;
    if (_cartPriceOverrides.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove price overrides before applying a coupon.'),
        ),
      );
      return;
    }
    final controller = TextEditingController(text: _couponCode);
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply coupon'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Coupon code',
            hintText: 'WELCOME10',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Check coupon'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    final items = _cart.entries
        .map(
          (entry) => (
            product: data.products.firstWhere(
              (product) => product.variantId == entry.key,
            ),
            quantity: entry.value,
          ),
        )
        .toList(growable: false);
    final subtotal = calculatePosTotals(items).subtotalMinor;
    try {
      final preview = await ref
          .read(promotionRepositoryProvider)
          .previewCoupon(
            businessId: workspace.businessId,
            branchId: warehouse.branchId,
            code: code,
            subtotalMinor: subtotal,
          );
      if (!mounted) return;
      setState(() {
        _couponCode = preview.code;
        _orderDiscountMinor = preview.discountMinor;
        if (_resumedSalesOrder != null) _salesOrderDirty = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${preview.name}: ${formatMoney(workspace.currencyCode, preview.discountMinor)} off applied.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not apply coupon: $error')),
        );
      }
    }
  }

  Future<void> _editDiscount(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
  ) async {
    if (_cart.isEmpty) return;
    final items = _cart.entries
        .map(
          (entry) => (
            product: data.products
                .firstWhere((product) => product.variantId == entry.key)
                .copyWith(priceMinor: _cartPriceOverrides[entry.key]),
            quantity: entry.value,
          ),
        )
        .toList(growable: false);
    final subtotal = calculatePosTotals(items).subtotalMinor;
    final controller = TextEditingController();
    var percentageMode = true;
    final discount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Order discount'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Percentage')),
                    ButtonSegment(value: false, label: Text('Fixed amount')),
                  ],
                  selected: {percentageMode},
                  onSelectionChanged: (selection) => setDialogState(() {
                    percentageMode = selection.first;
                    controller.clear();
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: percentageMode
                        ? 'Discount percentage'
                        : 'Discount amount',
                    suffixText: percentageMode ? '%' : workspace.currencyCode,
                    helperText:
                        'Maximum ${formatMoney(workspace.currencyCode, subtotal)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim();
                final calculated = percentageMode
                    ? _percentageDiscountFromText(subtotal, raw)
                    : parseMoneyToMinor(raw);
                if (calculated == null ||
                    calculated <= 0 ||
                    calculated > subtotal) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Enter a valid discount.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, calculated);
              },
              child: const Text('Apply discount'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (discount != null && mounted) {
      setState(() {
        _orderDiscountMinor = discount;
        _couponCode = '';
        if (_resumedSalesOrder != null) _salesOrderDirty = true;
      });
    }
  }

  Future<void> _editServiceCharge(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
  ) async {
    if (_cart.isEmpty || _resumedSalesOrder != null) return;
    final controller = TextEditingController(
      text: _serviceChargeMinor > 0
          ? (_serviceChargeMinor / 100).toStringAsFixed(2)
          : '',
    );
    final charge = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Service charge'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Service charge amount',
              suffixText: workspace.currencyCode,
              helperText: 'This amount is added to the sale total.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = parseMoneyToMinor(controller.text.trim());
              if (parsed == null || parsed <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid service charge.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Apply charge'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (charge != null && mounted) {
      setState(() => _serviceChargeMinor = charge);
    }
  }

  Future<void> _editCashRounding(
    BusinessWorkspace workspace,
    CatalogSnapshot data,
  ) async {
    if (_cart.isEmpty || _resumedSalesOrder != null) return;
    final items = _cart.entries
        .map(
          (entry) => (
            product: data.products
                .firstWhere((product) => product.variantId == entry.key)
                .copyWith(priceMinor: _cartPriceOverrides[entry.key]),
            quantity: entry.value,
          ),
        )
        .toList(growable: false);
    final baseTotals = calculatePosTotals(
      items,
      orderDiscountMinor: _orderDiscountMinor,
      serviceChargeMinor: _serviceChargeMinor,
    );
    final increment = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cash rounding'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose the cash denomination to round the total to. The adjustment is recorded on the sale.',
              ),
              const SizedBox(height: 16),
              for (final option in const [1, 5, 10])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Nearest ${formatMoney(workspace.currencyCode, option)}',
                  ),
                  subtitle: Text(
                    'Adjustment ${formatMoney(workspace.currencyCode, cashRoundingMinor(baseTotals.totalMinor, option))}',
                  ),
                  onTap: () => Navigator.pop(dialogContext, option),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (increment != null && mounted) {
      setState(() {
        _cashRoundingMinor = cashRoundingMinor(
          baseTotals.totalMinor,
          increment,
        );
      });
    }
  }

  Future<void> _editPriceOverride(
    CatalogProduct product,
    BusinessWorkspace workspace,
  ) async {
    if (_resumedSalesOrder != null) return;
    final current = _cartPriceOverrides[product.variantId];
    final controller = TextEditingController(
      text: current == null ? '' : (current / 100).toStringAsFixed(2),
    );
    final value = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Override price · ${product.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Unit price',
            prefixText: '${workspace.currencyCode} ',
            helperText: 'Leave unchanged to keep the catalog price.',
          ),
          onSubmitted: (_) {
            final parsed = parseMoneyToMinor(controller.text.trim());
            if (parsed == null || parsed < 0) return;
            Navigator.pop(dialogContext, parsed);
          },
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, -1),
              child: const Text('Remove override'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = parseMoneyToMinor(controller.text.trim());
              if (parsed == null || parsed < 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid non-negative price.'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Save price'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null) return;
    setState(() {
      if (value < 0) {
        _cartPriceOverrides.remove(product.variantId);
      } else {
        _cartPriceOverrides[product.variantId] = value;
      }
      _couponCode = '';
      _orderDiscountMinor = 0;
      if (_resumedSalesOrder != null) _salesOrderDirty = true;
    });
  }
}

class _CatalogPane extends StatelessWidget {
  const _CatalogPane({
    required this.products,
    required this.categories,
    required this.selectedCategoryId,
    required this.favoritesOnly,
    required this.hasFavorites,
    required this.recentOnly,
    required this.hasRecentProducts,
    required this.data,
    required this.warehouseId,
    required this.currencyCode,
    required this.canCreateCustomItem,
    required this.searchController,
    required this.searchFocusNode,
    required this.queryChanged,
    required this.submitSearch,
    required this.focusSearch,
    required this.scanBarcode,
    required this.categoryChanged,
    required this.favoritesChanged,
    required this.recentChanged,
    required this.addProduct,
    required this.createCustomItem,
  });

  final List<CatalogProduct> products;
  final List<CatalogOption> categories;
  final String? selectedCategoryId;
  final bool favoritesOnly;
  final bool hasFavorites;
  final bool recentOnly;
  final bool hasRecentProducts;
  final CatalogSnapshot data;
  final String warehouseId;
  final String currencyCode;
  final bool canCreateCustomItem;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> queryChanged;
  final ValueChanged<String> submitSearch;
  final VoidCallback focusSearch;
  final VoidCallback scanBarcode;
  final ValueChanged<String?> categoryChanged;
  final ValueChanged<bool> favoritesChanged;
  final ValueChanged<bool> recentChanged;
  final ValueChanged<CatalogProduct> addProduct;
  final VoidCallback createCustomItem;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Point of sale',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  autofocus: true,
                  // Barcode scanners submit an Enter key after each code.
                  // Override Flutter's default editing completion behavior so
                  // that Enter does not unfocus this field between scans.
                  onEditingComplete: () {},
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onChanged: queryChanged,
                  onSubmitted: submitSearch,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    labelText: 'Search products, SKU, or barcode',
                    helperText: 'Scan a barcode and press Enter · scanner stays focused',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Scan with camera',
                          onPressed: scanBarcode,
                          icon: const Icon(Icons.photo_camera_rounded),
                        ),
                        IconButton(
                          tooltip: 'Focus barcode scanner input (F2)',
                          onPressed: focusSearch,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canCreateCustomItem) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: createCustomItem,
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Add custom item'),
                    ),
                  ),
                ],
                if (categories.isNotEmpty ||
                    hasFavorites ||
                    hasRecentProducts) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          categories.length +
                          1 +
                          (hasFavorites ? 1 : 0) +
                          (hasRecentProducts ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ChoiceChip(
                            selected:
                                selectedCategoryId == null &&
                                !favoritesOnly &&
                                !recentOnly,
                            onSelected: (_) => categoryChanged(null),
                            avatar: const Icon(Icons.apps_rounded, size: 18),
                            label: const Text('All'),
                          );
                        }
                        final recentIndex = 1;
                        if (hasRecentProducts && index == recentIndex) {
                          return ChoiceChip(
                            selected: recentOnly,
                            onSelected: (_) => recentChanged(true),
                            avatar: const Icon(Icons.history_rounded, size: 18),
                            label: const Text('Recently sold'),
                          );
                        }
                        final favoritesIndex = 1 + (hasRecentProducts ? 1 : 0);
                        if (hasFavorites && index == favoritesIndex) {
                          return ChoiceChip(
                            selected: favoritesOnly,
                            onSelected: (_) => favoritesChanged(true),
                            avatar: const Icon(Icons.star_rounded, size: 18),
                            label: const Text('Favorites'),
                          );
                        }
                        final categoryIndex =
                            index -
                            1 -
                            (hasRecentProducts ? 1 : 0) -
                            (hasFavorites ? 1 : 0);
                        final category = categories[categoryIndex];
                        return ChoiceChip(
                          selected:
                              !favoritesOnly &&
                              !recentOnly &&
                              selectedCategoryId == category.id,
                          onSelected: (_) => categoryChanged(category.id),
                          label: Text(category.name),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: favoritesOnly
                  ? Icons.star_border_rounded
                  : recentOnly
                  ? Icons.history_toggle_off_rounded
                  : Icons.search_off_rounded,
              title: favoritesOnly
                  ? 'No favorite products found'
                  : recentOnly
                  ? 'No recently sold products'
                  : 'No products found',
              message: favoritesOnly
                  ? 'Mark products as favorites or try a different search.'
                  : recentOnly
                  ? 'Completed sales will appear here after the first checkout.'
                  : 'Add a product or try a different search.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 900
                    ? 4
                    : constraints.crossAxisExtent >= 620
                    ? 3
                    : 2;
                return SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    // Keep every catalog card the same height while giving
                    // the image a larger, predictable presentation area.
                    mainAxisExtent: 312,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final stock = data.stockForWarehouse(
                      product.variantId,
                      warehouseId,
                    );
                    final outOfStock = product.trackInventory && stock < 1;
                    final available = !outOfStock;
                    final statusColor = outOfStock
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary;
                    final panel = AppPanel(
                      onTap: available ? () => addProduct(product) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Use one aspect-ratio frame for every product, but
                          // keep the source fully visible. Cover was cropping
                          // bottle tops and labels on portrait uploads.
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ProductImage(
                              imagePath: product.imagePath,
                              borderRadius: 10,
                              fit: BoxFit.contain,
                              iconSize: 42,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              if (product.isFavorite) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.star_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.sku,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              if (product.trackInventory)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        outOfStock
                                            ? Icons.block_outlined
                                            : Icons.check_circle_outline,
                                        size: 14,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        outOfStock
                                            ? 'Out of stock'
                                            : 'In stock',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: statusColor),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                product.taxInclusive
                                    ? '${formatMoney(currencyCode, product.priceMinor)} incl. tax'
                                    : formatMoney(
                                        currencyCode,
                                        product.priceMinor,
                                      ),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                product.trackInventory
                                    ? (outOfStock ? 'Out of stock' : 'In stock')
                                    : 'Service',
                                style: TextStyle(
                                  color: outOfStock
                                      ? statusColor
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                    if (!outOfStock) return panel;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: panel,
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _BarcodeScannerDialog extends StatefulWidget {
  const _BarcodeScannerDialog({required this.onDetected});

  final ValueChanged<String> onDetected;

  @override
  State<_BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<_BarcodeScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    // Start explicitly after the preview has been attached. This avoids the
    // controller-start race that can otherwise happen when MobileScanner is
    // created inside a modal dialog, especially on Flutter web.
    autoStart: false,
    // Decode every available frame instead of waiting for the default 250 ms
    // normal-speed throttle. The platform reader still caps web polling at
    // the browser's animation rate, while native scanners process frames as
    // soon as they arrive.
    cameraResolution: const Size(960, 540),
    detectionSpeed: DetectionSpeed.unrestricted,
    facing: CameraFacing.back,
    // An empty list tells mobile_scanner to enable every format supported by
    // the active native or web decoder, including retail, 2D, and GS1 codes.
    formats: const <BarcodeFormat>[],
    autoZoom: true,
  );
  String? _lastDetectedValue;
  DateTime? _lastDetectedAt;
  int _scanCount = 0;
  bool _starting = false;
  String? _cameraError;
  CameraFacing _requestedFacing = CameraFacing.back;
  List<BarcodeCameraDevice> _cameraDevices = const [];
  String? _selectedCameraId;
  bool _loadingCameras = false;
  Timer? _decoderFallbackTimer;
  bool _decoderFallbackAttempted = false;
  String _decoderLabel = 'Native detector / ZXing WASM';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Use the browser's native BarcodeDetector when available because it is
      // substantially faster than decoding every frame through WebAssembly.
      // mobile_scanner automatically falls back to ZXing WASM on browsers
      // without native detector support. This is scanner acceleration only;
      // it does not add an offline queue or local transaction path.
      MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.auto);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCamera());
  }

  @override
  void dispose() {
    _decoderFallbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) {
    final value = capture.barcodes
        // Some browser/native decoders expose the decoded text as
        // displayValue while rawValue is null. Accept either representation
        // so EAN/UPC/QR scans are handled consistently across platforms.
        .map((barcode) => (barcode.rawValue ?? barcode.displayValue)?.trim())
        .whereType<String>()
        .firstWhere((rawValue) => rawValue.isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;
    final now = DateTime.now();
    final duplicate =
        value == _lastDetectedValue &&
        _lastDetectedAt != null &&
        now.difference(_lastDetectedAt!) < const Duration(milliseconds: 700);
    if (duplicate) return;
    _lastDetectedValue = value;
    _lastDetectedAt = now;
    _scanCount++;
    _decoderFallbackTimer?.cancel();
    widget.onDetected(value);
    if (mounted) setState(() {});
  }

  Future<void> _startCamera() async {
    if (!mounted || _starting || _controller.value.isRunning) return;
    setState(() {
      _starting = true;
      _cameraError = null;
    });
    try {
      // Pick the first available video input before starting the stream. This
      // prevents the selector from opening on an empty "Camera" placeholder;
      // the browser/native plugin still honours the device's preferred camera
      // when one was saved previously.
      if (kIsWeb && _selectedCameraId == null) {
        final devices = await listBarcodeCameraDevices();
        if (devices.isNotEmpty) {
          final defaultDevice = devices.first;
          _selectedCameraId = defaultDevice.id;
          await selectBarcodeCameraDevice(defaultDevice.id);
        }
      }
      await _controller.start(cameraDirection: _requestedFacing);
      await _loadCameraDevices();
      _scheduleDecoderFallback();
    } catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraErrorText(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _loadCameraDevices() async {
    if (!mounted) return;
    setState(() => _loadingCameras = true);
    try {
      final devices = await listBarcodeCameraDevices();
      if (!mounted) return;
      setState(() {
        _cameraDevices = devices;
        if (_selectedCameraId != null &&
            !devices.any((device) => device.id == _selectedCameraId)) {
          _selectedCameraId = null;
        }
        _selectedCameraId ??= devices.firstOrNull?.id;
      });
    } finally {
      if (mounted) setState(() => _loadingCameras = false);
    }
  }

  Future<void> _selectCamera(String deviceId) async {
    final normalized = deviceId.trim();
    if (normalized.isEmpty || _starting) return;
    setState(() {
      _selectedCameraId = normalized;
      _cameraError = null;
    });
    try {
      await selectBarcodeCameraDevice(normalized);
      await _restartCamera();
    } catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraErrorText(error));
    }
  }

  Future<void> _restartCamera() async {
    try {
      await _controller.stop();
    } catch (_) {
      // A stop before initialization is harmless; start() below will request
      // permission and initialize the camera again.
    }
    await _startCamera();
  }

  Future<void> _switchCamera() async {
    if (_starting || !_controller.value.isInitialized) return;
    final desktopCamera =
        kIsWeb &&
        (_controller.value.cameraDirection == CameraFacing.unknown ||
            _controller.value.cameraDirection == CameraFacing.external);
    if (desktopCamera && _cameraDevices.length > 1) {
      final currentIndex = _cameraDevices.indexWhere(
        (device) => device.id == _selectedCameraId,
      );
      final nextIndex = (currentIndex + 1) % _cameraDevices.length;
      await _selectCamera(_cameraDevices[nextIndex].id);
      return;
    }
    final nextFacing = _requestedFacing == CameraFacing.back
        ? CameraFacing.front
        : CameraFacing.back;
    setState(() {
      _starting = true;
      _cameraError = null;
      _requestedFacing = nextFacing;
    });
    try {
      await _controller.stop();
      // Explicitly restart with the requested direction. This works on web
      // browsers that report an unknown/external camera direction, where the
      // plugin's convenience switchCamera() intentionally does nothing.
      await _controller.start(cameraDirection: _requestedFacing);
      await _loadCameraDevices();
      _scheduleDecoderFallback();
    } catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraErrorText(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _scheduleDecoderFallback() {
    if (!kIsWeb || _decoderFallbackAttempted) return;
    _decoderFallbackTimer?.cancel();
    _decoderFallbackTimer = Timer(
      const Duration(seconds: 2),
      _tryCompatibilityDecoder,
    );
  }

  Future<void> _tryCompatibilityDecoder() async {
    if (!mounted || _scanCount > 0 || !kIsWeb || _decoderFallbackAttempted) {
      return;
    }
    _decoderFallbackAttempted = true;
    setState(() {
      _starting = true;
      _cameraError = null;
      _decoderLabel = 'Rotation-capable ZXing WASM';
    });
    try {
      await _controller.stop();
      MobileScannerPlatform.instance.setWebBarcodeReader(
        // ZXing WASM enables tryHarder + tryRotate in mobile_scanner, so
        // labels held vertically, diagonally, or upside down remain readable.
        WebBarcodeReader.zxingWasm,
      );
      await _controller.start(cameraDirection: _requestedFacing);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = _cameraErrorText(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _handleDetectError(Object error, StackTrace stackTrace) {
    // A barcode-decoder miss is expected while the camera is pointed away
    // from a code. Only surface camera/permission failures to the user.
    if (error is MobileScannerBarcodeException) return;
    if (!mounted) return;
    setState(() => _cameraError = _cameraErrorText(error));
  }

  String _cameraErrorText(Object error) {
    if (error is MobileScannerException) {
      return switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied => 'Camera permission was denied. Allow camera access in the browser or device settings, then tap Retry.',
        MobileScannerErrorCode.unsupported =>
          'This device does not provide a supported camera.',
        _ =>
          error.errorDetails?.message?.trim().isNotEmpty == true
              ? error.errorDetails!.message!.trim()
              : error.errorCode.message,
      };
    }
    return 'Could not start the camera. Check camera permissions and tap Retry.';
  }

  bool get _correctDesktopMirror {
    if (!kIsWeb) return false;
    final direction = _controller.value.cameraDirection;
    // Some desktop browsers do not expose facingMode and mirror the preview.
    // Correct only that unknown/external case; the normal rear camera preview
    // must stay unmirrored for barcode aiming.
    return direction == CameraFacing.unknown ||
        direction == CameraFacing.external;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width - 32;
    final previewWidth = maxWidth.clamp(280.0, 560.0).toDouble();
    return AlertDialog(
      title: const Text('Scan barcode or QR code'),
      content: SizedBox(
        width: previewWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.25,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform(
                      alignment: Alignment.center,
                      transform: _correctDesktopMirror
                          ? Matrix4.diagonal3Values(-1, 1, 1)
                          : Matrix4.identity(),
                      child: MobileScanner(
                        controller: _controller,
                        onDetect: _handleCapture,
                        onDetectError: _handleDetectError,
                        fit: BoxFit.cover,
                        tapToFocus: true,
                        placeholderBuilder: (_) => const ColoredBox(
                          color: Colors.black,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorBuilder: (context, error) => const ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Icon(
                              Icons.no_photography_outlined,
                              color: Colors.white70,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    if (_starting)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_cameraDevices.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue:
                    _cameraDevices.any(
                      (device) => device.id == _selectedCameraId,
                    )
                    ? _selectedCameraId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Camera',
                  prefixIcon: Icon(Icons.videocam_outlined),
                  helperText: 'Laptop, mobile, USB, and external webcams are supported.',
                ),
                items: [
                  for (final device in _cameraDevices)
                    DropdownMenuItem(
                      value: device.id,
                      child: Text(
                        device.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _starting
                    ? null
                    : (deviceId) {
                        if (deviceId != null) {
                          unawaited(_selectCamera(deviceId));
                        }
                      },
              ),
              const SizedBox(height: 12),
            ],
            if (kIsWeb && _cameraDevices.isEmpty && !_loadingCameras)
              Text(
                'No camera list was returned. Allow camera access, connect the webcam, and tap Refresh cameras.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            if (_loadingCameras)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Text(
              _cameraError ??
                  'Hold the barcode at any angle. Scanning stays open until you press Cancel. $_decoderLabel is active.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (_lastDetectedValue != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last scanned: $_lastDetectedValue · $_scanCount total',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (kIsWeb)
          TextButton.icon(
            onPressed: _starting || _loadingCameras ? null : _loadCameraDevices,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh cameras'),
          ),
        if (_cameraError != null)
          TextButton.icon(
            onPressed: _starting ? null : _restartCamera,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry camera'),
          ),
        if (_cameraError == null)
          TextButton.icon(
            onPressed: _starting ? null : _switchCamera,
            icon: const Icon(Icons.flip_camera_android_rounded),
            label: const Text('Flip camera'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _HeldCartAction {
  const _HeldCartAction({required this.cart, required this.discard});

  final HeldPosCart cart;
  final bool discard;
}

class _DraftAction {
  const _DraftAction({required this.draft, required this.delete});

  final PosDraft draft;
  final bool delete;
}

class _QuoteAction {
  const _QuoteAction({required this.quote, required this.cancel});

  final SalesQuote quote;
  final bool cancel;
}

class _QuoteDetails {
  const _QuoteDetails({required this.title, required this.validUntil});

  final String title;
  final DateTime validUntil;
}

class _SalesQuoteDialog extends StatefulWidget {
  const _SalesQuoteDialog({
    required this.initialTitle,
    required this.initialValidUntil,
    required this.updating,
  });

  final String initialTitle;
  final DateTime initialValidUntil;
  final bool updating;

  @override
  State<_SalesQuoteDialog> createState() => _SalesQuoteDialogState();
}

class _SalesQuoteDialogState extends State<_SalesQuoteDialog> {
  late final TextEditingController _titleController;
  late DateTime _validUntil;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _validUntil = widget.initialValidUntil;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.request_quote_outlined),
      title: Text(widget.updating ? 'Update quotation' : 'Create quotation'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Quotation title',
                hintText: 'Customer or opportunity name',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Valid through'),
              subtitle: Text(DateFormat.yMMMMd().format(_validUntil)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 6),
            const Text(
              'This saves prices and taxes as a non-posting estimate. No stock or payment is recorded.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.updating ? 'Update quotation' : 'Save quotation'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _validUntil.isBefore(today) ? today : _validUntil,
      firstDate: today,
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() => _validUntil = selected);
    }
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a quotation title.')));
      return;
    }
    Navigator.pop(
      context,
      _QuoteDetails(title: title, validUntil: _validUntil),
    );
  }
}

class _SalesOrderAction {
  const _SalesOrderAction({required this.order, required this.cancel});

  final SalesOrder order;
  final bool cancel;
}

class _SalesOrderDetails {
  const _SalesOrderDetails({required this.title, required this.deliveryOn});

  final String title;
  final DateTime deliveryOn;
}

class _SalesOrderDialog extends StatefulWidget {
  const _SalesOrderDialog({
    required this.initialTitle,
    required this.initialDeliveryOn,
    required this.updating,
  });

  final String initialTitle;
  final DateTime initialDeliveryOn;
  final bool updating;

  @override
  State<_SalesOrderDialog> createState() => _SalesOrderDialogState();
}

class _SalesOrderDialogState extends State<_SalesOrderDialog> {
  late final TextEditingController _titleController;
  late DateTime _deliveryOn;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _deliveryOn = widget.initialDeliveryOn;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.inventory_2_outlined),
      title: Text(
        widget.updating ? 'Update sales order' : 'Create sales order',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Sales order title',
                hintText: 'Customer or delivery reference',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Requested delivery'),
              subtitle: Text(DateFormat.yMMMMd().format(_deliveryOn)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 6),
            const Text(
              'Stock items are reserved immediately. Stock moves only when the order is fulfilled as a sale.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.updating ? 'Update order' : 'Save order'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _deliveryOn.isBefore(today) ? today : _deliveryOn,
      firstDate: today,
      lastDate: DateTime(today.year + 5, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() => _deliveryOn = selected);
    }
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a sales order title.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _SalesOrderDetails(title: title, deliveryOn: _deliveryOn),
    );
  }
}

class _CartPane extends StatelessWidget {
  const _CartPane({
    required this.workspace,
    required this.data,
    required this.cart,
    required this.cartNotes,
    required this.openShifts,
    required this.shiftId,
    required this.canManageRegisters,
    required this.openShift,
    required this.customers,
    required this.customerId,
    required this.paymentMethod,
    required this.orderDiscountMinor,
    required this.serviceChargeMinor,
    required this.roundingMinor,
    required this.canDiscount,
    required this.canServiceCharge,
    required this.canCashRounding,
    required this.canPriceOverride,
    required this.cartPriceOverrides,
    required this.checkingOut,
    required this.holdingCart,
    required this.savingDraft,
    required this.savingQuote,
    required this.savingOrder,
    required this.heldCartCount,
    required this.draftCount,
    required this.quoteCount,
    required this.salesOrderCount,
    required this.resumedHeldCartLabel,
    required this.resumedDraftTitle,
    required this.resumedQuoteTitle,
    required this.resumedSalesOrder,
    required this.salesOrderDirty,
    required this.showShortcuts,
    required this.paymentChanged,
    required this.customerChanged,
    required this.increment,
    required this.decrement,
    required this.editItemNote,
    required this.editPriceOverride,
    required this.editDiscount,
    required this.editServiceCharge,
    required this.editCashRounding,
    required this.couponCode,
    required this.applyCoupon,
    required this.removeCoupon,
    required this.removeDiscount,
    required this.removeServiceCharge,
    required this.removeCashRounding,
    required this.holdCart,
    required this.showHeldCarts,
    required this.saveDraft,
    required this.showDrafts,
    required this.saveQuote,
    required this.showQuotes,
    required this.saveSalesOrder,
    required this.showSalesOrders,
    required this.cancelSale,
    required this.checkout,
  });

  final BusinessWorkspace workspace;
  final CatalogSnapshot data;
  final Map<String, int> cart;
  final Map<String, String> cartNotes;
  final List<RegisterShift> openShifts;
  final String? shiftId;
  final bool canManageRegisters;
  final VoidCallback openShift;
  final List<Customer> customers;
  final String? customerId;
  final String paymentMethod;
  final int orderDiscountMinor;
  final int serviceChargeMinor;
  final int roundingMinor;
  final bool canDiscount;
  final bool canServiceCharge;
  final bool canCashRounding;
  final bool canPriceOverride;
  final Map<String, int> cartPriceOverrides;
  final bool checkingOut;
  final bool holdingCart;
  final bool savingDraft;
  final bool savingQuote;
  final bool savingOrder;
  final int heldCartCount;
  final int draftCount;
  final int quoteCount;
  final int salesOrderCount;
  final String? resumedHeldCartLabel;
  final String? resumedDraftTitle;
  final String? resumedQuoteTitle;
  final SalesOrder? resumedSalesOrder;
  final bool salesOrderDirty;
  final VoidCallback showShortcuts;
  final ValueChanged<String> paymentChanged;
  final ValueChanged<String?> customerChanged;
  final ValueChanged<CatalogProduct> increment;
  final ValueChanged<CatalogProduct> decrement;
  final ValueChanged<CatalogProduct> editItemNote;
  final ValueChanged<CatalogProduct> editPriceOverride;
  final VoidCallback editDiscount;
  final VoidCallback editServiceCharge;
  final VoidCallback editCashRounding;
  final String couponCode;
  final VoidCallback applyCoupon;
  final VoidCallback removeCoupon;
  final VoidCallback removeDiscount;
  final VoidCallback removeServiceCharge;
  final VoidCallback removeCashRounding;
  final VoidCallback holdCart;
  final VoidCallback showHeldCarts;
  final VoidCallback saveDraft;
  final VoidCallback showDrafts;
  final VoidCallback saveQuote;
  final VoidCallback showQuotes;
  final VoidCallback saveSalesOrder;
  final VoidCallback showSalesOrders;
  final VoidCallback cancelSale;
  final VoidCallback checkout;

  @override
  Widget build(BuildContext context) {
    final busy =
        checkingOut || holdingCart || savingDraft || savingQuote || savingOrder;
    final hasPriceOverrides = cartPriceOverrides.isNotEmpty;
    final items = cart.entries
        .map((entry) {
          final product = data.products
              .firstWhere((item) => item.variantId == entry.key)
              .copyWith(priceMinor: cartPriceOverrides[entry.key]);
          return (product: product, quantity: entry.value);
        })
        .toList(growable: false);
    final totals = calculatePosTotals(
      items,
      orderDiscountMinor: orderDiscountMinor,
      serviceChargeMinor: serviceChargeMinor,
      roundingMinor: roundingMinor,
    );
    final committedOrder = salesOrderDirty ? null : resumedSalesOrder;
    final displaySubtotalMinor =
        committedOrder?.subtotalMinor ?? totals.subtotalMinor;
    final displayTaxMinor = committedOrder?.taxTotalMinor ?? totals.taxMinor;
    final displayDiscountMinor =
        committedOrder?.discountTotalMinor ?? totals.orderDiscountMinor;
    final displayServiceChargeMinor = committedOrder == null
        ? totals.serviceChargeMinor
        : 0;
    final displayRoundingMinor = committedOrder == null
        ? totals.roundingMinor
        : 0;
    final displayTotalMinor =
        committedOrder?.grandTotalMinor ?? totals.totalMinor;

    Widget saleTitle() => AppMotionSwitcher(
      motionKey: ValueKey(
        resumedHeldCartLabel ??
            resumedDraftTitle ??
            resumedQuoteTitle ??
            resumedSalesOrder?.id ??
            'current-sale',
      ),
      alignment: Alignment.centerLeft,
      duration: AppMotion.quick,
      child: Text(
        resumedHeldCartLabel != null
            ? 'Resumed · $resumedHeldCartLabel'
            : resumedDraftTitle != null
            ? 'Draft · $resumedDraftTitle'
            : resumedQuoteTitle != null
            ? 'Quote · $resumedQuoteTitle'
            : resumedSalesOrder != null
            ? 'Order${salesOrderDirty ? ' (edited)' : ''} · ${resumedSalesOrder!.title}'
            : 'Current sale',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );

    Widget countAction({
      required int count,
      required String tooltip,
      required VoidCallback? onPressed,
      required IconData icon,
    }) => Badge.count(
      count: count,
      isLabelVisible: count > 0,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );

    final secondaryActionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
    final compactAdjustmentStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
    );
    Widget adjustmentAction({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      VoidCallback? onRemove,
      String? removeTooltip,
    }) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: compactAdjustmentStyle,
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: removeTooltip,
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      );
    }

    final adjustmentActions = <Widget>[];
    if (canDiscount && items.isNotEmpty) {
      adjustmentActions.add(
        adjustmentAction(
          icon: Icons.local_offer_outlined,
          label: couponCode.isEmpty ? 'Coupon' : 'Edit coupon',
          onPressed: checkingOut || hasPriceOverrides ? null : applyCoupon,
          onRemove: couponCode.isEmpty || checkingOut ? null : removeCoupon,
          removeTooltip: 'Remove coupon',
        ),
      );
      adjustmentActions.add(
        adjustmentAction(
          icon: Icons.percent_rounded,
          label: orderDiscountMinor > 0 ? 'Edit discount' : 'Add discount',
          onPressed: checkingOut || couponCode.isNotEmpty ? null : editDiscount,
          onRemove: orderDiscountMinor == 0 || checkingOut
              ? null
              : removeDiscount,
          removeTooltip: 'Remove discount',
        ),
      );
    }
    if (canServiceCharge && items.isNotEmpty) {
      adjustmentActions.add(
        adjustmentAction(
          icon: Icons.room_service_outlined,
          label: serviceChargeMinor > 0 ? 'Edit service' : 'Service charge',
          onPressed: checkingOut ? null : editServiceCharge,
          onRemove: serviceChargeMinor == 0 || checkingOut
              ? null
              : removeServiceCharge,
          removeTooltip: 'Remove service charge',
        ),
      );
    }
    if (canCashRounding && items.isNotEmpty) {
      adjustmentActions.add(
        adjustmentAction(
          icon: Icons.toll_outlined,
          label: roundingMinor == 0 ? 'Round cash' : 'Edit rounding',
          onPressed: checkingOut ? null : editCashRounding,
          onRemove: roundingMinor == 0 || checkingOut
              ? null
              : removeCashRounding,
          removeTooltip: 'Remove cash rounding',
        ),
      );
    }
    final secondaryActions = <Widget>[
      OutlinedButton.icon(
        style: secondaryActionStyle,
        onPressed:
            cart.isEmpty ||
                busy ||
                couponCode.isNotEmpty ||
                hasPriceOverrides ||
                resumedDraftTitle != null ||
                resumedQuoteTitle != null ||
                resumedSalesOrder != null
            ? null
            : holdCart,
        icon: holdingCart
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.pause_rounded),
        label: Text(
          resumedHeldCartLabel == null ? 'Park' : 'Update',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        ),
      ),
      OutlinedButton.icon(
        style: secondaryActionStyle,
        onPressed:
            cart.isEmpty ||
                busy ||
                couponCode.isNotEmpty ||
                hasPriceOverrides ||
                resumedHeldCartLabel != null ||
                resumedQuoteTitle != null ||
                resumedSalesOrder != null
            ? null
            : saveDraft,
        icon: savingDraft
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.description_outlined),
        label: Text(
          resumedDraftTitle == null ? 'Draft' : 'Update',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        ),
      ),
      OutlinedButton.icon(
        style: secondaryActionStyle,
        onPressed:
            cart.isEmpty ||
                busy ||
                couponCode.isNotEmpty ||
                hasPriceOverrides ||
                resumedHeldCartLabel != null ||
                resumedDraftTitle != null ||
                resumedSalesOrder != null
            ? null
            : saveQuote,
        icon: savingQuote
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.request_quote_outlined),
        label: Text(
          resumedQuoteTitle == null ? 'Quote' : 'Update',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        ),
      ),
      OutlinedButton.icon(
        style: secondaryActionStyle,
        onPressed:
            cart.isEmpty ||
                busy ||
                couponCode.isNotEmpty ||
                hasPriceOverrides ||
                resumedHeldCartLabel != null ||
                resumedDraftTitle != null ||
                resumedQuoteTitle != null
            ? null
            : saveSalesOrder,
        icon: savingOrder
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.inventory_2_outlined),
        label: Text(
          resumedSalesOrder == null ? 'Order' : 'Update',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
        ),
      ),
    ];

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final shortcutButton = IconButton(
                      tooltip: 'Keyboard shortcuts (F1)',
                      onPressed: showShortcuts,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                    );
                    final historyButtons = <Widget>[
                      countAction(
                        count: heldCartCount,
                        tooltip: 'Held sales',
                        onPressed: busy ? null : showHeldCarts,
                        icon: Icons.pause_circle_outline_rounded,
                      ),
                      countAction(
                        count: draftCount,
                        tooltip: 'Sales drafts',
                        onPressed: busy ? null : showDrafts,
                        icon: Icons.description_outlined,
                      ),
                      countAction(
                        count: quoteCount,
                        tooltip: 'Quotations',
                        onPressed: busy ? null : showQuotes,
                        icon: Icons.request_quote_outlined,
                      ),
                      countAction(
                        count: salesOrderCount,
                        tooltip: 'Sales orders',
                        onPressed: busy ? null : showSalesOrders,
                        icon: Icons.inventory_2_outlined,
                      ),
                    ];
                    final cancelButton = IconButton(
                      tooltip: 'Cancel current sale',
                      onPressed: cart.isEmpty || busy ? null : cancelSale,
                      icon: const Icon(Icons.remove_shopping_cart_outlined),
                    );

                    if (constraints.maxWidth < 440) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: saleTitle()),
                              cancelButton,
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [shortcutButton, ...historyButtons],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: saleTitle()),
                        shortcutButton,
                        ...historyButtons,
                        cancelButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Cashier shift',
                    helperText: 'Cashiers are assigned automatically; admins can manage any branch shift.',
                    prefixIcon: Icon(Icons.lock_clock_outlined),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          openShifts
                                  .where((shift) => shift.id == shiftId)
                                  .firstOrNull
                                  ?.registerName ??
                              'No open shift assigned',
                        ),
                      ),
                      if (canManageRegisters && openShifts.isEmpty)
                        TextButton.icon(
                          onPressed: openShift,
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Open shift'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                DropdownMenu<String>(
                  key: ValueKey('customer-$customerId'),
                  initialSelection:
                      customers.any((item) => item.id == customerId)
                      ? customerId
                      : '',
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  expandedInsets: EdgeInsets.zero,
                  label: const Text('Customer'),
                  hintText: 'Search name, phone, email, code, or GSTIN',
                  leadingIcon: const Icon(Icons.person_search_outlined),
                  dropdownMenuEntries: [
                    const DropdownMenuEntry<String>(
                      value: '',
                      label: 'Walk-in customer',
                    ),
                    ...customers.map(
                      (customer) => DropdownMenuEntry<String>(
                        value: customer.id,
                        label: [
                          customer.name,
                          if ((customer.phone ?? '').trim().isNotEmpty)
                            customer.phone!.trim(),
                          if ((customer.email ?? '').trim().isNotEmpty)
                            customer.email!.trim(),
                          if ((customer.code ?? '').trim().isNotEmpty)
                            'Code ${customer.code!.trim()}',
                          if ((customer.gstin ?? '').trim().isNotEmpty)
                            'GSTIN ${customer.gstin!.trim()}',
                          if ((customer.groupName ?? '').trim().isNotEmpty)
                            'Group ${customer.groupName!.trim()}',
                        ].join(' • '),
                      ),
                    ),
                  ],
                  onSelected: (value) => customerChanged(
                    value == null || value.isEmpty ? null : value,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  AppMotionSwitcher(
                    motionKey: ValueKey(items.isEmpty),
                    child: items.isEmpty
                        ? const SizedBox(
                            height: 120,
                            child: Center(
                              child: Text('Tap a product to add it'),
                            ),
                          )
                        : Column(
                            children: [
                              for (final item in items)
                                Builder(
                                  builder: (context) {
                                    final orderLine = salesOrderDirty
                                        ? null
                                        : resumedSalesOrder?.items
                                              .where(
                                                (line) =>
                                                    line.variantId ==
                                                    item.product.variantId,
                                              )
                                              .firstOrNull;
                                    return ListTile(
                                      leading: ProductImage(
                                        imagePath: item.product.imagePath,
                                        width: 44,
                                        height: 44,
                                        borderRadius: 8,
                                        iconSize: 20,
                                      ),
                                      title: Text(item.product.name),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            formatMoney(
                                              workspace.currencyCode,
                                              orderLine?.lineTotalMinor ??
                                                  _lineTotal(
                                                    item.product,
                                                    item.quantity,
                                                  ),
                                            ),
                                          ),
                                          if (cartNotes[item.product.variantId]
                                                  ?.isNotEmpty ??
                                              false)
                                            Text(
                                              cartNotes[item
                                                  .product
                                                  .variantId]!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          if (cartPriceOverrides.containsKey(
                                            item.product.variantId,
                                          ))
                                            Text(
                                              'Price override · ${formatMoney(workspace.currencyCode, item.product.priceMinor)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                            ),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip:
                                                cartNotes[item
                                                            .product
                                                            .variantId]
                                                        ?.isNotEmpty ??
                                                    false
                                                ? 'Edit item note'
                                                : 'Add item note',
                                            onPressed:
                                                busy ||
                                                    resumedSalesOrder != null
                                                ? null
                                                : () => editItemNote(
                                                    item.product,
                                                  ),
                                            icon: Icon(
                                              cartNotes[item.product.variantId]
                                                          ?.isNotEmpty ??
                                                      false
                                                  ? Icons.sticky_note_2_rounded
                                                  : Icons.note_add_outlined,
                                            ),
                                          ),
                                          if (canPriceOverride)
                                            IconButton(
                                              tooltip:
                                                  cartPriceOverrides
                                                      .containsKey(
                                                        item.product.variantId,
                                                      )
                                                  ? 'Edit price override'
                                                  : 'Override unit price',
                                              onPressed:
                                                  busy ||
                                                      resumedSalesOrder != null
                                                  ? null
                                                  : () => editPriceOverride(
                                                      item.product,
                                                    ),
                                              icon: Icon(
                                                cartPriceOverrides.containsKey(
                                                      item.product.variantId,
                                                    )
                                                    ? Icons.price_check_rounded
                                                    : Icons.sell_outlined,
                                              ),
                                            ),
                                          IconButton(
                                            tooltip:
                                                'Decrease ${item.product.name} quantity',
                                            onPressed: () =>
                                                decrement(item.product),
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                          Text(item.quantity.toString()),
                                          IconButton(
                                            tooltip:
                                                'Increase ${item.product.name} quantity',
                                            onPressed: () =>
                                                increment(item.product),
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey('payment-$paymentMethod'),
                          initialValue: paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Payment method',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text('Cash'),
                            ),
                            DropdownMenuItem(value: 'upi', child: Text('UPI')),
                            DropdownMenuItem(
                              value: 'razorpay',
                              child: Text('Razorpay'),
                            ),
                            DropdownMenuItem(
                              value: 'customer_credit',
                              child: Text('Customer credit'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) paymentChanged(value);
                          },
                        ),
                        if (paymentMethod == 'upi' ||
                            paymentMethod == 'razorpay') ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              paymentMethod == 'razorpay'
                                  ? 'Razorpay opens secure Standard Checkout for this bill. The sale is marked paid only after server verification.'
                                  : 'UPI checkout opens a bill-specific QR and asks for a Success or Failed confirmation before the sale is finalized.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (adjustmentActions.isNotEmpty) ...[
                          for (
                            var index = 0;
                            index < adjustmentActions.length;
                            index += 2
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index + 2 < adjustmentActions.length
                                    ? 8
                                    : 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: adjustmentActions[index]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: index + 1 < adjustmentActions.length
                                        ? adjustmentActions[index + 1]
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        _TotalRow(
                          label: 'Subtotal',
                          value: formatMoney(
                            workspace.currencyCode,
                            displaySubtotalMinor,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _TotalRow(
                          label: 'Tax',
                          value: formatMoney(
                            workspace.currencyCode,
                            displayTaxMinor,
                          ),
                        ),
                        if (displayDiscountMinor > 0) ...[
                          const SizedBox(height: 5),
                          _TotalRow(
                            label: 'Discount',
                            value:
                                '-${formatMoney(workspace.currencyCode, displayDiscountMinor)}',
                            valueColor: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                        if (displayServiceChargeMinor > 0) ...[
                          const SizedBox(height: 5),
                          _TotalRow(
                            label: 'Service charge',
                            value: formatMoney(
                              workspace.currencyCode,
                              displayServiceChargeMinor,
                            ),
                            valueColor: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                        if (displayRoundingMinor != 0) ...[
                          const SizedBox(height: 5),
                          _TotalRow(
                            label: 'Rounding',
                            value: formatMoney(
                              workspace.currencyCode,
                              displayRoundingMinor,
                            ),
                            valueColor: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              formatMoney(
                                workspace.currencyCode,
                                displayTotalMinor,
                              ),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 460) {
                              final buttonWidth =
                                  (constraints.maxWidth - 8) / 2;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final action in secondaryActions)
                                    SizedBox(width: buttonWidth, child: action),
                                ],
                              );
                            }

                            return Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < secondaryActions.length;
                                  index++
                                ) ...[
                                  if (index > 0) const SizedBox(width: 8),
                                  Expanded(child: secondaryActions[index]),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                10,
                18,
                12 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: cart.isEmpty || busy || salesOrderDirty
                      ? null
                      : checkout,
                  icon: checkingOut
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined),
                  label: Text(
                    checkingOut
                        ? 'Completing…'
                        : salesOrderDirty
                        ? 'Update order before fulfillment'
                        : resumedSalesOrder != null
                        ? 'Fulfill sales order'
                        : 'Complete sale',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _lineTotal(CatalogProduct product, int quantity) {
  return calculatePosTotals([(product: product, quantity: quantity)])
      .totalMinor;
}

const _allowedPosPaymentMethods = <String>{
  'cash',
  'upi',
  'razorpay',
  'customer_credit',
};

/// Keeps saved carts and keyboard shortcuts inside the payment methods that
/// the POS currently exposes. Legacy tenders that are no longer supported are
/// routed to a safe default instead of resurfacing as unavailable options.
String _normalizePosPaymentMethod(String method) {
  final normalized = method.trim().toLowerCase();
  if (_allowedPosPaymentMethods.contains(normalized)) return normalized;
  if (const {
    'card',
    'bank_transfer',
    'wallet',
    'gift_card',
  }.contains(normalized)) {
    return 'razorpay';
  }
  return 'cash';
}

int? _percentageDiscountFromText(int subtotalMinor, String value) {
  final percentage = double.tryParse(value);
  if (percentage == null || percentage <= 0 || percentage > 100) return null;
  return percentageDiscountMinor(subtotalMinor, (percentage * 100).round());
}

String _minorInput(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

const _splitPaymentMethods = <String, String>{
  'cash': 'Cash',
  'upi': 'UPI',
  'razorpay': 'Razorpay',
  'customer_credit': 'Customer credit',
};

const _partialPaymentMethods = <String, String>{
  'cash': 'Cash',
  'upi': 'UPI',
  'razorpay': 'Razorpay',
};

class _CashPaymentResult {
  const _CashPaymentResult({required this.changeMinor});

  final int changeMinor;
}

class _CustomSaleItemRequest {
  const _CustomSaleItemRequest({
    required this.name,
    required this.priceMinor,
    required this.quantity,
    required this.taxRateId,
  });

  final String name;
  final int priceMinor;
  final int quantity;
  final String? taxRateId;
}

class _CustomSaleItemDialog extends StatefulWidget {
  const _CustomSaleItemDialog({
    required this.currencyCode,
    required this.taxRates,
  });

  final String currencyCode;
  final List<TaxRateOption> taxRates;

  @override
  State<_CustomSaleItemDialog> createState() => _CustomSaleItemDialogState();
}

class _CustomSaleItemDialogState extends State<_CustomSaleItemDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String? _taxRateId;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final priceMinor = parseMoneyToMinor(_priceController.text);
    final quantity = int.tryParse(_quantityController.text.trim());
    if (name.isEmpty ||
        name.length > 180 ||
        priceMinor == null ||
        priceMinor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a name and a valid positive price.'),
        ),
      );
      return;
    }
    if (quantity == null || quantity <= 0 || quantity > 100000) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid quantity.')));
      return;
    }
    Navigator.pop(
      context,
      _CustomSaleItemRequest(
        name: name,
        priceMinor: priceMinor,
        quantity: quantity,
        taxRateId: _taxRateId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.add_box_outlined),
      title: const Text('Add custom item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 180,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'Installation, delivery, or other service',
              ),
            ),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Unit price',
                prefixText: '${widget.currencyCode} ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _taxRateId,
              decoration: const InputDecoration(labelText: 'Tax rate'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No tax'),
                ),
                ...widget.taxRates.map(
                  (rate) => DropdownMenuItem<String?>(
                    value: rate.id,
                    child: Text(rate.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _taxRateId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add to sale'),
        ),
      ],
    );
  }
}

class _UpiPaymentConfirmation {
  const _UpiPaymentConfirmation({
    required this.status,
    required this.reference,
  });

  final String status;
  final String reference;
}

const _upiPaymentAddress = 'kaushal.pithva@ptaxis';

class _UpiPaymentDialog extends StatefulWidget {
  const _UpiPaymentDialog({
    required this.currencyCode,
    required this.amountMinor,
    required this.gatewayName,
  });

  final String currencyCode;
  final int amountMinor;
  final String gatewayName;

  @override
  State<_UpiPaymentDialog> createState() => _UpiPaymentDialogState();
}

class _UpiPaymentDialogState extends State<_UpiPaymentDialog> {
  final _referenceController = TextEditingController();
  late final String _paymentReference;

  @override
  void initState() {
    super.initState();
    _paymentReference = 'UPI-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  void _finish(String status) {
    final enteredReference = _referenceController.text.trim();
    final reference = enteredReference.isEmpty
        ? _paymentReference
        : enteredReference;
    Navigator.pop(
      context,
      _UpiPaymentConfirmation(status: status, reference: reference),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.amountMinor / 100).toStringAsFixed(2);
    final upiPayload = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': _upiPaymentAddress,
        'pn': 'FlexPOS',
        'am': amount,
        'cu': 'INR',
        'tr': _paymentReference,
        'tn': 'FlexPOS UPI payment',
      },
    ).toString();
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_2_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Confirm ${widget.gatewayName} payment',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        formatMoney(widget.currencyCode, widget.amountMinor),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fixed amount for this bill',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _UpiQrPreview(data: upiPayload),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Scan to pay via ${widget.gatewayName} UPI',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _upiPaymentAddress,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'After the customer pays, choose Success only when the payment is confirmed. Choose Failed when it was not received.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _referenceController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'UPI reference (optional)',
                          hintText: 'UTR or transaction reference',
                          prefixIcon: Icon(Icons.receipt_long_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _finish('failed'),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Failed'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _finish('settled'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Success'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the payment QR as an image on a separate async task. This avoids
/// leaving the whole dialog blank if a browser cannot paint a CustomPaint QR
/// directly during the route transition.
class _UpiQrPreview extends StatefulWidget {
  const _UpiQrPreview({required this.data});

  final String data;

  @override
  State<_UpiQrPreview> createState() => _UpiQrPreviewState();
}

class _UpiQrPreviewState extends State<_UpiQrPreview> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _renderQr();
  }

  Future<Uint8List?> _renderQr() async {
    try {
      final painter = QrPainter(
        data: widget.data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        gapless: true,
      );
      final imageData = await painter.toImageData(
        224,
        format: ui.ImageByteFormat.png,
      );
      return imageData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 224,
      child: FutureBuilder<Uint8List?>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            // Keep a widget-based QR fallback for HTML-renderer builds where
            // off-screen image encoding is not available.
            return QrImageView(
              data: widget.data,
              size: 224,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              semanticsLabel: 'UPI payment QR code',
              errorStateBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'QR unavailable.\nUse UPI ID:\n$_upiPaymentAddress',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.black),
                  ),
                ),
              ),
            );
          }
          return Image.memory(
            bytes,
            width: 224,
            height: 224,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            semanticLabel: 'UPI payment QR code',
          );
        },
      ),
    );
  }
}

class _CashPaymentDialog extends StatefulWidget {
  const _CashPaymentDialog({
    required this.currencyCode,
    required this.cashDueMinor,
  });

  final String currencyCode;
  final int cashDueMinor;

  @override
  State<_CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<_CashPaymentDialog> {
  late final TextEditingController _tenderedController;

  @override
  void initState() {
    super.initState();
    _tenderedController = TextEditingController(
      text: _minorInput(widget.cashDueMinor),
    );
  }

  @override
  void dispose() {
    _tenderedController.dispose();
    super.dispose();
  }

  int? get _tenderedMinor => parseMoneyToMinor(_tenderedController.text);

  int? get _changeMinor {
    final tendered = _tenderedMinor;
    if (tendered == null || tendered < widget.cashDueMinor) return null;
    return calculateCashChangeMinor(
      cashDueMinor: widget.cashDueMinor,
      cashTenderedMinor: tendered,
    );
  }

  void _submit() {
    final change = _changeMinor;
    if (change == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash tendered must cover the amount due.'),
        ),
      );
      return;
    }
    Navigator.pop(context, _CashPaymentResult(changeMinor: change));
  }

  @override
  Widget build(BuildContext context) {
    final change = _changeMinor;
    return AlertDialog(
      icon: const Icon(Icons.payments_outlined),
      title: const Text('Accept cash'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TotalRow(
              label: 'Amount due',
              value: formatMoney(widget.currencyCode, widget.cashDueMinor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tenderedController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Cash tendered',
                suffixText: widget.currencyCode,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            _TotalRow(
              label: 'Change',
              value: change == null
                  ? '—'
                  : formatMoney(widget.currencyCode, change),
              valueColor: change == null
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Accept payment')),
      ],
    );
  }
}

class _SplitPaymentResult {
  const _SplitPaymentResult({
    required this.lines,
    required this.cashChangeMinor,
  });

  final List<PosPaymentLine> lines;
  final int cashChangeMinor;
}

class _PaymentDraft {
  _PaymentDraft({required this.method, required int amountMinor})
    : amountController = TextEditingController(
        text: amountMinor > 0 ? _minorInput(amountMinor) : '',
      );

  String method;
  final TextEditingController amountController;

  void dispose() => amountController.dispose();
}

class _SplitPaymentDialog extends StatefulWidget {
  const _SplitPaymentDialog({
    required this.currencyCode,
    required this.totalMinor,
  });

  final String currencyCode;
  final int totalMinor;

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  final List<_PaymentDraft> _drafts = [];
  late final TextEditingController _cashTenderedController;
  late int _lastCashDueMinor;

  @override
  void initState() {
    super.initState();
    final cashMinor = widget.totalMinor > 1 ? widget.totalMinor ~/ 2 : 1;
    _drafts.add(_PaymentDraft(method: 'cash', amountMinor: cashMinor));
    if (widget.totalMinor > 1) {
      _drafts.add(
        _PaymentDraft(
          method: 'razorpay',
          amountMinor: widget.totalMinor - cashMinor,
        ),
      );
    }
    _lastCashDueMinor = cashMinor;
    _cashTenderedController = TextEditingController(
      text: _minorInput(cashMinor),
    );
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    _cashTenderedController.dispose();
    super.dispose();
  }

  int get _allocatedMinor => _drafts.fold(
    0,
    (total, draft) =>
        total + (parseMoneyToMinor(draft.amountController.text) ?? 0),
  );

  int get _cashDueMinor => _drafts
      .where((draft) => draft.method == 'cash')
      .fold(
        0,
        (total, draft) =>
            total + (parseMoneyToMinor(draft.amountController.text) ?? 0),
      );

  int? get _cashChangeMinor {
    final tendered = parseMoneyToMinor(_cashTenderedController.text);
    if (tendered == null || tendered < _cashDueMinor) return null;
    return calculateCashChangeMinor(
      cashDueMinor: _cashDueMinor,
      cashTenderedMinor: tendered,
    );
  }

  void _paymentChanged(VoidCallback change) {
    final priorTendered = parseMoneyToMinor(_cashTenderedController.text);
    change();
    final newCashDue = _cashDueMinor;
    if (priorTendered == _lastCashDueMinor) {
      _cashTenderedController.text = _minorInput(newCashDue);
    }
    _lastCashDueMinor = newCashDue;
    setState(() {});
  }

  void _addPayment() {
    final remaining = widget.totalMinor - _allocatedMinor;
    _paymentChanged(
      () => _drafts.add(
        _PaymentDraft(
          method: 'razorpay',
          amountMinor: remaining > 0 ? remaining : 0,
        ),
      ),
    );
  }

  void _removePayment(int index) {
    if (_drafts.length <= 2) return;
    _paymentChanged(() => _drafts.removeAt(index).dispose());
  }

  void _submit() {
    if (_drafts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least two payment lines.')),
      );
      return;
    }
    final lines = <PosPaymentLine>[];
    for (final draft in _drafts) {
      final amount = parseMoneyToMinor(draft.amountController.text);
      if (amount == null || amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Every split payment needs a positive amount.'),
          ),
        );
        return;
      }
      lines.add(PosPaymentLine(method: draft.method, amountMinor: amount));
    }
    try {
      validatePosPaymentLines(lines, totalMinor: widget.totalMinor);
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allocated payments must exactly equal the sale total.',
          ),
        ),
      );
      return;
    }
    final change = _cashDueMinor == 0 ? 0 : _cashChangeMinor;
    if (change == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash tendered must cover the cash portion.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _SplitPaymentResult(lines: lines, cashChangeMinor: change),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allocated = _allocatedMinor;
    final remaining = widget.totalMinor - allocated;
    final cashDue = _cashDueMinor;
    final change = cashDue == 0 ? 0 : _cashChangeMinor;
    return AlertDialog(
      icon: const Icon(Icons.call_split_rounded),
      title: const Text('Split payment'),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TotalRow(
                  label: 'Sale total',
                  value: formatMoney(widget.currencyCode, widget.totalMinor),
                ),
                const SizedBox(height: 16),
                for (var index = 0; index < _drafts.length; index++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: _drafts[index].method,
                          decoration: const InputDecoration(
                            labelText: 'Method',
                          ),
                          items: _splitPaymentMethods.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              _paymentChanged(
                                () => _drafts[index].method = value,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _drafts[index].amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Amount',
                            suffixText: widget.currencyCode,
                          ),
                          onChanged: (_) => _paymentChanged(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove payment',
                        onPressed: _drafts.length > 2
                            ? () => _removePayment(index)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addPayment,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add payment'),
                  ),
                ),
                const Divider(height: 24),
                _TotalRow(
                  label: 'Allocated',
                  value: formatMoney(widget.currencyCode, allocated),
                ),
                const SizedBox(height: 6),
                _TotalRow(
                  label: remaining >= 0 ? 'Remaining' : 'Over allocated',
                  value: formatMoney(widget.currencyCode, remaining.abs()),
                  valueColor: remaining == 0
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                if (cashDue > 0) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _cashTenderedController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cash tendered',
                      helperText:
                          'Cash portion: ${formatMoney(widget.currencyCode, cashDue)}',
                      suffixText: widget.currencyCode,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  _TotalRow(
                    label: 'Change',
                    value: change == null
                        ? '—'
                        : formatMoney(widget.currencyCode, change),
                    valueColor: change == null
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Cash settles immediately. Manual UPI uses the bill-specific QR; Razorpay opens Standard Checkout as a sole tender and is server-verified before the sale is paid.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Use split payment'),
        ),
      ],
    );
  }
}

class _PartialPaymentDialog extends StatefulWidget {
  const _PartialPaymentDialog({
    required this.currencyCode,
    required this.totalMinor,
  });

  final String currencyCode;
  final int totalMinor;

  @override
  State<_PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<_PartialPaymentDialog> {
  String _method = 'cash';
  late final TextEditingController _paidController;
  late final TextEditingController _cashTenderedController;
  late int _lastPaidMinor;

  @override
  void initState() {
    super.initState();
    final initialPaid = widget.totalMinor > 1 ? widget.totalMinor ~/ 2 : 0;
    _lastPaidMinor = initialPaid;
    _paidController = TextEditingController(text: _minorInput(initialPaid));
    _cashTenderedController = TextEditingController(
      text: _minorInput(initialPaid),
    );
  }

  @override
  void dispose() {
    _paidController.dispose();
    _cashTenderedController.dispose();
    super.dispose();
  }

  int? get _paidMinor => parseMoneyToMinor(_paidController.text);

  int? get _balanceMinor {
    final paid = _paidMinor;
    if (paid == null || paid <= 0 || paid >= widget.totalMinor) return null;
    return widget.totalMinor - paid;
  }

  int? get _cashChangeMinor {
    final paid = _paidMinor;
    final tendered = parseMoneyToMinor(_cashTenderedController.text);
    if (paid == null || tendered == null || tendered < paid) return null;
    return calculateCashChangeMinor(
      cashDueMinor: paid,
      cashTenderedMinor: tendered,
    );
  }

  void _paidChanged() {
    final nextPaid = _paidMinor ?? 0;
    final tendered = parseMoneyToMinor(_cashTenderedController.text);
    if (_method == 'cash' && tendered == _lastPaidMinor) {
      _cashTenderedController.text = _minorInput(nextPaid);
    }
    _lastPaidMinor = nextPaid;
    setState(() {});
  }

  void _submit() {
    final paid = _paidMinor;
    final balance = _balanceMinor;
    if (paid == null || balance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Paid now must be greater than zero and less than the sale total.',
          ),
        ),
      );
      return;
    }
    final change = _method == 'cash' ? _cashChangeMinor : 0;
    if (change == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash tendered must cover the amount paid now.'),
        ),
      );
      return;
    }
    final lines = buildPartialPaymentLines(
      immediateMethod: _method,
      paidNowMinor: paid,
      totalMinor: widget.totalMinor,
    );
    Navigator.pop(
      context,
      _SplitPaymentResult(lines: lines, cashChangeMinor: change),
    );
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balanceMinor;
    final change = _method == 'cash' ? _cashChangeMinor : 0;
    return AlertDialog(
      icon: const Icon(Icons.account_balance_wallet_outlined),
      title: const Text('Partial payment'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TotalRow(
                label: 'Sale total',
                value: formatMoney(widget.currencyCode, widget.totalMinor),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Paid now with'),
                items: _partialPaymentMethods.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _method = value;
                    if (value == 'cash') {
                      _cashTenderedController.text = _minorInput(
                        _paidMinor ?? 0,
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paidController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount paid now',
                  suffixText: widget.currencyCode,
                ),
                onChanged: (_) => _paidChanged(),
              ),
              if (_method == 'cash') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _cashTenderedController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cash tendered',
                    suffixText: widget.currencyCode,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const Divider(height: 28),
              _TotalRow(
                label: 'Customer-credit balance',
                value: balance == null
                    ? '—'
                    : formatMoney(widget.currencyCode, balance),
                valueColor: balance == null
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              if (_method == 'cash') ...[
                const SizedBox(height: 8),
                _TotalRow(
                  label: 'Change',
                  value: change == null
                      ? '—'
                      : formatMoney(widget.currencyCode, change),
                  valueColor: change == null
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'The unpaid balance is posted to the selected customer’s credit statement and remains subject to their credit limit.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record payment')),
      ],
    );
  }
}

class _GiftCardIssueRequest {
  const _GiftCardIssueRequest({
    required this.amountMinor,
    required this.expiresAt,
  });

  final int amountMinor;
  final DateTime expiresAt;
}

class _GiftCardIssueDialog extends StatefulWidget {
  const _GiftCardIssueDialog({required this.currencyCode, this.customerName});

  final String currencyCode;
  final String? customerName;

  @override
  State<_GiftCardIssueDialog> createState() => _GiftCardIssueDialogState();
}

class _GiftCardIssueDialogState extends State<_GiftCardIssueDialog> {
  final _amountController = TextEditingController();
  late DateTime _expiresAt;

  @override
  void initState() {
    super.initState();
    final defaultExpiry = DateTime.now().add(const Duration(days: 365));
    _expiresAt = DateTime(
      defaultExpiry.year,
      defaultExpiry.month,
      defaultExpiry.day,
      23,
      59,
      59,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime(now.year, now.month, now.day + 1),
      lastDate: DateTime(now.year + 10, now.month, now.day),
      helpText: 'Gift-card expiry',
    );
    if (picked == null) return;
    setState(() {
      _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  void _submit() {
    final amountMinor = parseMoneyToMinor(_amountController.text);
    if (amountMinor == null || amountMinor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a gift-card value above zero.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _GiftCardIssueRequest(amountMinor: amountMinor, expiresAt: _expiresAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.add_card_rounded),
      title: const Text('Issue gift card'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Initial value',
                suffixText: widget.currencyCode,
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Expiry date'),
              subtitle: Text(DateFormat.yMMMd().format(_expiresAt)),
              trailing: TextButton(
                onPressed: _pickExpiry,
                child: const Text('Change'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.customerName == null
                  ? 'This card can be used by any customer.'
                  : 'This card will be bound to ${widget.customerName}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Issuance creates stored value and is recorded in the immutable audit ledger.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Issue card')),
      ],
    );
  }
}

class _SerializedSaleDialog extends StatefulWidget {
  const _SerializedSaleDialog({
    required this.items,
    required this.warehouseId,
    required this.units,
  });

  final List<({CatalogProduct product, int quantity})> items;
  final String warehouseId;
  final List<SerializedInventoryUnit> units;

  @override
  State<_SerializedSaleDialog> createState() => _SerializedSaleDialogState();
}

class _SerializedSaleDialogState extends State<_SerializedSaleDialog> {
  final Map<String, Set<String>> _selected = {};

  void _submit() {
    final missing = widget.items.where((item) {
      return (_selected[item.product.variantId]?.length ?? 0) != item.quantity;
    });
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select one available serial/IMEI for every unit.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _selected.map(
        (key, value) => MapEntry(key, value.toList(growable: false)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.qr_code_scanner_rounded),
      title: const Text('Select serials / IMEIs'),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 540),
          child: ListView(
            shrinkWrap: true,
            children: widget.items
                .map((item) {
                  final product = item.product;
                  final available = widget.units
                      .where(
                        (unit) =>
                            unit.variantId == product.variantId &&
                            unit.warehouseId == widget.warehouseId &&
                            unit.status == 'in_stock',
                      )
                      .toList(growable: false);
                  final selected = _selected.putIfAbsent(
                    product.variantId,
                    () => <String>{},
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${product.name} · ${product.variantName}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            'Select ${item.quantity} ${product.trackingMode == 'imei' ? 'IMEI(s)' : 'serial(s)'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (available.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'No available units in this warehouse.',
                              ),
                            )
                          else
                            ...available.map(
                              (unit) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: selected.contains(unit.id),
                                title: Text(unit.identifier),
                                subtitle: Text(unit.trackingLabel),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      if (selected.length < item.quantity) {
                                        selected.add(unit.id);
                                      }
                                    } else {
                                      selected.remove(unit.id);
                                    }
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Use selected units'),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class _CashierPinDialog extends StatefulWidget {
  const _CashierPinDialog();

  @override
  State<_CashierPinDialog> createState() => _CashierPinDialogState();
}

class _CashierPinDialogState extends State<_CashierPinDialog> {
  final _controller = TextEditingController();
  final _biometric = BiometricReentry();
  bool _biometricAvailable = false;
  bool _biometricAvailabilityResolved = false;
  bool _biometricVerified = false;
  bool _checkingBiometric = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricAvailability();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded),
      title: const Text('Re-enter cashier PIN'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        maxLength: 12,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: '6–12 digit PIN',
          prefixIcon: Icon(Icons.pin_outlined),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: !_biometricAvailabilityResolved || _checkingBiometric
              ? null
              : _verifyBiometric,
          icon: _checkingBiometric
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fingerprint_rounded),
          label: Text(_biometricVerified ? 'Device verified' : 'Verify device'),
        ),
        FilledButton(
          onPressed:
              !_biometricAvailabilityResolved ||
                  (_biometricAvailable && !_biometricVerified)
              ? null
              : _submit,
          child: const Text('Unlock sale'),
        ),
      ],
    );
  }

  Future<void> _loadBiometricAvailability() async {
    final available = await _biometric.isAvailable();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricAvailabilityResolved = true;
    });
  }

  Future<void> _verifyBiometric() async {
    setState(() => _checkingBiometric = true);
    final verified = await _biometric.authenticate();
    if (!mounted) return;
    setState(() {
      _checkingBiometric = false;
      _biometricVerified = verified;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          verified ? 'Device verified. Enter the cashier PIN to continue.' : 'Biometric verification was unavailable or cancelled. Use the cashier PIN.',
        ),
      ),
    );
  }

  void _submit() {
    if (_biometricAvailable && !_biometricVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verify this device before entering the cashier PIN.'),
        ),
      );
      return;
    }
    final pin = _controller.text.trim();
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6–12 digit cashier PIN.')),
      );
      return;
    }
    Navigator.pop(context, pin);
  }
}
