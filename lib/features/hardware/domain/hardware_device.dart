import 'dart:convert';

class HardwareDevice {
  const HardwareDevice({
    required this.id,
    required this.businessId,
    required this.deviceKind,
    required this.connectionType,
    required this.displayName,
    required this.status,
    required this.capabilities,
    required this.metadata,
    required this.createdAt,
    this.branchId,
    this.endpoint,
    this.lastSeenAt,
    this.lastTestedAt,
    this.lastError,
  });

  factory HardwareDevice.fromJson(Map<String, dynamic> json) {
    return HardwareDevice(
      id: json['id'] as String,
      businessId: json['business_id'] as String,
      branchId: json['branch_id'] as String?,
      deviceKind: json['device_kind'] as String,
      connectionType: json['connection_type'] as String,
      displayName: json['display_name'] as String,
      endpoint: json['endpoint'] as String?,
      status: json['status'] as String,
      capabilities: Map<String, dynamic>.from(
        (json['capabilities'] as Map?) ?? const <String, dynamic>{},
      ),
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? const <String, dynamic>{},
      ),
      lastSeenAt: _date(json['last_seen_at']),
      lastTestedAt: _date(json['last_tested_at']),
      lastError: json['last_error'] as String?,
      createdAt: _date(json['created_at']) ?? DateTime.now(),
    );
  }

  final String id;
  final String businessId;
  final String? branchId;
  final String deviceKind;
  final String connectionType;
  final String displayName;
  final String? endpoint;
  final String status;
  final Map<String, dynamic> capabilities;
  final Map<String, dynamic> metadata;
  final DateTime? lastSeenAt;
  final DateTime? lastTestedAt;
  final String? lastError;
  final DateTime createdAt;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
}

class HardwareDeviceDefinition {
  const HardwareDeviceDefinition({
    required this.code,
    required this.label,
    required this.connectionType,
    required this.description,
  });

  final String code;
  final String label;
  final String connectionType;
  final String description;
}

const hardwareDeviceDefinitions = <HardwareDeviceDefinition>[
  HardwareDeviceDefinition(
    code: 'barcode_camera',
    label: 'Camera barcode scanner',
    connectionType: 'camera',
    description: 'Mobile/web camera scanning through the permission-aware scanner adapter.',
  ),
  HardwareDeviceDefinition(
    code: 'barcode_bluetooth',
    label: 'Bluetooth barcode scanner',
    connectionType: 'hid',
    description:
        'Bluetooth HID/keyboard-wedge scanner with the focused POS input.',
  ),
  HardwareDeviceDefinition(
    code: 'barcode_usb',
    label: 'USB barcode scanner',
    connectionType: 'hid',
    description: 'USB HID/keyboard-wedge scanner with the focused POS input.',
  ),
  HardwareDeviceDefinition(
    code: 'thermal_bluetooth',
    label: 'Bluetooth thermal printer',
    connectionType: 'bluetooth',
    description: 'Raw thermal adapter boundary; use the platform print bridge for transport.',
  ),
  HardwareDeviceDefinition(
    code: 'thermal_usb',
    label: 'USB thermal printer',
    connectionType: 'usb',
    description: 'Raw thermal adapter boundary; use the platform print bridge for transport.',
  ),
  HardwareDeviceDefinition(
    code: 'thermal_network',
    label: 'Network thermal printer',
    connectionType: 'tcp',
    description:
        'Network ESC/POS adapter boundary with an operator-managed endpoint.',
  ),
  HardwareDeviceDefinition(
    code: 'cash_drawer',
    label: 'Cash drawer',
    connectionType: 'system_print',
    description:
        'ESC/POS drawer-kick command through a connected receipt printer.',
  ),
  HardwareDeviceDefinition(
    code: 'label_printer',
    label: 'Label printer',
    connectionType: 'usb',
    description: 'Label batch boundary with barcode/QR payload metadata.',
  ),
  HardwareDeviceDefinition(
    code: 'weighing_scale',
    label: 'Weighing scale',
    connectionType: 'serial',
    description: 'Serial scale input boundary for weight-based checkout.',
  ),
  HardwareDeviceDefinition(
    code: 'customer_display',
    label: 'Customer display',
    connectionType: 'tcp',
    description:
        'Online customer-display endpoint for basket and total updates.',
  ),
];

HardwareDeviceDefinition hardwareDeviceDefinition(String code) =>
    hardwareDeviceDefinitions.firstWhere(
      (item) => item.code == code,
      orElse: () => HardwareDeviceDefinition(
        code: code,
        label: code,
        connectionType: 'system_print',
        description: '',
      ),
    );

String hardwareDeviceLabel(String code) => hardwareDeviceDefinition(code).label;

String hardwareConnectionLabel(String code) => switch (code) {
  'camera' => 'Camera',
  'hid' => 'HID / keyboard wedge',
  'bluetooth' => 'Bluetooth',
  'usb' => 'USB',
  'tcp' => 'Network / TCP',
  'system_print' => 'System print bridge',
  'serial' => 'Serial',
  _ => code,
};

/// ESC/POS initialization and cash-drawer pulse bytes for a platform bridge.
/// The app deliberately does not open a device or queue bytes offline; a
/// platform adapter must send these bytes while the user is online.
List<int> escPosInitialize() => const [0x1b, 0x40];

List<int> escPosCashDrawerPulse() => const [0x1b, 0x70, 0x00, 0x19, 0xfa];

List<int> escPosText(String value) => [...utf8.encode(value), 0x0a];

List<int> buildEscPosReceipt({
  required String businessName,
  required String body,
  String? footer,
}) => [
  ...escPosInitialize(),
  ...escPosText(businessName),
  ...escPosText(body),
  if (footer != null) ...escPosText(footer),
  0x1d,
  0x56,
  0x00,
];
