# Vendored libraries

Committed rather than loaded from a CDN, so the app works offline and does not depend on a
third party staying up.

| File | Package | Version | Licence | Used for |
|---|---|---|---|---|
| `bwip-js.min.js` | [bwip-js](https://github.com/metafloor/bwip-js) | 4.11.4 | MIT | Drawing QR, Aztec, PDF417 and Code 128 |
| `zxing.min.js` | [@zxing/library](https://github.com/zxing-js/library) | 0.21.3 | MIT | Reading barcodes from the camera where `BarcodeDetector` is missing (Safari) |

EAN-13, EAN-8, UPC-A, UPC-E, ITF-14 and Code 39 are **not** drawn by a library: they use
`js/barcode.js`, ported from the iOS app's Swift and covered by the tests in `tests.html`.

To update either library:

```sh
npm install bwip-js @zxing/library
cp node_modules/bwip-js/dist/bwip-js-min.js PocketPassWeb/vendor/bwip-js.min.js
cp node_modules/@zxing/library/umd/index.min.js PocketPassWeb/vendor/zxing.min.js
```
