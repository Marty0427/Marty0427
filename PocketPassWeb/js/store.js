/**
 * The wallet, kept in this browser.
 *
 * The stored shape is deliberately identical to the iOS app's backup file, so an export from
 * either one restores into the other.
 *
 * On iOS, a site's storage is cleared after seven days of not being used — unless the site
 * has been added to the Home Screen, which is exempt. That is why the app nags about
 * installing, and why Export Backup is not an afterthought.
 */

const CARDS_KEY = "pocketpass.cards";
const SETTINGS_KEY = "pocketpass.settings";
const BACKUP_VERSION = 1;

export const CATEGORIES = {
  loyalty: { name: "Loyalty", icon: "🛒", defaultSymbology: "code128" },
  boardingPass: { name: "Boarding Pass", icon: "✈️", defaultSymbology: "aztec" },
  eventTicket: { name: "Event Ticket", icon: "🎟️", defaultSymbology: "qr" },
  transit: { name: "Transit", icon: "🚆", defaultSymbology: "qr" },
  membership: { name: "Membership", icon: "💳", defaultSymbology: "qr" },
  giftCard: { name: "Gift Card", icon: "🎁", defaultSymbology: "code128" },
  coupon: { name: "Coupon", icon: "🏷️", defaultSymbology: "qr" },
  identification: { name: "ID", icon: "🪪", defaultSymbology: "qr" },
  other: { name: "Other", icon: "▫️", defaultSymbology: "qr" },
};

export const THEMES = {
  graphite: ["#3A3A3C", "#1C1C1E"],
  ocean: ["#1B6CA8", "#0C3D63"],
  forest: ["#2E7D4F", "#14532D"],
  sunset: ["#E4572E", "#9B2226"],
  berry: ["#C2185B", "#7B1140"],
  sand: ["#C8922E", "#8A5A16"],
  plum: ["#6D3B9E", "#3F2069"],
  slate: ["#4A6572", "#233640"],
};

const THEME_NAMES = Object.keys(THEMES);

/** Storage can throw in private mode or when the quota is gone; never take the app down. */
function readJSON(key, fallback) {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function writeJSON(key, value) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
    return null;
  } catch (error) {
    return error?.name === "QuotaExceededError"
      ? "There is no room left in this browser's storage."
      : "This browser refused to save. Private browsing blocks storage.";
  }
}

const newId = () =>
  (crypto.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(16).slice(2)}`).toUpperCase();

/** Fills in anything a hand-edited or newer backup left out, so one odd card cannot kill a restore. */
function reviveCard(raw) {
  if (!raw || typeof raw.payload !== "string" || !raw.payload) return null;
  const now = new Date().toISOString();
  return {
    id: typeof raw.id === "string" && raw.id ? raw.id : newId(),
    name: raw.name ?? "",
    organization: raw.organization ?? "",
    payload: raw.payload,
    symbology: raw.symbology ?? "qr",
    category: CATEGORIES[raw.category] ? raw.category : "other",
    theme: THEMES[raw.theme] ? raw.theme : "graphite",
    notes: raw.notes ?? "",
    isFavorite: Boolean(raw.isFavorite),
    expirationDate: raw.expirationDate ?? null,
    createdAt: raw.createdAt ?? now,
    updatedAt: raw.updatedAt ?? raw.createdAt ?? now,
    lastUsedAt: raw.lastUsedAt ?? null,
  };
}

/** Favourites first, then most recently shown, then alphabetical — as on iOS. */
function sortCards(cards) {
  return [...cards].sort((a, b) => {
    if (a.isFavorite !== b.isFavorite) return a.isFavorite ? -1 : 1;
    if (a.lastUsedAt && b.lastUsedAt && a.lastUsedAt !== b.lastUsedAt) {
      return a.lastUsedAt < b.lastUsedAt ? 1 : -1;
    }
    if (a.lastUsedAt && !b.lastUsedAt) return -1;
    if (!a.lastUsedAt && b.lastUsedAt) return 1;
    return displayName(a).localeCompare(displayName(b), undefined, { sensitivity: "base" });
  });
}

export const displayName = (card) => (card.name?.trim() ? card.name.trim() : "Untitled card");

export function loadCards() {
  const stored = readJSON(CARDS_KEY, []);
  return sortCards((Array.isArray(stored) ? stored : []).map(reviveCard).filter(Boolean));
}

export function saveCards(cards) {
  return writeJSON(CARDS_KEY, sortCards(cards));
}

export function upsertCard(cards, card) {
  const now = new Date().toISOString();
  const index = cards.findIndex((existing) => existing.id === card.id);
  const merged = { ...card, updatedAt: now };
  if (index === -1) return sortCards([...cards, { ...merged, createdAt: merged.createdAt ?? now }]);
  const copy = [...cards];
  copy[index] = merged;
  return sortCards(copy);
}

export const removeCard = (cards, id) => cards.filter((card) => card.id !== id);

export const findCard = (cards, id) => cards.find((card) => card.id === id) ?? null;

/** Same code in the same format is the same card, whatever it is called. */
export const duplicateOf = (cards, payload, symbology) =>
  cards.find((card) => card.payload === payload && card.symbology === symbology) ?? null;

export function filterCards(cards, query = "", category = null) {
  const needle = query.trim().toLowerCase();
  return cards.filter((card) => {
    if (category && card.category !== category) return false;
    if (!needle) return true;
    return [card.name, card.organization, card.notes, card.payload, CATEGORIES[card.category]?.name]
      .filter(Boolean)
      .join("\n")
      .toLowerCase()
      .includes(needle);
  });
}

export function makeCard({ payload, symbology, cards = [] }) {
  const category = "loyalty";
  return {
    id: newId(),
    name: "",
    organization: "",
    payload,
    symbology,
    category,
    theme: THEME_NAMES[Math.abs(cards.length) % THEME_NAMES.length],
    notes: "",
    isFavorite: false,
    expirationDate: null,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    lastUsedAt: null,
  };
}

export const isExpired = (card, now = new Date()) =>
  Boolean(card.expirationDate) && new Date(card.expirationDate) < now;

export function isExpiringSoon(card, now = new Date(), days = 7) {
  if (!card.expirationDate) return false;
  const expiry = new Date(card.expirationDate);
  if (expiry < now) return false;
  return expiry - now <= days * 24 * 60 * 60 * 1000;
}

// MARK: - Settings

const DEFAULT_SETTINGS = { keepAwake: true, showInstallHint: true };

export const loadSettings = () => ({ ...DEFAULT_SETTINGS, ...readJSON(SETTINGS_KEY, {}) });
export const saveSettings = (settings) => writeJSON(SETTINGS_KEY, settings);

// MARK: - Backup

export function makeBackup(cards) {
  return JSON.stringify(
    { version: BACKUP_VERSION, exportedAt: new Date().toISOString(), cards },
    null,
    2
  );
}

/** Accepts the envelope the iOS app writes, and a bare array of cards. */
export function readBackup(text) {
  const parsed = JSON.parse(text);
  const list = Array.isArray(parsed) ? parsed : parsed?.cards;
  if (!Array.isArray(list)) throw new Error("That file does not contain any cards.");
  const cards = list.map(reviveCard).filter(Boolean);
  if (!cards.length) throw new Error("That file does not contain any cards.");
  return cards;
}

/** Adds the cards that are genuinely new, leaving what is already stored alone. */
export function mergeBackup(cards, incoming) {
  let added = 0;
  let merged = [...cards];
  for (const candidate of incoming) {
    if (duplicateOf(merged, candidate.payload, candidate.symbology)) continue;
    const card = merged.some((existing) => existing.id === candidate.id)
      ? { ...candidate, id: newId() }
      : candidate;
    merged = [...merged, card];
    added += 1;
  }
  return { cards: sortCards(merged), added };
}
