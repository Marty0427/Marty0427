# Releasing PocketPass

The listing text, privacy manifest and release automation are in the repository. What is left
needs an Apple Developer account, a Mac and a device — none of which a CI container or an
assistant can stand in for.

Work through this in order. Steps marked **(only you)** cannot be automated at all.

## 1. Accounts and identifiers — **(only you)**

- [ ] Apple Developer Program membership, $99/year, at <https://developer.apple.com/programs/>.
      Enrolment takes anywhere from a few hours to a couple of days.
- [ ] Register a bundle identifier you own at Certificates, Identifiers & Profiles. The project
      ships with the placeholder `com.marty0427.PocketPass`; either register that or set
      `POCKETPASS_BUNDLE_ID` and change the two `PRODUCT_BUNDLE_IDENTIFIER` values in
      `PocketPass.xcodeproj`.
- [ ] Create the app record in App Store Connect: **My Apps → + → New App**, platform iOS,
      the bundle ID from above, primary language English, SKU anything unique.
- [ ] Note your ten character **Team ID** (Membership page).

## 2. App Store Connect API key — **(only you)**

Users and Access → Integrations → App Store Connect API → **+**, role **App Manager**.

- [ ] Download the `AuthKey_XXXXXXXXXX.p8`. **Apple lets you download it once.**
- [ ] Keep the Key ID and the Issuer ID.
- [ ] Never commit the `.p8`; `.gitignore` blocks `*.p8`, but the real protection is not
      putting it in the repository in the first place.

## 3. First build on a Mac

The project has never been compiled — it was written in a Linux container with no Swift
toolchain. Expect to fix a few things the compiler finds on the first open.

```sh
cd PocketPass
open PocketPass.xcodeproj          # Xcode 16 or newer
```

- [ ] Signing & Capabilities → select your team, leave signing automatic.
- [ ] Build and run on a real device (⌘R). The scanner needs a camera; the simulator has none.
- [ ] `bundle install && bundle exec fastlane test` — the unit tests should pass.
- [ ] Scan a real QR code, a Code 128 membership card and an EAN-13 retail card.
- [ ] Show a generated EAN-13 and Code 128 to a second phone's scanner, at normal brightness
      and in a dark room. This is the one test that matters: a barcode that looks right and
      does not scan is the whole product failing.

## 4. Screenshots — **(only you)**

Apple will not accept the listing without them. Take them on device or simulator, drop the
PNGs into `fastlane/screenshots/en-US/` named `01_...`, `02_...` in display order, and commit
them. Sizes are listed in that directory's README.

Suggested five: the wallet full of cards; a card open at full brightness; the scanner with a
card framed; the editor showing live validation; Settings showing the app lock.

## 5. Upload

```sh
cd PocketPass
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_CONTENT=$(base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8)
export DEVELOPER_TEAM_ID=XXXXXXXXXX

bundle exec fastlane beta       # TestFlight, for testing it end to end first
bundle exec fastlane release    # uploads the build AND the listing text
```

`release` deliberately stops short of submitting for review. Pass `submit:true` when you are
ready, or press Submit in App Store Connect yourself.

The same lanes run from GitHub: **Actions → PocketPass → Run workflow**, once
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` and `DEVELOPER_TEAM_ID` exist as repository
secrets. It is manual-dispatch only — macOS runners are billed at ten times the Linux rate.

## 6. Fields only a person can fill in App Store Connect — **(only you)**

`fastlane release` uploads the name, subtitle, description, keywords, promotional text,
release notes and URLs from `fastlane/metadata/`. These are not in that set:

- [ ] **Category**: Utilities (primary). No secondary needed.
- [ ] **Copyright**: your name or company, e.g. `2026 Your Name`.
- [ ] **Age rating** questionnaire: every answer "None" → 4+.
- [ ] **App Privacy**: choose **"No, we do not collect data from this app."** That is accurate
      as built — there is no network code anywhere in the app, and `PrivacyInfo.xcprivacy`
      declares the same.
- [ ] **Contact information** for review (name, phone, email).
- [ ] **Privacy policy URL**: publish `AppStore/metadata/privacy_policy.md` somewhere public
      and put the URL both there and in `fastlane/metadata/en-US/privacy_url.txt`.
- [ ] **Support URL**: replace the `example.com` placeholder in
      `fastlane/metadata/en-US/support_url.txt`.

Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is `NO` in the build
settings, which is correct — the app uses no encryption beyond iOS file protection.

## What review will most likely ask about

- **Camera usage**: the purpose string is specific and the app only opens the camera on the
  scanner screen. The review notes in `fastlane/metadata/review_information/notes.txt` spell
  this out.
- **Minimum functionality** (guideline 4.2) is the realistic risk for a utility this small.
  The counter is that it does something the built-in Wallet does not: store arbitrary retail
  barcodes offline. If it is rejected on 4.2, the reply is that specific capability, not a
  promise of features.
- **Do not** describe it as a Google Wallet or Apple Wallet alternative in the listing. The
  current copy does not.
