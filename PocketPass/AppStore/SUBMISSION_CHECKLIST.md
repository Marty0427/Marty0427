# App Store submission checklist

Everything in `metadata/` is ready to paste into App Store Connect. The items below are the
ones that need a real account, a Mac or a device, and cannot be completed from the repository.

## Before the first build

- [ ] Change `PRODUCT_BUNDLE_IDENTIFIER` from `com.marty0427.PocketPass` to an identifier your
      team owns (both the app and test targets), and register it in the Developer portal.
- [ ] Select a development team in Signing & Capabilities; leave signing automatic.
- [ ] Decide the display name. `INFOPLIST_KEY_CFBundleDisplayName` is currently `PocketPass`.
- [ ] Publish `metadata/privacy_policy.md` at a public URL — App Store Connect requires one.
- [ ] Replace the placeholder support and marketing URLs in `metadata/en-US/`.

## App Privacy answers (Data collection)

Answer **"No, we do not collect data from this app."** Every part of it is true as built:

| Question | Answer |
|---|---|
| Contact info, identifiers, usage data, diagnostics | Not collected |
| Tracking across apps and websites | No |
| Third-party analytics or advertising SDKs | None |

`PocketPass/PrivacyInfo.xcprivacy` already declares this, plus the one required-reason API the
app uses (`UserDefaults`, reason `CA92.1`).

## Ratings and compliance

- [ ] Age rating questionnaire: all "None" — the app has no user content, web views, gambling
      or contests. Expected rating 4+.
- [ ] Export compliance: the app uses no encryption beyond what iOS provides for file
      protection, so the standard exemption applies (`ITSAppUsesNonExemptEncryption = NO` can
      be added to the Info.plist to stop the question being asked on every upload).
- [ ] Content rights: no third-party content.

## Screenshots

Required sizes (one set covers the rest by scaling):

- [ ] 6.9" iPhone (1320 × 2868)
- [ ] 6.5" iPhone (1242 × 2688) — still required for older device families
- [ ] 13" iPad (2064 × 2752), since the app ships as universal (`TARGETED_DEVICE_FAMILY = "1,2"`)

Suggested shots, in order:

1. The wallet, full of cards, with the categories visible.
2. A card open at full brightness, showing a QR code.
3. The scanner with a card framed.
4. The editor showing live validation and the symbol preview.
5. Settings, showing the app lock and "nothing is uploaded".

## Review notes

Paste into App Review Information → Notes:

> PocketPass stores barcodes locally. There is no account, so no demo credentials are needed.
> To exercise the scanner on a device, point it at any QR code or retail barcode. In the
> simulator, use "Import from Photos" with a screenshot of a barcode, or "Enter Manually"
> (for example format EAN-13, code 5901234123457).

## Testing before upload

- [ ] `Scripts/test.sh` passes.
- [ ] Scan tested on a real device for at least: a QR code, a Code 128 membership card and an
      EAN-13 retail card.
- [ ] A generated EAN-13 and Code 128 verified against a second phone's scanner, at normal
      brightness and in a dark room.
- [ ] VoiceOver pass over the wallet and card screens.
- [ ] Dynamic Type at the largest accessibility size.
- [ ] Dark mode: barcodes must stay black on white.
