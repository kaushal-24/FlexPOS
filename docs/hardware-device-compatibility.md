# FlexPOS hardware compatibility

FlexPOS hardware operations are deliberately **online-only**. A signed-in
session is required to register a device, record a connectivity result, and
complete a sale. The app does not cache catalog data, queue transactions, or
settle electronic payments while disconnected.

## Supported adapter boundaries

| Device | Connection boundary | Current application behavior |
| --- | --- | --- |
| Camera barcode scanner | Camera permission / `mobile_scanner` | Camera scanning is available from the POS scanner action. |
| Bluetooth barcode scanner | HID keyboard wedge | Focused POS input accepts scanner keystrokes; the operating system pairs the scanner. |
| USB barcode scanner | HID keyboard wedge | Focused POS input accepts scanner keystrokes; the operating system supplies the USB HID device. |
| Bluetooth thermal printer | Platform print bridge | Receipt bytes and device metadata are registered online; a native bridge must own pairing and transport. |
| USB thermal printer | Platform print bridge | Receipt bytes and device metadata are registered online; a native bridge/driver must own USB access. |
| Network thermal printer | TCP/9100 platform bridge | The operator records a non-secret endpoint such as `printer.local:9100`; transport is delegated to a platform bridge. |
| ESC/POS receipts | ESC/POS command builder | Initialization, text, cut, and cash-drawer pulse bytes are generated for an online adapter. |
| Cash drawer | Printer drawer-kick command | The adapter uses the ESC/POS pulse through the connected receipt printer. |
| Label printer | USB/platform bridge | Label metadata and barcode/QR payloads are available to the online bridge. |
| Weighing scale | Serial/platform bridge | Weight input is a platform adapter boundary and must be validated before checkout. |
| Customer display | TCP/platform bridge | Basket and total updates are sent by an online platform adapter. |

## Setup and diagnostics

The **Hardware operations** screen is available from **More** when the
`hardware_operations` module is enabled. Authorized operators can register a
device, choose its branch and connection type, and record an authenticated
connectivity result (`online`, `error`, `offline`, or `disabled`). Each result
is append-only in the device event log and is visible to authorized users.

Endpoints and capability metadata must never contain passwords, API keys,
service-role keys, or transaction data. Credentials belong in a native/server
secret manager; the public database stores only device metadata and status.

## Platform notes

- Flutter web supports camera scanning, HID keyboard-wedge scanners, and the
  existing 58/80 mm PDF/system print flow.
- Android, Windows, and other native builds can provide Bluetooth, USB, TCP,
  serial, and drawer/label bridges through platform code or managed drivers.
- The registry and diagnostics screen intentionally does not pretend to open a
  raw device from a browser. A bridge reports the real online result through
  the authenticated RPC.
- Disconnected operation is not a fallback: no offline cache, queue, replay,
  deferred synchronization, or offline electronic settlement exists by design.
