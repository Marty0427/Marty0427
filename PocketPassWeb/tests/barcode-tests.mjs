// The web app's barcode tests.
//
// These are the same checks the iOS test target makes, against the JavaScript port, plus a
// round trip through a decoder written separately from the encoder: it parses guards, parity
// and element widths the way a scanner does, so a symbol that decodes back to the number it
// encodes is evidence the tables and the assembly are both right.
//
//   node tests/barcode-tests.mjs
import {
  LEFT_ODD, LEFT_EVEN, RIGHT, PARITY, ITF, CODE39, CODE39_ALPHABET,
  encode, normalize, checkDigit, upcAEquivalent, BarcodeError,
} from "../js/barcode.js";

let pass = 0;
const failures = [];
const check = (name, condition, detail = "") => {
  if (condition) { pass++; } else { failures.push(`${name}${detail ? " — " + detail : ""}`); }
};
const bitsOf = (modules) => modules.map((m) => (m ? "1" : "0")).join("");

// ---------------------------------------------------------------- table rules

for (let d = 0; d <= 9; d++) {
  const complement = [...LEFT_ODD[d]].map((c) => (c === "0" ? "1" : "0")).join("");
  check(`R[${d}] is the complement of L[${d}]`, complement === RIGHT[d], `${complement} vs ${RIGHT[d]}`);
  const reversed = [...RIGHT[d]].reverse().join("");
  check(`G[${d}] is R[${d}] reversed`, reversed === LEFT_EVEN[d], `${reversed} vs ${LEFT_EVEN[d]}`);
  const odd = [...LEFT_ODD[d]].filter((c) => c === "1").length;
  check(`L[${d}] has odd parity`, odd % 2 === 1, `${odd} bars`);
  const even = [...LEFT_EVEN[d]].filter((c) => c === "1").length;
  check(`G[${d}] has even parity`, even % 2 === 0, `${even} bars`);
  check(`patterns are 7 modules (${d})`, [LEFT_ODD[d], LEFT_EVEN[d], RIGHT[d]].every((p) => p.length === 7));
}
check("L patterns are unique", new Set(LEFT_ODD).size === 10);
check("G patterns are unique", new Set(LEFT_EVEN).size === 10);
check("R patterns are unique", new Set(RIGHT).size === 10);
check("parity patterns are unique", new Set(PARITY).size === 10);
check("parity patterns are 6 long and start with O",
  PARITY.every((p) => p.length === 6 && p.startsWith("O") && /^[OE]+$/.test(p)));

const runLengths = (pattern) => {
  const runs = [];
  let current = null, length = 0;
  for (const c of pattern) {
    if (c === current) { length++; } else { if (current !== null) runs.push(length); current = c; length = 1; }
  }
  if (current !== null) runs.push(length);
  return runs;
};
for (const [character, pattern] of Object.entries(CODE39)) {
  const runs = runLengths(pattern);
  check(`Code 39 "${character}" is 12 modules`, pattern.length === 12, `${pattern.length}`);
  check(`Code 39 "${character}" has 9 elements`, runs.length === 9, `${runs.length}`);
  check(`Code 39 "${character}" has 3 wide elements`, runs.filter((r) => r === 2).length === 3, runs.join(","));
  check(`Code 39 "${character}" elements are narrow or wide`, runs.every((r) => r === 1 || r === 2));
}
for (const character of CODE39_ALPHABET) {
  check(`Code 39 covers "${character}"`, CODE39[character] !== undefined);
}
ITF.forEach((widths, d) => {
  check(`ITF ${d} has 5 elements`, widths.length === 5);
  check(`ITF ${d} has 2 wide elements`, widths.filter((w) => w === 2).length === 2);
  check(`ITF ${d} sums to 7`, widths.reduce((a, b) => a + b, 0) === 7);
});

// ------------------------------------------------------------- check digits

const gtins = [
  ["590123412345", "7", "ean13"],
  ["9638507", "4", "ean8"],
  ["03600029145", "2", "upcA"],
  ["1540141253220", "2", "itf14"],
  ["000000000000", "0", null],
];
for (const [body, expected] of gtins) {
  check(`check digit of ${body}`, checkDigit(body) === expected, `got ${checkDigit(body)}`);
}
check("EAN-13 completes a missing check digit", normalize("590123412345", "ean13") === "5901234123457");
check("EAN-13 strips spaces", normalize("5901 2341 2345 7", "ean13") === "5901234123457");
check("EAN-13 rejects a wrong check digit", (() => {
  try { normalize("5901234123454", "ean13"); return false; } catch (e) { return e instanceof BarcodeError; }
})());
check("UPC-E 01234565 expands to 012345000065", upcAEquivalent("01234565") === "012345000065");
check("UPC-E 0425261 expands to 042100005264", upcAEquivalent("0425261") === "042100005264");
check("Code 39 uppercases", normalize("member-42", "code39") === "MEMBER-42");
check("Code 39 rejects #", (() => {
  try { normalize("a#b", "code39"); return false; } catch { return true; }
})());

// --------------------------------------------- independent decoders (scanner)

function decodeEAN(modules) {
  const s = bitsOf(modules);
  const digitCount = s.length === 95 ? 13 : s.length === 67 ? 8 : 0;
  if (!digitCount) throw new Error(`unexpected module count ${s.length}`);
  const half = digitCount === 13 ? 6 : 4;
  if (s.slice(0, 3) !== "101") throw new Error("bad start guard");
  if (s.slice(-3) !== "101") throw new Error("bad end guard");
  const centre = 3 + half * 7;
  if (s.slice(centre, centre + 5) !== "01010") throw new Error("bad centre guard");

  let parity = "", digits = "";
  for (let i = 0; i < half; i++) {
    const chunk = s.slice(3 + i * 7, 10 + i * 7);
    const odd = LEFT_ODD.indexOf(chunk);
    const even = LEFT_EVEN.indexOf(chunk);
    if (odd >= 0) { parity += "O"; digits += odd; }
    else if (even >= 0) { parity += "E"; digits += even; }
    else throw new Error(`unknown left pattern ${chunk}`);
  }
  for (let i = 0; i < half; i++) {
    const start = centre + 5 + i * 7;
    const chunk = s.slice(start, start + 7);
    const value = RIGHT.indexOf(chunk);
    if (value < 0) throw new Error(`unknown right pattern ${chunk}`);
    digits += value;
  }
  if (digitCount === 13) {
    const first = PARITY.indexOf(parity);
    if (first < 0) throw new Error(`unknown parity ${parity}`);
    digits = String(first) + digits;
  } else if (parity !== "OOOO") {
    throw new Error(`EAN-8 must be all odd parity, got ${parity}`);
  }
  if (checkDigit(digits.slice(0, -1)) !== digits.slice(-1)) throw new Error("check digit fails");
  return digits;
}

function decodeCode39(modules) {
  const s = bitsOf(modules);
  const lookup = Object.fromEntries(Object.entries(CODE39).map(([k, v]) => [v, k]));
  let out = "";
  for (let i = 0; i < s.length; i += 13) { // 12 modules + 1 separator
    const chunk = s.slice(i, i + 12);
    const character = lookup[chunk];
    if (!character) throw new Error(`unknown pattern ${chunk}`);
    out += character;
    const separator = s.slice(i + 12, i + 13);
    if (separator && separator !== "0") throw new Error("missing inter-character gap");
  }
  if (!out.startsWith("*") || !out.endsWith("*")) throw new Error("missing start/stop");
  return out.slice(1, -1);
}

function decodeITF(modules) {
  const runs = [];
  let current = modules[0], length = 0;
  for (const m of modules) {
    if (m === current) { length++; } else { runs.push({ bar: current, width: length }); current = m; length = 1; }
  }
  runs.push({ bar: current, width: length });

  const start = runs.slice(0, 4);
  if (!start.every((r) => r.width === 1)) throw new Error("bad start pattern");
  const stop = runs.slice(-3);
  if (!(stop[0].width === 2 && stop[1].width === 1 && stop[2].width === 1)) throw new Error("bad stop pattern");

  const body = runs.slice(4, -3);
  if (body.length % 10 !== 0) throw new Error("body is not whole digit pairs");
  const widthsToDigit = (widths) => {
    const index = ITF.findIndex((p) => p.join("") === widths.join(""));
    if (index < 0) throw new Error(`unknown widths ${widths}`);
    return index;
  };
  let digits = "";
  for (let i = 0; i < body.length; i += 10) {
    const chunk = body.slice(i, i + 10);
    const bars = chunk.filter((_, n) => n % 2 === 0).map((r) => r.width);
    const spaces = chunk.filter((_, n) => n % 2 === 1).map((r) => r.width);
    digits += widthsToDigit(bars);
    digits += widthsToDigit(spaces);
  }
  return digits;
}

// ------------------------------------------------------------- round trips

const roundTrips = [
  ["ean13", "5901234123457", decodeEAN, "5901234123457"],
  ["ean13", "0012345678905", decodeEAN, "0012345678905"],
  ["ean13", "9012345678906", decodeEAN, "9012345678906"],
  ["ean13", "4006381333931", decodeEAN, "4006381333931"],
  ["ean8", "96385074", decodeEAN, "96385074"],
  ["upcA", "036000291452", decodeEAN, "0036000291452"],
  ["upcE", "01234565", decodeEAN, "0012345000065"],
  ["code39", "MEMBER-42", decodeCode39, "MEMBER-42"],
  ["code39", "ABC 123.$/+%", decodeCode39, "ABC 123.$/+%"],
  ["itf14", "15401412532202", decodeITF, "15401412532202"],
];
for (const [symbology, input, decoder, expected] of roundTrips) {
  try {
    const { modules } = encode(input, symbology);
    const decoded = decoder(modules);
    check(`round trip ${symbology} ${input}`, decoded === expected, `decoded ${decoded}`);
  } catch (error) {
    check(`round trip ${symbology} ${input}`, false, error.message);
  }
}

// every EAN-13 leading digit, so all ten parity patterns get exercised
for (let first = 0; first <= 9; first++) {
  const body = `${first}01234567890`.slice(0, 12);
  const gtin = body + checkDigit(body);
  try {
    const decoded = decodeEAN(encode(gtin, "ean13").modules);
    check(`round trip EAN-13 starting ${first}`, decoded === gtin, `decoded ${decoded}`);
  } catch (error) {
    check(`round trip EAN-13 starting ${first}`, false, error.message);
  }
}

// ------------------------------------------------------------ module counts

check("EAN-13 is 95 modules", encode("5901234123457", "ean13").modules.length === 95);
check("EAN-8 is 67 modules", encode("96385074", "ean8").modules.length === 67);
check("ITF-14 is 106 modules", encode("15401412532202", "itf14").modules.length === 106);
check("Code 39 'A' is 38 modules", encode("A", "code39").modules.length === 3 * 12 + 2);
check("UPC-A draws the same bars as EAN-13 with a leading zero",
  bitsOf(encode("036000291452", "upcA").modules) === bitsOf(encode("0036000291452", "ean13").modules));
check("UPC-E draws its UPC-A expansion",
  bitsOf(encode("01234565", "upcE").modules) === bitsOf(encode("012345000065", "upcA").modules));

console.log(`${pass} checks passed, ${failures.length} failed`);
if (failures.length) {
  console.log("\nFAILURES:");
  for (const failure of failures) console.log("  - " + failure);
  process.exit(1);
}
