alter table public.hardware_devices
  add constraint hardware_devices_connection_kind_check check (
    (device_kind = 'barcode_camera' and connection_type = 'camera')
    or (device_kind in ('barcode_bluetooth', 'barcode_usb') and connection_type = 'hid')
    or (device_kind = 'thermal_bluetooth' and connection_type = 'bluetooth')
    or (device_kind in ('thermal_usb', 'label_printer') and connection_type = 'usb')
    or (device_kind in ('thermal_network', 'customer_display') and connection_type = 'tcp')
    or (device_kind = 'cash_drawer' and connection_type = 'system_print')
    or (device_kind = 'weighing_scale' and connection_type = 'serial')
  );
