import { COMMON_SYMBOLOGIES, SYMBOLOGIES, humanReadable, normalize, validationError } from "./barcode.js";
import { renderSymbolOrMessage } from "./render.js";
import { cameraIsAvailable, scanImageFile, startScanning } from "./scanner.js";
import {
  CATEGORIES, THEMES, displayName, duplicateOf, filterCards, findCard, isExpired, isExpiringSoon,
  loadCards, loadSettings, makeBackup, makeCard, mergeBackup, readBackup, removeCard, saveCards,
  saveSettings, upsertCard,
} from "./store.js";

const $ = (id) => document.getElementById(id);

const state = {
  cards: loadCards(),
  settings: loadSettings(),
  query: "",
  category: null,
  cardId: null,
  draft: null,
  editingExisting: false,
  scanner: null,
  wakeLock: null,
  installPrompt: null,
};

// MARK: - Shell

const VIEWS = ["wallet", "card", "editor", "scanner", "settings"];
let viewStack = ["wallet"];

function showView(name, { replace = false } = {}) {
  if (!replace && viewStack[viewStack.length - 1] !== name) viewStack.push(name);
  if (replace) viewStack[viewStack.length - 1] = name;

  for (const view of VIEWS) $(`view-${view}`).hidden = view !== name;
  window.scrollTo(0, 0);

  if (name !== "scanner") stopScanner();
  if (name === "card") requestWakeLock();
  else releaseWakeLock();
}

function goBack() {
  viewStack.pop();
  const previous = viewStack[viewStack.length - 1] ?? "wallet";
  viewStack = viewStack.length ? viewStack : ["wallet"];
  showView(previous, { replace: true });
  if (previous === "wallet") renderWallet();
}

let toastTimer = null;
function toast(message) {
  const element = $("toast");
  element.textContent = message;
  element.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (element.hidden = true), 3200);
}

function persist() {
  const failure = saveCards(state.cards);
  if (failure) toast(failure);
}

// MARK: - Wallet

function renderWallet() {
  renderCategoryChips();

  const visible = filterCards(state.cards, state.query, state.category);
  const list = $("card-list");
  list.replaceChildren();

  $("wallet-empty").hidden = state.cards.length > 0;
  $("wallet-no-matches").hidden = !(state.cards.length > 0 && visible.length === 0);

  for (const card of visible) list.appendChild(cardTile(card));
}

function renderCategoryChips() {
  const used = [...new Set(state.cards.map((card) => card.category))];
  const chips = $("category-chips");
  chips.replaceChildren();
  if (used.length < 2) return;

  const addChip = (label, value) => {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "chip";
    chip.textContent = label;
    chip.setAttribute("aria-pressed", String(state.category === value));
    chip.addEventListener("click", () => {
      state.category = state.category === value ? null : value;
      renderWallet();
    });
    chips.appendChild(chip);
  };

  addChip("All", null);
  for (const category of used) addChip(CATEGORIES[category]?.name ?? category, category);
}

function cardTile(card) {
  const [start, end] = THEMES[card.theme] ?? THEMES.graphite;
  const tile = document.createElement("button");
  tile.type = "button";
  tile.className = "card-tile";
  tile.style.background = `linear-gradient(135deg, ${start}, ${end})`;
  tile.addEventListener("click", () => openCard(card.id));

  const info = document.createElement("div");
  info.className = "info";

  const eyebrow = document.createElement("span");
  eyebrow.className = "eyebrow";
  eyebrow.textContent = `${CATEGORIES[card.category]?.icon ?? ""} ${CATEGORIES[card.category]?.name ?? "Other"}`;

  const name = document.createElement("span");
  name.className = "name";
  name.textContent = displayName(card);

  info.append(eyebrow, name);

  if (card.organization) {
    const org = document.createElement("span");
    org.className = "org";
    org.textContent = card.organization;
    info.appendChild(org);
  }

  const badgeText = expiryLabel(card);
  if (badgeText) {
    const badge = document.createElement("span");
    badge.className = "tile-badge";
    badge.textContent = badgeText;
    info.appendChild(badge);
  }

  const right = document.createElement("div");
  right.className = "tile-side";

  if (card.isFavorite) {
    const star = document.createElement("span");
    star.className = "star";
    star.textContent = "★";
    right.appendChild(star);
  }

  const thumb = document.createElement("div");
  thumb.className = "thumb";
  right.appendChild(thumb);
  renderSymbolOrMessage(thumb, card.payload, card.symbology);

  tile.append(info, right);
  tile.setAttribute(
    "aria-label",
    [displayName(card), card.organization, CATEGORIES[card.category]?.name, card.isFavorite ? "Favourite" : null]
      .filter(Boolean)
      .join(", ")
  );
  return tile;
}

function expiryLabel(card) {
  if (isExpired(card)) return "Expired";
  if (isExpiringSoon(card)) {
    return `Expires ${new Date(card.expirationDate).toLocaleDateString(undefined, { day: "numeric", month: "short" })}`;
  }
  return null;
}

// MARK: - Card detail

async function openCard(id) {
  const card = findCard(state.cards, id);
  if (!card) return;

  state.cardId = id;
  showView("card");

  $("card-title").textContent = displayName(card);
  $("card-name").textContent = displayName(card);
  $("card-org").textContent = card.organization;
  $("card-org").hidden = !card.organization;
  $("toggle-favourite").textContent = card.isFavorite ? "★ Favourite" : "☆ Add favourite";

  const badge = $("card-expiry");
  const label = expiryLabel(card);
  badge.hidden = !label;
  badge.textContent = label ?? "";
  badge.classList.toggle("warn", isExpired(card));

  const details = $("card-details");
  details.replaceChildren();
  const addRow = (term, value) => {
    if (!value) return;
    const row = document.createElement("div");
    const dt = document.createElement("dt");
    dt.textContent = term;
    const dd = document.createElement("dd");
    dd.textContent = value;
    row.append(dt, dd);
    details.appendChild(row);
  };
  addRow("Format", SYMBOLOGIES[card.symbology]?.name ?? card.symbology);
  addRow("Category", CATEGORIES[card.category]?.name);
  if (card.expirationDate) addRow("Expires", new Date(card.expirationDate).toLocaleDateString());
  if (card.lastUsedAt) addRow("Last shown", new Date(card.lastUsedAt).toLocaleString());
  addRow("Notes", card.notes);

  const encoded = await renderSymbolOrMessage($("card-symbol"), card.payload, card.symbology);
  $("card-readable").textContent = encoded ? humanReadable(encoded, card.symbology) : "";

  // Showing a card counts as using it, which floats it back to the top of the wallet.
  state.cards = upsertCard(state.cards, { ...card, lastUsedAt: new Date().toISOString() });
  persist();
}

// MARK: - Editor

function openEditor(card) {
  state.editingExisting = Boolean(card);
  state.draft = card
    ? { ...card }
    : makeCard({ payload: "", symbology: "qr", cards: state.cards });

  $("editor-title").textContent = state.editingExisting ? "Edit card" : "New card";
  $("field-payload").value = state.draft.payload;
  $("field-symbology").value = state.draft.symbology;
  $("field-name").value = state.draft.name;
  $("field-organization").value = state.draft.organization;
  $("field-category").value = state.draft.category;
  $("field-favourite").checked = state.draft.isFavorite;
  $("field-notes").value = state.draft.notes;

  const hasExpiry = Boolean(state.draft.expirationDate);
  $("field-has-expiry").checked = hasExpiry;
  $("expiry-field").hidden = !hasExpiry;
  $("field-expiry").value = hasExpiry ? state.draft.expirationDate.slice(0, 10) : "";

  renderThemeGrid();
  showView("editor");
  refreshEditorPreview();
}

function renderThemeGrid() {
  const grid = $("theme-grid");
  grid.replaceChildren();
  for (const [name, [start, end]] of Object.entries(THEMES)) {
    const swatch = document.createElement("button");
    swatch.type = "button";
    swatch.className = "theme-swatch";
    swatch.style.background = `linear-gradient(135deg, ${start}, ${end})`;
    swatch.setAttribute("role", "radio");
    swatch.setAttribute("aria-label", name);
    swatch.setAttribute("aria-checked", String(state.draft?.theme === name));
    swatch.textContent = state.draft?.theme === name ? "✓" : "";
    swatch.addEventListener("click", () => {
      state.draft.theme = name;
      renderThemeGrid();
    });
    grid.appendChild(swatch);
  }
}

async function refreshEditorPreview() {
  const payload = $("field-payload").value;
  const symbology = $("field-symbology").value;
  const note = $("payload-note");

  const problem = payload.trim() ? validationError(payload, symbology) : null;
  note.textContent = problem ?? SYMBOLOGIES[symbology]?.hint ?? "";
  note.classList.toggle("error", Boolean(problem));
  $("save-card").disabled = Boolean(validationError(payload, symbology));

  $("field-payload").inputMode = SYMBOLOGIES[symbology]?.numeric ? "numeric" : "text";

  if (problem || !payload.trim()) {
    $("preview-block").hidden = true;
    return;
  }
  $("preview-block").hidden = false;
  const encoded = await renderSymbolOrMessage($("editor-symbol"), payload, symbology);
  $("editor-readable").textContent = encoded ? humanReadable(encoded, symbology) : "";
}

function saveDraft() {
  const payload = $("field-payload").value;
  const symbology = $("field-symbology").value;

  let normalized;
  try {
    normalized = normalize(payload, symbology);
  } catch (error) {
    toast(error.message);
    return;
  }

  const expiry = $("field-has-expiry").checked && $("field-expiry").value
    ? new Date(`${$("field-expiry").value}T12:00:00`).toISOString()
    : null;

  const card = {
    ...state.draft,
    payload: normalized,
    symbology,
    name: $("field-name").value.trim(),
    organization: $("field-organization").value.trim(),
    category: $("field-category").value,
    isFavorite: $("field-favourite").checked,
    notes: $("field-notes").value.trim(),
    expirationDate: expiry,
  };

  state.cards = upsertCard(state.cards, card);
  persist();
  state.draft = null;

  viewStack = ["wallet"];
  showView("wallet", { replace: true });
  renderWallet();
  toast(state.editingExisting ? "Card updated." : "Card added.");
}

// MARK: - Adding

function openSheet() { $("sheet").hidden = false; }
function closeSheet() { $("sheet").hidden = true; }

function startFromScan({ payload, symbology }) {
  const existing = duplicateOf(state.cards, payload, symbology);
  if (existing) {
    toast(`“${displayName(existing)}” already holds that code.`);
  }
  const card = makeCard({ payload, symbology, cards: state.cards });
  openEditor(card);
  state.editingExisting = false;
  $("editor-title").textContent = "New card";
}

async function openScanner() {
  if (!cameraIsAvailable()) {
    toast("This browser can’t open a camera here. Enter the code by hand instead.");
    return;
  }
  showView("scanner");
  $("scanner-hint").textContent = "Line the card’s code up inside the frame.";

  try {
    state.scanner = await startScanning($("scanner-video"), {
      onResult: (result) => {
        stopScanner();
        goBack();
        startFromScan(result);
      },
      onProblem: (message) => {
        $("scanner-hint").textContent = message;
      },
    });
  } catch (error) {
    goBack();
    toast(
      error?.name === "NotAllowedError"
        ? "Camera access was refused. Allow it in your browser settings, or type the code in."
        : error?.message ?? "The camera could not be started."
    );
  }
}

function stopScanner() {
  state.scanner?.stop();
  state.scanner = null;
}

async function importImage(file) {
  if (!file) return;
  toast("Looking for a code…");
  try {
    const outcome = await scanImageFile(file);
    if (outcome.ok) startFromScan(outcome);
    else toast(outcome.message);
  } catch (error) {
    toast(error?.message ?? "That image could not be read.");
  }
}

// MARK: - Wake lock

async function requestWakeLock() {
  if (!state.settings.keepAwake || !("wakeLock" in navigator)) return;
  try {
    state.wakeLock = await navigator.wakeLock.request("screen");
  } catch {
    /* denied or unsupported; the card still shows */
  }
}

function releaseWakeLock() {
  state.wakeLock?.release?.().catch(() => {});
  state.wakeLock = null;
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && !$("view-card").hidden) requestWakeLock();
});

// MARK: - Backup

async function exportBackup() {
  const text = makeBackup(state.cards);
  const filename = `PocketPass-${new Date().toISOString().slice(0, 10)}.json`;
  const file = new File([text], filename, { type: "application/json" });

  // Sharing is the only route that reliably saves a file on iOS; a download link opens a tab.
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: "PocketPass backup" });
      return;
    } catch (error) {
      if (error?.name === "AbortError") return;
    }
  }

  const url = URL.createObjectURL(file);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

async function importBackup(file) {
  if (!file) return;
  try {
    const incoming = readBackup(await file.text());
    const { cards, added } = mergeBackup(state.cards, incoming);
    state.cards = cards;
    persist();
    renderWallet();
    toast(added ? `Added ${added} card${added === 1 ? "" : "s"}.` : "Every card in that backup was already here.");
  } catch (error) {
    toast(error?.message ?? "That backup could not be read.");
  }
}

// MARK: - Install hint

const isStandalone = () =>
  window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;

function refreshInstallHint() {
  const banner = $("install-hint");
  if (isStandalone() || !state.settings.showInstallHint) {
    banner.hidden = true;
    return;
  }
  const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);
  $("install-hint-text").textContent = state.installPrompt
    ? "It then opens like an app and keeps your cards safely."
    : isIOS
      ? "Tap Share, then “Add to Home Screen”. iOS clears a website’s storage after a week unused — an installed app is exempt."
      : "Use your browser’s menu to install it. Your cards then stay put and it opens like an app.";
  $("install-app").hidden = !state.installPrompt;
  banner.hidden = false;
}

// MARK: - Wiring

function populateSelects() {
  const symbologySelect = $("field-symbology");
  const ordered = [...COMMON_SYMBOLOGIES, ...Object.keys(SYMBOLOGIES).filter((key) => !COMMON_SYMBOLOGIES.includes(key))];
  for (const key of ordered) {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = SYMBOLOGIES[key].name;
    symbologySelect.appendChild(option);
  }

  const categorySelect = $("field-category");
  for (const [key, category] of Object.entries(CATEGORIES)) {
    const option = document.createElement("option");
    option.value = key;
    option.textContent = `${category.icon} ${category.name}`;
    categorySelect.appendChild(option);
  }
}

function wire() {
  for (const button of document.querySelectorAll("[data-back]")) {
    button.addEventListener("click", goBack);
  }

  $("open-add").addEventListener("click", openSheet);
  $("empty-scan").addEventListener("click", () => { closeSheet(); openScanner(); });
  $("empty-manual").addEventListener("click", () => { closeSheet(); openEditor(null); });
  $("action-scan").addEventListener("click", () => { closeSheet(); openScanner(); });
  $("action-manual").addEventListener("click", () => { closeSheet(); openEditor(null); });
  $("action-cancel").addEventListener("click", closeSheet);
  $("sheet").addEventListener("click", (event) => { if (event.target === $("sheet")) closeSheet(); });
  $("import-image").addEventListener("change", (event) => {
    closeSheet();
    importImage(event.target.files?.[0]);
    event.target.value = "";
  });

  $("search").addEventListener("input", (event) => {
    state.query = event.target.value;
    renderWallet();
  });

  $("open-settings").addEventListener("click", () => {
    $("setting-keep-awake").checked = state.settings.keepAwake;
    $("storage-note").textContent = `${state.cards.length} card${state.cards.length === 1 ? "" : "s"} stored in this browser. The backup is a readable JSON file — anyone who opens it can read the codes.`;
    showView("settings");
  });

  $("setting-keep-awake").addEventListener("change", (event) => {
    state.settings = { ...state.settings, keepAwake: event.target.checked };
    saveSettings(state.settings);
  });

  $("export-backup").addEventListener("click", exportBackup);
  $("import-backup").addEventListener("change", (event) => {
    importBackup(event.target.files?.[0]);
    event.target.value = "";
  });

  $("field-payload").addEventListener("input", refreshEditorPreview);
  $("field-symbology").addEventListener("change", refreshEditorPreview);
  $("field-has-expiry").addEventListener("change", (event) => {
    $("expiry-field").hidden = !event.target.checked;
  });
  $("editor-form").addEventListener("submit", (event) => { event.preventDefault(); saveDraft(); });
  $("save-card").addEventListener("click", saveDraft);

  $("copy-code").addEventListener("click", async () => {
    const card = findCard(state.cards, state.cardId);
    if (!card) return;
    try {
      await navigator.clipboard.writeText(card.payload);
      toast("Code copied.");
    } catch {
      toast("This browser would not let the page copy.");
    }
  });

  $("toggle-favourite").addEventListener("click", () => {
    const card = findCard(state.cards, state.cardId);
    if (!card) return;
    state.cards = upsertCard(state.cards, { ...card, isFavorite: !card.isFavorite });
    persist();
    openCard(card.id);
  });

  $("edit-card").addEventListener("click", () => {
    const card = findCard(state.cards, state.cardId);
    if (card) openEditor(card);
  });

  $("delete-card").addEventListener("click", () => {
    const card = findCard(state.cards, state.cardId);
    if (!card) return;
    if (!window.confirm(`Delete “${displayName(card)}”? This cannot be undone.`)) return;
    state.cards = removeCard(state.cards, card.id);
    persist();
    viewStack = ["wallet"];
    showView("wallet", { replace: true });
    renderWallet();
    toast("Card deleted.");
  });

  $("card-menu-button").addEventListener("click", () => {
    document.querySelector("#view-card .card-body").scrollIntoView({ behavior: "smooth", block: "end" });
  });

  $("dismiss-install").addEventListener("click", () => {
    state.settings = { ...state.settings, showInstallHint: false };
    saveSettings(state.settings);
    refreshInstallHint();
  });

  $("install-app").addEventListener("click", async () => {
    if (!state.installPrompt) return;
    state.installPrompt.prompt();
    await state.installPrompt.userChoice;
    state.installPrompt = null;
    refreshInstallHint();
  });

  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    state.installPrompt = event;
    refreshInstallHint();
  });

  window.addEventListener("pagehide", stopScanner);
}

function registerServiceWorker() {
  if (!("serviceWorker" in navigator) || !window.isSecureContext) return;
  window.addEventListener("load", () => {
    navigator.serviceWorker.register(new URL("../sw.js", import.meta.url), { scope: "./" }).catch(() => {
      /* offline support is a bonus, not a requirement */
    });
  });
}

populateSelects();
wire();
renderWallet();
refreshInstallHint();
registerServiceWorker();
$("version-note").textContent = "PocketPass for the web · version 1.0";
