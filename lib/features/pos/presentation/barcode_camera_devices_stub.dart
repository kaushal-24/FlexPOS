class BarcodeCameraDevice {
  const BarcodeCameraDevice({required this.id, required this.label});

  final String id;
  final String label;
}

Future<List<BarcodeCameraDevice>> listBarcodeCameraDevices() async {
  return const [];
}

Future<void> selectBarcodeCameraDevice(String deviceId) async {}
