# Architecture

PocketPass is a single-module SwiftUI app with no external dependencies. This document covers
the decisions that are not obvious from reading the types.

## Data flow

```
ScannerScreen ─┐
PhotoImport   ─┼─► ScanResult ─► CardDraft ─► WalletCard ─► CardStore ─► CardRepository ─► cards.json
ManualEntry   ─┘                                                │
                                                                ▼
                                            WalletView / CardDetailView ─► BarcodeView ─► BarcodeRenderer
```

`CardStore` is the only mutable source of truth and is `@MainActor`. It writes through to a
`CardRepository` on every change; the protocol exists so tests (and previews) can run against
memory instead of a disk.

## Storage

One JSON file in Application Support, written atomically with
`Data.WritingOptions.completeFileProtection`. That means:

- the file is unreadable while the device is locked, which is the right default for a wallet;
- the app only touches it in the foreground, so complete protection costs nothing;
- a backup is the same JSON, so nothing about the format is secret or lossy.

`WalletCard.init(from:)` decodes leniently — every field except `payload` falls back to a
default. A backup that a person edited by hand, or that a newer build wrote, still restores
instead of failing wholesale.

## Barcodes

### Two engines

| Symbology | Engine | Why |
|---|---|---|
| QR, Aztec, PDF417, Code 128 | Core Image generator filters | Apple ships them |
| EAN-13, EAN-8, UPC-A, UPC-E, ITF-14, Code 39 | `LinearBarcodeEncoder` + `BitmapBarcodeRenderer` | Core Image has no generator for these |

`BarcodeRenderer` picks the engine; `LinearBarcodeEncoderTests.testEverySymbologyHasExactlyOneEngine`
fails if a new format is ever added to both or neither.

### Whole-pixel modules

Bars are drawn at an integer number of pixels per module, and Core Image output is scaled by an
integer factor with nearest-neighbour sampling. Fractional module widths make a symbol that
looks fine and scans badly, because adjacent bars end up different widths after rounding.

Neighbouring bars are merged into a single fill, both for speed and because separate adjacent
fills can leave a hairline seam.

### Quiet zones

Ten modules each side for linear symbols (EAN requires at least nine). `BarcodeView` always
draws on white with padding, in dark mode as well — an inverted barcode is not scannable.

### UPC-A and UPC-E

Two details in the standards leak into the code:

- **UPC-A is EAN-13 with a leading zero**, and it produces identical bars. Scanners (both
  AVFoundation and Vision) report UPC-A as a 13-digit EAN-13 starting with `0`.
  `ScanResultMapper.resolve` converts that back to the 12 digits printed on the card, so the
  number in the app matches the number on the plastic.
- **UPC-E is drawn as its UPC-A expansion.** A true UPC-E symbol is a different, narrower
  encoding; every till expands it to the same GTIN on read, and the expansion is what the
  product number actually is. Storing the short form and drawing the long one keeps both the
  display and the scan correct, and avoids a second parity table. `BarcodeValidator.upcAEquivalent`
  implements the expansion rules.

### Check digits

`BarcodeValidator` completes the GS1 modulo-10 check digit when the typed number omits it
(loyalty cards are often printed without it) and rejects a number whose check digit is wrong,
naming the digit it expected. That error surfaces under the text field while typing.

## Scanning

`BarcodeCaptureController` owns an `AVCaptureSession` configured on a private queue —
`startRunning()` blocks, and doing it on the main queue is a visible stutter when the sheet
opens. Detection is limited to the highlighted window via `rectOfInterest`, which speeds up
recognition and stops the scanner grabbing the next card on the table.

Delivery is one-shot: after a code is recognised the controller stops reporting until the
caller calls `resume()`. Without that, a single card fires the callback dozens of times a second.

Formats the app cannot re-draw (Data Matrix, Code 93) are still requested from the session, so
the scanner can say "this format isn't supported yet" instead of appearing broken.

## Privacy

No network code exists in the app. `PrivacyInfo.xcprivacy` declares no collected data and one
required-reason API (`UserDefaults`, reason `CA92.1`). The camera is used only while the
scanner is open; photo import goes through `PhotosPicker`, which runs out of process and hands
over exactly one image.

The optional app lock is a privacy screen, not encryption — `SettingsView` says so plainly,
because a lock that implies more protection than it gives is worse than none.

## Testing

`PocketPassTests` covers the parts where a mistake is expensive and invisible: check digits,
encoding tables, symbol assembly, scan-result mapping, store behaviour and backup round-trips.
The UI layer is deliberately thin and left to previews.
