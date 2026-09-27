import { SYMBOLOGIES, encode, humanReadable, isLibraryDrawn, normalize } from "./barcode.js";

const SVG_NS = "http://www.w3.org/2000/svg";
const QUIET_ZONE = 10; // modules each side; EAN needs at least 9

let bwipPromise = null;

/**
 * Loads bwip-js the first time a QR, Aztec, PDF417 or Code 128 card is drawn.
 *
 * It is a megabyte, and a wallet full of loyalty barcodes never needs it, so it is not part
 * of the first paint. The service worker still pre-caches it, so going offline later is fine.
 */
function loadBwip() {
  if (window.bwipjs) return Promise.resolve(window.bwipjs);
  if (bwipPromise) return bwipPromise;

  bwipPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = new URL("../vendor/bwip-js.min.js", import.meta.url).href;
    script.onload = () => (window.bwipjs ? resolve(window.bwipjs) : reject(new Error("bwip-js did not load")));
    script.onerror = () => reject(new Error("bwip-js could not be loaded"));
    document.head.appendChild(script);
  });
  return bwipPromise;
}

/**
 * Draws the linear formats this project encodes itself, as SVG.
 *
 * SVG rather than a bitmap because it stays sharp at any size, and the bars are whole
 * modules in the viewBox, so no rounding can make neighbouring bars different widths.
 */
function drawLinear(payload, symbology) {
  const { modules } = encode(payload, symbology);
  const total = modules.length + QUIET_ZONE * 2;
  const height = Math.round(total / SYMBOLOGIES[symbology].ratio);

  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", `0 0 ${total} ${height}`);
  svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
  svg.setAttribute("shape-rendering", "crispEdges");
  svg.setAttribute("role", "img");

  const background = document.createElementNS(SVG_NS, "rect");
  background.setAttribute("width", String(total));
  background.setAttribute("height", String(height));
  background.setAttribute("fill", "#ffffff");
  svg.appendChild(background);

  // Merge neighbouring bars into one rect, as the iOS renderer does: fewer shapes, and no
  // hairline seam where two rects meet.
  let runStart = null;
  for (let index = 0; index <= modules.length; index++) {
    const isBar = index < modules.length && modules[index];
    if (isBar && runStart === null) {
      runStart = index;
    } else if (!isBar && runStart !== null) {
      const bar = document.createElementNS(SVG_NS, "rect");
      bar.setAttribute("x", String(QUIET_ZONE + runStart));
      bar.setAttribute("y", "0");
      bar.setAttribute("width", String(index - runStart));
      bar.setAttribute("height", String(height));
      bar.setAttribute("fill", "#000000");
      svg.appendChild(bar);
      runStart = null;
    }
  }
  return svg;
}

/** Draws QR, Aztec, PDF417 and Code 128 with bwip-js, onto a canvas. */
async function drawWithLibrary(payload, symbology) {
  const bwipjs = await loadBwip();
  const canvas = document.createElement("canvas");
  const options = {
    bcid: SYMBOLOGIES[symbology].drawnBy,
    text: payload,
    scale: 4,
    includetext: false,
    paddingwidth: 2,
    paddingheight: 2,
    backgroundcolor: "FFFFFF",
  };

  if (symbology === "qr") options.eclevel = "M";
  if (symbology === "code128") options.height = 14;
  if (symbology === "pdf417") options.eclevel = 4;

  bwipjs.toCanvas(canvas, options);
  canvas.classList.add("symbol-canvas");
  return canvas;
}

/**
 * Renders `payload` into `container`, replacing whatever was there.
 *
 * Resolves to the normalised payload — the one actually encoded, which for a card typed in
 * without its check digit is not the string that was passed in.
 */
export async function renderSymbol(container, rawPayload, symbology) {
  const payload = normalize(rawPayload, symbology);

  const symbol = isLibraryDrawn(symbology)
    ? await drawWithLibrary(payload, symbology)
    : drawLinear(payload, symbology);

  symbol.setAttribute?.("aria-label", `${SYMBOLOGIES[symbology].name} for ${payload}`);
  container.replaceChildren(symbol);
  return payload;
}

/**
 * Renders into `container` and writes any failure into it as readable text instead of
 * throwing, for the places where a broken card must not take the screen down with it.
 */
export async function renderSymbolOrMessage(container, rawPayload, symbology) {
  try {
    return await renderSymbol(container, rawPayload, symbology);
  } catch (error) {
    const message = document.createElement("p");
    message.className = "symbol-error";
    message.textContent = error?.message ?? "This code couldn’t be drawn.";
    container.replaceChildren(message);
    return null;
  }
}

export { humanReadable };
