import 'package:flexpos/features/hardware/domain/hardware_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hardware definitions cover every supported device boundary', () {
    expect(hardwareDeviceDefinitions, hasLength(10));
    expect(hardwareDeviceLabel('barcode_camera'), 'Camera barcode scanner');
    expect(hardwareConnectionLabel('hid'), 'HID / keyboard wedge');
    expect(hardwareConnectionLabel('tcp'), 'Network / TCP');
  });

  test('ESC/POS command helpers produce online adapter bytes', () {
    expect(escPosInitialize(), [0x1b, 0x40]);
    expect(escPosCashDrawerPulse(), [0x1b, 0x70, 0x00, 0x19, 0xfa]);

    final receipt = buildEscPosReceipt(
      businessName: 'FlexPOS',
      body: 'Total ₹150.00',
      footer: 'Thank you',
    );
    expect(receipt.take(2), [0x1b, 0x40]);
    expect(receipt, contains(0x0a));
    expect(receipt, contains(0xe2));
    expect(receipt, contains(0x1d));
    expect(receipt.last, 0x00);
  });
}
