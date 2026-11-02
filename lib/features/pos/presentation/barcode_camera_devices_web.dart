import 'dart:js_interop';

import 'package:web/web.dart' as web;

class BarcodeCameraDevice {
  const BarcodeCameraDevice({required this.id, required this.label});

  final String id;
  final String label;
}

const _preferredDeviceStorageKey = 'mobile_scanner_preferred_device_id';

Future<List<BarcodeCameraDevice>> listBarcodeCameraDevices() async {
  try {
    final mediaDevices = web.window.navigator.mediaDevices;
    final devices = (await mediaDevices.enumerateDevices().toDart).toDart;
    var unnamedCamera = 0;
    return devices
        .where((device) => device.kind == 'videoinput')
        .map((device) {
          final label = device.label.trim();
          final displayLabel = label.isEmpty
              ? 'Camera ${++unnamedCamera}'
              : label;
          return BarcodeCameraDevice(id: device.deviceId, label: displayLabel);
        })
        .where((device) => device.id.trim().isNotEmpty)
        .toList(growable: false);
  } on Object {
    return const [];
  }
}

Future<void> selectBarcodeCameraDevice(String deviceId) async {
  final normalized = deviceId.trim();
  if (normalized.isEmpty) return;
  try {
    web.window.localStorage.setItem(_preferredDeviceStorageKey, normalized);
  } on Object {
    // Private browsing modes may disable localStorage. The current camera
    // remains usable; the browser will choose the next available input.
  }
}
