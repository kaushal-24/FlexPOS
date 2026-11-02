# Hardware barcode scanner setup

FlexPOS supports barcode scanners that expose themselves to the operating
system as a keyboard (HID/keyboard-wedge mode). This works with a USB scanner
or a Bluetooth scanner paired as a keyboard and does not require a fixed app
port, a native SDK, or an offline queue.

## Setup

1. Connect the USB scanner, or pair the Bluetooth scanner in the operating
   system's Bluetooth settings.
2. If the scanner offers programming barcodes, select keyboard-wedge/HID mode,
   the keyboard layout used by the workstation, and an `Enter` suffix after
   each scan. FlexPOS uses the suffix to submit the captured value.
3. Sign in to FlexPOS, open POS, and press `F2` or click the scanner-focus icon
   in the product search field.
4. Scan a product whose barcode is stored in the active catalog. The value is
   normalized, submitted on Enter, and added only when there is one exact
   barcode match.

The camera button beside the field provides camera barcode/QR scanning on
supported targets. The scanner waits for the preview to attach before asking
for camera access, accepts both raw and display barcode values, and provides a
Retry camera action when permission or initialization fails. On the web, run
the app from `localhost` or HTTPS and allow camera access for the browser. If
camera permission is denied or a platform has no camera support, use the
focused keyboard-wedge field instead.

On desktop browsers, a webcam may report an unknown facing direction and show
a mirrored preview. FlexPOS corrects that preview for barcode aiming and
provides a **Flip camera** action when more than one camera is available.
The web scanner uses the ZXing WASM backend for common retail formats such as
EAN-8, EAN-13, UPC, Code 128, Code 39, ITF, and QR.
If the WASM decoder does not produce a result after initialization, FlexPOS
automatically retries with the compatibility ZXing JavaScript decoder.

## Troubleshooting

- If text appears in another application instead of POS, return to POS and
  press `F2` before scanning.
- If the scan types correctly but does not submit, configure the scanner to
  append Enter (sometimes called CR, Return, or suffix `0x0D`). Pressing Enter
  manually is also supported.
- If POS reports no exact match, confirm the barcode is stored on the active
  product variant and that the selected business/warehouse is correct.
- Do not treat a successful scan as payment confirmation. Checkout still uses
  the existing authenticated Supabase transaction and payment verification
  rules.

## Physical validation record

Before release, record one successful run for every scanner model and target
device. Use a product with a known unique barcode and capture the evidence in
the release notes:

| Check | Expected result | Evidence |
| --- | --- | --- |
| Pair/connect scanner | Operating system recognizes the HID keyboard | Device/model and OS |
| F2 focus | POS search field has focus before the scan | Screenshot or screen recording |
| Scan with Enter suffix | One exact product is added to the cart | Barcode, invoice, timestamp |
| Scan unknown barcode | POS shows an exact-match error and does not add a line | Screenshot |
| Checkout after scan | Online sale completes and inventory changes once | Sale/inventory IDs |

This workspace cannot certify a physical scanner. The application-side
workflow and deterministic catalog lookup tests are complete; the table above
is the remaining device-lab evidence gate.

Native serial/SDK adapters, automatic scanner configuration, and physical
device certification remain release hardware work; the application-side
keyboard-wedge workflow is implemented and covered by the existing catalog
lookup tests.
