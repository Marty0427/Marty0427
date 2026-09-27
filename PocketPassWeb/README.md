# PocketPass for the web

The same wallet as the iOS app, as a web page you can install on your Home Screen. Loyalty
cards, tickets and boarding passes, stored in your browser, shown offline.

No build step, no framework, no server: it is HTML, CSS and ES modules, and it runs from any
static host.

## Running it

```sh
cd PocketPassWeb
npm run serve          # http://127.0.0.1:8777
```

`127.0.0.1` counts as a secure context, so the camera and the service worker both work there.
On any other host you need **https** — browsers refuse camera access otherwise.

## Testing

```sh
npm test               # 342 barcode checks, no browser needed, about a second
npm install            # only needed for the UI test
npm run test:ui        # drives a real browser and writes build/screenshots
```

`npm test` runs the same checks as the iOS test target, against the JavaScript port: the
encoding tables against the rules of the standards, check digits against known vectors, and a
round trip through a decoder written separately from the encoder — it reads guards, parity and
element widths the way a scanner does, so a symbol that decodes back to the number it encodes
is evidence that both the tables and the assembly are right.

`npm run test:ui` adds a card through the interface, opens it, and photographs every screen.
Look at those screenshots: a barcode can render wrongly and still pass every assertion an
automated test can make.

## How it is put together

```
PocketPassWeb/
├── index.html      every screen, as plain markup
├── styles.css      one stylesheet, light and dark
├── sw.js           service worker: caches everything so it works offline
├── js/
│   ├── barcode.js  validation, check digits, and the linear encoders
│   ├── render.js   SVG for the linear formats, bwip-js for the rest
│   ├── scanner.js  camera reading, native where possible
│   ├── store.js    cards, settings and backups in localStorage
│   └── app.js      the screens and what the buttons do
├── vendor/         bwip-js and ZXing, committed so the app works offline
└── tests/
```

**Two barcode engines, on purpose.** EAN-13, EAN-8, UPC-A, UPC-E, ITF-14 and Code 39 are
encoded by `js/barcode.js`, ported from the iOS app's Swift and covered by the tests. QR,
Aztec, PDF417 and Code 128 are drawn by bwip-js, which is loaded only when a card actually
needs it — a wallet full of loyalty barcodes never downloads that megabyte.

**Two scanning engines, for the same reason.** Chrome and Android have a native
`BarcodeDetector`. Safari does not, so iOS falls back to ZXing compiled to JavaScript.

**Backups are interchangeable with the iOS app.** Same JSON, same field names, so a file
exported from either one restores into the other.

## What the web cannot do

Worth knowing before you rely on it:

| | iOS app | Web app |
|---|---|---|
| Brighten the screen for a scanner | Automatic | **Impossible.** No web API can set brightness; the app can only ask you to |
| Keep the screen awake | Yes | Yes, on iOS 16.4+ and Android |
| Work offline | Yes | Yes, once loaded |
| Survive not being used for a week | Yes | **Only if installed to the Home Screen** — iOS clears an ordinary site's storage after seven days unused |
| Lock behind Face ID | Yes | Not yet |
| Camera scanning | Fast, native | Works; slower on iOS, which has no native decoder |

The brightness one matters most in practice. A dim phone is the usual reason a till scanner
refuses to read a screen, and on the web that is yours to handle.

## Installing it on a phone

- **iOS:** open the page in Safari, tap Share, then **Add to Home Screen**. This is not
  optional if you want your cards to still be there next month.
- **Android:** the browser offers to install it; the app also shows an Install button.

## Privacy

Cards never leave the device. There is no account, no server and no analytics, and after the
page has loaded the app makes no network requests at all. The camera runs only while the
scanner is open, and frames are decoded on the device. An exported backup is a plain JSON file
containing your barcode numbers — treat it like the cards themselves.
