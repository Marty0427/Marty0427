// JavaScript port of PocketPass's LinearBarcodeEncoder + BarcodeValidator.
// Ported line by line from the Swift so that testing this tests that.

export const LEFT_ODD = [
  "0001101", "0011001", "0010011", "0111101", "0100011",
  "0110001", "0101111", "0111011", "0110111", "0001011",
];
export const LEFT_EVEN = [
  "0100111", "0110011", "0011011", "0100001", "0011101",
  "0111001", "0000101", "0010001", "0001001", "0010111",
];
export const RIGHT = [
  "1110010", "1100110", "1101100", "1000010", "1011100",
  "1001110", "1010000", "1000100", "1001000", "1110100",
];
export const PARITY = [
  "OOOOOO", "OOEOEE", "OOEEOE", "OOEEEO", "OEOOEE",
  "OEEOOE", "OEEEOO", "OEOEOE", "OEOEEO", "OEEOEO",
];
export const ITF = [
  [1, 1, 2, 2, 1], [2, 1, 1, 1, 2], [1, 2, 1, 1, 2], [2, 2, 1, 1, 1], [1, 1, 2, 1, 2],
  [2, 1, 2, 1, 1], [1, 2, 2, 1, 1], [1, 1, 1, 2, 2], [2, 1, 1, 2, 1], [1, 2, 1, 2, 1],
];
export const CODE39 = {
  "0": "101001101101", "1": "110100101011", "2": "101100101011", "3": "110110010101",
  "4": "101001101011", "5": "110100110101", "6": "101100110101", "7": "101001011011",
  "8": "110100101101", "9": "101100101101", "A": "110101001011", "B": "101101001011",
  "C": "110110100101", "D": "101011001011", "E": "110101100101", "F": "101101100101",
  "G": "101010011011", "H": "110101001101", "I": "101101001101", "J": "101011001101",
  "K": "110101010011", "L": "101101010011", "M": "110110101001", "N": "101011010011",
  "O": "110101101001", "P": "101101101001", "Q": "101010110011", "R": "110101011001",
  "S": "101101011001", "T": "101011011001", "U": "110010101011", "V": "100110101011",
  "W": "110011010101", "X": "100101101011", "Y": "110010110101", "Z": "100110110101",
  "-": "100101011011", ".": "110010101101", " ": "100110101101", "$": "100100100101",
  "/": "100100101001", "+": "100101001001", "%": "101001001001", "*": "100101101101",
};
export const CODE39_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%";

const NORMAL_GUARD = "101";
const CENTER_GUARD = "01010";

export const SYMBOLOGIES = {
  qr:     { name: "QR Code", hint: "Loyalty apps, tickets, links", digits: [], numeric: false, ratio: 1,   max: 1200, drawnBy: "qrcode" },
  aztec:  { name: "Aztec",   hint: "Boarding passes and rail tickets", digits: [], numeric: false, ratio: 1,   max: 1000, drawnBy: "azteccode" },
  pdf417: { name: "PDF417",  hint: "Boarding passes and IDs", digits: [], numeric: false, ratio: 2.6, max: 1100, drawnBy: "pdf417" },
  code128:{ name: "Code 128", hint: "Membership and shipping labels", digits: [], numeric: false, ratio: 2.4, max: 80, drawnBy: "code128" },
  code39: { name: "Code 39", hint: "Badges and older memberships", digits: [], numeric: false, ratio: 2.4, max: 40, drawnBy: null },
  ean13:  { name: "EAN-13",  hint: "Retail loyalty cards (13 digits)", digits: [12, 13], numeric: true, ratio: 1.9, max: 14, drawnBy: null },
  ean8:   { name: "EAN-8",   hint: "Short retail codes (8 digits)", digits: [7, 8], numeric: true, ratio: 1.6, max: 14, drawnBy: null },
  upcA:   { name: "UPC-A",   hint: "North American retail (12 digits)", digits: [11, 12], numeric: true, ratio: 1.9, max: 14, drawnBy: null },
  upcE:   { name: "UPC-E",   hint: "Compressed UPC (6-8 digits)", digits: [6, 7, 8], numeric: true, ratio: 1.6, max: 14, drawnBy: null },
  itf14:  { name: "ITF-14",  hint: "Cartons and wholesale cards", digits: [13, 14], numeric: true, ratio: 2.4, max: 14, drawnBy: null },
};

/** Formats offered first in the editor, because they cover most wallets. */
export const COMMON_SYMBOLOGIES = ["qr", "aztec", "pdf417", "code128", "ean13", "code39"];

/** `true` when a library draws it rather than {@link encode}. */
export const isLibraryDrawn = (symbology) => Boolean(SYMBOLOGIES[symbology]?.drawnBy);

export class BarcodeError extends Error {}

// The GS1 modulo-10 check digit shared by EAN-8, EAN-13, UPC-A and ITF-14.
export function checkDigit(body) {
  let sum = 0;
  const reversed = [...body].reverse();
  for (let i = 0; i < reversed.length; i++) {
    const value = Number(reversed[i]);
    sum += i % 2 === 0 ? value * 3 : value;
  }
  return String((10 - (sum % 10)) % 10);
}

function completeGTIN(digits, fullLength, accepted) {
  if (digits.length === fullLength - 1) return digits + checkDigit(digits);
  if (digits.length === fullLength) {
    const expected = checkDigit(digits.slice(0, -1));
    if (digits.slice(-1) !== expected) {
      throw new BarcodeError(`The last digit should be ${expected}. Check the number and try again.`);
    }
    return digits;
  }
  throw new BarcodeError(`This format needs ${accepted.join(" or ")} digits.`);
}

function expandUPCEBody(body) {
  if (body.length !== 7) throw new BarcodeError("This format needs 6, 7 or 8 digits.");
  const system = body[0];
  const x = body.slice(1);
  switch (x[5]) {
    case "0": case "1": case "2":
      return `${system}${x[0]}${x[1]}${x[5]}0000${x[2]}${x[3]}${x[4]}`;
    case "3":
      return `${system}${x[0]}${x[1]}${x[2]}00000${x[3]}${x[4]}`;
    case "4":
      return `${system}${x[0]}${x[1]}${x[2]}${x[3]}00000${x[4]}`;
    default:
      return `${system}${x[0]}${x[1]}${x[2]}${x[3]}${x[4]}0000${x[5]}`;
  }
}

function normalizeUPCE(digits) {
  const accepted = SYMBOLOGIES.upcE.digits;
  if (digits.length === 6) {
    const body = "0" + digits;
    return body + checkDigit(expandUPCEBody(body));
  }
  if (digits.length === 7) {
    if (digits[0] !== "0" && digits[0] !== "1") {
      throw new BarcodeError(`This format needs ${accepted.join(" or ")} digits.`);
    }
    return digits + checkDigit(expandUPCEBody(digits));
  }
  if (digits.length === 8) {
    const body = digits.slice(0, 7);
    if (body[0] !== "0" && body[0] !== "1") {
      throw new BarcodeError(`This format needs ${accepted.join(" or ")} digits.`);
    }
    const expected = checkDigit(expandUPCEBody(body));
    if (digits.slice(-1) !== expected) {
      throw new BarcodeError(`The last digit should be ${expected}. Check the number and try again.`);
    }
    return digits;
  }
  throw new BarcodeError(`This format needs ${accepted.join(" or ")} digits.`);
}

export function upcAEquivalent(payload) {
  const normalized = normalizeUPCE(payload);
  const expanded = expandUPCEBody(normalized.slice(0, 7));
  return expanded + checkDigit(expanded);
}

export function normalize(raw, symbology) {
  const trimmed = String(raw).trim();
  if (!trimmed) throw new BarcodeError("Enter the code printed on the card.");

  const spec = SYMBOLOGIES[symbology];
  if (!spec) throw new BarcodeError("Unknown format.");

  if (!spec.numeric) {
    if (trimmed.length > spec.max) {
      throw new BarcodeError(`This format holds at most ${spec.max} characters.`);
    }
    if (symbology === "code39") {
      const uppercased = trimmed.toUpperCase();
      for (const character of uppercased) {
        if (!CODE39_ALPHABET.includes(character)) {
          throw new BarcodeError(`“${character}” can’t be encoded in this format.`);
        }
      }
      return uppercased;
    }
    if (symbology === "code128") {
      // eslint-disable-next-line no-control-regex
      if (/[^\x00-\x7F]/.test(trimmed)) {
        throw new BarcodeError("Code 128 needs plain ASCII characters.");
      }
    }
    return trimmed;
  }

  // Printed numbers are routinely spaced or hyphenated; those separators carry no data.
  const digits = [...trimmed].filter((c) => !" -–—".includes(c)).join("");
  if (!/^[0-9]+$/.test(digits)) throw new BarcodeError("This format only accepts digits.");

  switch (symbology) {
    case "ean13": return completeGTIN(digits, 13, spec.digits);
    case "ean8":  return completeGTIN(digits, 8, spec.digits);
    case "upcA":  return completeGTIN(digits, 12, spec.digits);
    case "itf14": return completeGTIN(digits, 14, spec.digits);
    case "upcE":  return normalizeUPCE(digits);
    default:      return digits;
  }
}

/** The validation error for a payload, or `null` when it is usable. */
export function validationError(raw, symbology) {
  try {
    normalize(raw, symbology);
    return null;
  } catch (error) {
    return error instanceof BarcodeError ? error.message : "That code can’t be encoded.";
  }
}

/** Digits printed under the symbol: grouped for numeric formats, raw otherwise. */
export function humanReadable(payload, symbology) {
  if (!SYMBOLOGIES[symbology]?.numeric) return payload;
  return payload.replace(/(.{4})/g, "$1 ").trim();
}

const bits = (s) => [...s].map((c) => c === "1");

function encodeEAN13(payload) {
  const d = [...payload].map(Number);
  if (d.length !== 13) throw new BarcodeError("This format needs 13 digits.");
  const parity = PARITY[d[0]];
  let out = NORMAL_GUARD;
  for (let i = 1; i <= 6; i++) out += parity[i - 1] === "O" ? LEFT_ODD[d[i]] : LEFT_EVEN[d[i]];
  out += CENTER_GUARD;
  for (let i = 7; i <= 12; i++) out += RIGHT[d[i]];
  out += NORMAL_GUARD;
  return bits(out);
}

function encodeEAN8(payload) {
  const d = [...payload].map(Number);
  if (d.length !== 8) throw new BarcodeError("This format needs 8 digits.");
  let out = NORMAL_GUARD;
  for (let i = 0; i <= 3; i++) out += LEFT_ODD[d[i]];
  out += CENTER_GUARD;
  for (let i = 4; i <= 7; i++) out += RIGHT[d[i]];
  out += NORMAL_GUARD;
  return bits(out);
}

function encodeITF(payload) {
  const d = [...payload].map(Number);
  if (d.length % 2 !== 0) throw new BarcodeError("This format needs an even number of digits.");
  const modules = [true, false, true, false]; // start: narrow bar, space, bar, space
  for (let pair = 0; pair < d.length; pair += 2) {
    const bars = ITF[d[pair]];
    const spaces = ITF[d[pair + 1]];
    for (let e = 0; e < 5; e++) {
      for (let i = 0; i < bars[e]; i++) modules.push(true);
      for (let i = 0; i < spaces[e]; i++) modules.push(false);
    }
  }
  modules.push(true, true, false, true); // stop: wide bar, narrow space, narrow bar
  return modules;
}

function encodeCode39(payload) {
  const characters = [..."*" + payload.toUpperCase() + "*"];
  let out = "";
  characters.forEach((character, index) => {
    const pattern = CODE39[character];
    if (!pattern) throw new BarcodeError(`“${character}” can’t be encoded in this format.`);
    out += pattern;
    if (index < characters.length - 1) out += "0"; // one narrow space between characters
  });
  return bits(out);
}

export function encode(rawPayload, symbology) {
  const payload = normalize(rawPayload, symbology);
  switch (symbology) {
    case "ean13": return { modules: encodeEAN13(payload), humanReadable: payload };
    case "upcA": return { modules: encodeEAN13("0" + payload), humanReadable: payload };
    case "upcE": return { modules: encodeEAN13("0" + upcAEquivalent(payload)), humanReadable: payload };
    case "ean8": return { modules: encodeEAN8(payload), humanReadable: payload };
    case "itf14": return { modules: encodeITF(payload), humanReadable: payload };
    case "code39": return { modules: encodeCode39(payload), humanReadable: payload };
    default: throw new BarcodeError(`${SYMBOLOGIES[symbology]?.name ?? symbology} is drawn by bwip-js, not here.`);
  }
}
