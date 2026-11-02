import 'package:flexpos/features/purchasing/domain/purchasing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'purchase order maps nested supplier, warehouse, and remaining stock',
    () {
      final order = PurchaseOrder.fromJson({
        'id': 'po-1',
        'order_number': 'PO-001',
        'status': 'partially_received',
        'grand_total': '118.00',
        'ordered_at': '2026-10-20T08:00:00Z',
        'suppliers': {'name': 'Supplier One'},
        'warehouses': {'name': 'Main Warehouse'},
        'purchase_order_items': [
          {
            'id': 'line-1',
            'variant_id': 'variant-1',
            'product_name': 'Product One',
            'sku': 'SKU-1',
            'ordered_quantity': '10.000000',
            'received_quantity': '4.000000',
            'purchase_return_items': [
              {'quantity': '1.000000'},
            ],
            'unit_cost': '10.0000',
            'tax_rate': '18.0000',
            'product_variants': {'tracking_mode': 'serial'},
          },
        ],
      });

      expect(order.supplierName, 'Supplier One');
      expect(order.grandTotalMinor, 11800);
      expect(order.canReceive, isTrue);
      expect(order.lines.single.remainingQuantity, 6);
      expect(order.lines.single.returnedQuantity, 1);
      expect(order.lines.single.returnableQuantity, 3);
      expect(order.lines.single.taxRateBasisPoints, 1800);
      expect(order.lines.single.isSerialized, isTrue);
      expect(order.lines.single.identifierLabel, 'serial number');
      expect(order.canReturn, isTrue);
    },
  );
}
