import 'package:flexpos/features/inventory/domain/inventory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock loss event maps immutable quantity and value details', () {
    final event = StockLossEvent.fromJson({
      'id': 'loss-1',
      'event_number': 'DMG-001',
      'loss_type': 'damage',
      'product_name': 'Demo product',
      'variant_name': 'Default',
      'sku': 'DEMO-1',
      'quantity': '2.500000',
      'unit_cost': '12.3400',
      'loss_value': '30.85',
      'reason': 'Damaged during handling',
      'notes': 'Photo retained by manager',
      'recorded_at': '2026-10-28T09:30:00Z',
      'warehouses': {'name': 'Main warehouse'},
    });

    expect(event.typeLabel, 'Damage');
    expect(event.quantity, 2.5);
    expect(event.unitCostMinor, 1234);
    expect(event.lossValueMinor, 3085);
    expect(event.warehouseName, 'Main warehouse');
  });

  test('serialized inventory unit maps registry status and labels', () {
    final unit = SerializedInventoryUnit.fromJson({
      'id': 'unit-1',
      'tracking_mode': 'imei',
      'identifier': '356938035643809',
      'status': 'in_stock',
      'product_name': 'Demo phone',
      'variant_name': 'Default',
      'sku': 'PHONE-1',
      'registered_at': '2026-10-28T10:00:00Z',
      'warehouses': {'name': 'Main warehouse'},
    });

    expect(unit.trackingLabel, 'IMEI');
    expect(unit.statusLabel, 'In Stock');
    expect(unit.identifier, '356938035643809');
    expect(unit.warehouseName, 'Main warehouse');
  });
}
