import { SYMBOLOGIES, normalize } from "./barcode.js";

/**
 * Reading barcodes from the camera.
 *
 * Two engines, because the platforms differ: Chrome and Android have a native
 * `BarcodeDetector`, which is fast and costs nothing to ship. Safari does not, so iOS falls
 * back to ZXing compiled to JavaScript — slower, and the reason the megabyte of vendor code
 * exists. Whichever runs, the result goes through the same mapping and validation as a scan
 * on iOS.
 */

/** Native `BarcodeDetector` names, mapped to our formats. */
const NATIVE_FORMATS = {
  qr_code: "qr",
  aztec: "aztec",
  pdf417: "pdf417",
  code_128: "code128",
  code_39: "code39",
  ean_13: "ean13",
  ean_8: "ean8",
  upc_a: "upcA",
  upc_e: "upcE",
  itf: "itf14",
};

/** ZXing's `BarcodeFormat` names, mapped to our formats. */
const ZXING_FORMATS = {
  QR_CODE: "qr",
  AZTEC: "aztec",
  PDF_417: "pdf417",
  CODE_128: "code128",
  CODE_39: "code39",
  EAN_13: "ean13",
  EAN_8: "ean8",
  UPC_A: "upcA",
  UPC_E: "upcE",
  ITF: "itf14",
};

let zxingPromise = null;

function loadZXing() {
  if (window.ZXing) return Promise.resolve(window.ZXing);
  if (zxingPromise) return zxingPromise;

  zxingPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = new URL("../vendor/zxing.min.js", import.meta.url).href;
    script.onload = () => (window.ZXing ? resolve(window.ZXing) : reject(new Error("ZXing did not load")));
    script.onerror = () => reject(new Error("The scanner library could not be loaded."));
    document.head.appendChild(script);
  });
  return zxingPromise;
}

/**
 * Both scanners report UPC-A as a 13 digit EAN-13 with a leading zero. The card itself is
 * printed with 12 digits, so it is stored that way — the same rule the iOS app applies.
 */
export function resolveScan(payload, symbology) {
  if (symbology === "ean13" && payload.length === 13 && payload.startsWith("0") && /^\d+$/.test(payload)) {
    return { payload: payload.slice(1), symbology: "upcA" };
  }
  return { payload, symbology };
}

/**
 * Turns a raw read into something storable, or explains why it is not.
 * @returns {{ok: true, payload: string, symbology: string} | {ok: false, message: string}}
 */
export function interpretScan(rawPayload, rawSymbology) {
  if (!rawSymbology) {
    return { ok: false, message: "That barcode format can’t be stored yet." };
  }
  const resolved = resolveScan(rawPayload, rawSymbology);
  try {
    return { ok: true, payload: normalize(resolved.payload, resolved.symbology), symbology: resolved.symbology };
  } catch (error) {
    return { ok: false, message: error?.message ?? "That code couldn’t be read." };
  }
}

/** `true` when this browser can open a camera at all. */
export const cameraIsAvailable = () =>
  Boolean(navigator.mediaDevices?.getUserMedia) && window.isSecureContext;

/**
 * Starts the camera and calls `onResult` once, for the first code that can be stored.
 * Returns a handle whose `stop()` releases the camera — always call it.
 */
export async function startScanning(video, { onResult, onProblem }) {
  if (!window.isSecureContext) {
    throw new Error("The camera needs a secure connection. Open this page over https.");
  }
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error("This browser cannot open a camera.");
  }

  const stream = await navigator.mediaDevices.getUserMedia({
    video: { facingMode: { ideal: "environment" }, width: { ideal: 1280 }, height: { ideal: 720 } },
    audio: false,
  });

  video.srcObject = stream;
  video.setAttribute("playsinline", "true"); // without this iOS takes the video fullscreen
  video.muted = true;
  await video.play().catch(() => {});

  let stopped = false;
  let zxingReader = null;
  let frameTimer = null;

  const stop = () => {
    if (stopped) return;
    stopped = true;
    if (frameTimer) clearInterval(frameTimer);
    try {
      zxingReader?.reset();
    } catch {
      /* the reader is going away regardless */
    }
    for (const track of stream.getTracks()) track.stop();
    video.srcObject = null;
  };

  // One code at a time: the caller decides whether scanning continues.
  const deliver = (rawPayload, symbology) => {
    if (stopped || !rawPayload) return;
    const outcome = interpretScan(rawPayload, symbology);
    if (outcome.ok) {
      stop();
      onResult(outcome);
    } else {
      onProblem?.(outcome.message);
    }
  };

  if ("BarcodeDetector" in window) {
    const supported = await window.BarcodeDetector.getSupportedFormats();
    const formats = Object.keys(NATIVE_FORMATS).filter((format) => supported.includes(format));
    const detector = new window.BarcodeDetector({ formats });

    frameTimer = setInterval(async () => {
      if (stopped || video.readyState < 2) return;
      try {
        const [found] = await detector.detect(video);
        if (found) deliver(found.rawValue, NATIVE_FORMATS[found.format]);
      } catch {
        /* a dropped frame is not worth reporting */
      }
    }, 250);

    return { stop, engine: "BarcodeDetector" };
  }

  const ZXing = await loadZXing();
  const hints = new Map();
  hints.set(
    ZXing.DecodeHintType.POSSIBLE_FORMATS,
    Object.keys(ZXING_FORMATS).map((name) => ZXing.BarcodeFormat[name]).filter((value) => value !== undefined)
  );

  zxingReader = new ZXing.BrowserMultiFormatReader(hints, { delayBetweenScanAttempts: 200 });
  zxingReader.decodeFromStream(stream, video, (result, error) => {
    if (stopped || !result) return;
    const format = ZXing.BarcodeFormat[result.getBarcodeFormat()];
    deliver(result.getText(), ZXING_FORMATS[format]);
  });

  return { stop, engine: "ZXing" };
}

/** Finds a barcode in a still image, for importing a screenshot. */
export async function scanImageFile(file) {
  const url = URL.createObjectURL(file);
  try {
    if ("BarcodeDetector" in window) {
      const supported = await window.BarcodeDetector.getSupportedFormats();
      const formats = Object.keys(NATIVE_FORMATS).filter((format) => supported.includes(format));
      const detector = new window.BarcodeDetector({ formats });
      const bitmap = await createImageBitmap(file);
      const [found] = await detector.detect(bitmap);
      bitmap.close?.();
      if (found) return interpretScan(found.rawValue, NATIVE_FORMATS[found.format]);
      return { ok: false, message: "No barcode was found in that image." };
    }

    const ZXing = await loadZXing();
    const reader = new ZXing.BrowserMultiFormatReader();
    try {
      const result = await reader.decodeFromImageUrl(url);
      const format = ZXing.BarcodeFormat[result.getBarcodeFormat()];
      return interpretScan(result.getText(), ZXING_FORMATS[format]);
    } catch {
      return { ok: false, message: "No barcode was found in that image." };
    } finally {
      reader.reset();
    }
  } finally {
    URL.revokeObjectURL(url);
  }
}

export { SYMBOLOGIES };
