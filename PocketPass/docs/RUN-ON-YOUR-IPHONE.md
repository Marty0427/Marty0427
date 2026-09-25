# Running PocketPass on your own iPhone

You need a Mac with Xcode 16 or newer, an iPhone on iOS 17 or newer, and a cable. You do
**not** need the $99 Apple Developer Program: Xcode will sign the app with a plain Apple ID.

The catch with free signing is that the build stops working after **seven days**, and you can
have three such apps on a device at once. Rebuilding renews it. That is fine for testing and
useless for keeping, which is what TestFlight is for (see `../AppStore/RELEASE.md`).

## Once, before the first build

```sh
git clone https://github.com/Marty0427/Marty0427.git
cd Marty0427/PocketPass
Scripts/set-bundle-id.sh com.yourname.PocketPass    # use something certainly yours
open PocketPass.xcodeproj
```

The bundle identifier matters more than it looks. The repository ships with the placeholder
`com.marty0427.PocketPass`, and free signing refuses to build an identifier that is already
registered to another team — the error Xcode shows for this is unhelpful, so change it first
and skip the puzzle.

Then in Xcode:

1. **Settings → Accounts → +** and add your Apple ID. It appears as a *Personal Team*.
2. Select the **PocketPass** target → **Signing & Capabilities** → Team = your Personal Team,
   "Automatically manage signing" left on.

## Once, on the iPhone

1. **Settings → Privacy & Security → Developer Mode → on**, then restart the phone. This is
   required on iOS 16 and later, and it is the step people miss: without it your device never
   appears as a run destination.
2. Plug the phone in and tap **Trust** on the "Trust This Computer?" prompt.

## Every build

1. In Xcode's destination menu (top bar) pick your iPhone, then ⌘R.
2. The first launch is refused with "Untrusted Developer". On the phone go to
   **Settings → General → VPN & Device Management**, tap your Apple ID, and trust it.
   Launch again from Xcode.

## What to actually test

The simulator has already proved the app compiles, that 87 unit tests pass, and that every
screen renders and navigates. None of that touches the hardware. These are the things only a
real phone can answer, in the order they are worth doing:

- [ ] **Scan a real card.** Tap **+ → Scan Code** and point it at a supermarket loyalty card,
      a membership barcode and any QR code. Check the number stored matches the number printed.
      A UPC-A card should store 12 digits, not 13 — that conversion is deliberate.
- [ ] **Show it to a scanner.** Open a stored card and hold it to a self-checkout, a library
      scanner, or a second phone running Google Lens. **This is the test that matters.** A
      barcode that looks right and does not scan is the whole product failing.
- [ ] **Try it dim.** Turn screen brightness right down before opening a card. The app should
      push brightness up on its own, and put it back when you leave the card.
- [ ] **Let it sit.** Open a card and wait past your usual auto-lock time. The screen should
      stay awake.
- [ ] **Import a screenshot.** Email yourself a boarding pass, screenshot it, then
      **+ → Import from Photos**.
- [ ] **Lock it.** Settings → Require Face ID, then background the app and come back.
- [ ] **Back up and restore.** Settings → Export Backup, AirDrop it to yourself, delete a
      card, then Restore from Backup.
- [ ] **Dark mode.** Barcodes must stay black on white. Anything inverted will not scan.

If something fails, the interesting detail is usually *which* format and *which* scanner —
the six linear formats are encoded by this project, while QR, Aztec, PDF417 and Code 128 come
from Apple's own generators, so a failure in each group points somewhere quite different.

## If Xcode complains

| What it says | What it means |
|---|---|
| "Failed to register bundle identifier" | The identifier is taken. Run `Scripts/set-bundle-id.sh` with a different one. |
| "Unable to install… device not supported" | The phone is on an older iOS than the 17.0 deployment target. |
| Your iPhone is missing from the destination menu | Developer Mode is off, or the cable is data-less. |
| "Untrusted Developer" on launch | Trust the certificate in Settings → General → VPN & Device Management. |
| The app dies after a week | Expected with free signing. Rebuild from Xcode. |
