/**
 * End-to-end test: drives the app in a real browser and photographs each screen.
 *
 * It serves the app itself and picks its own port, so there is nothing to start first:
 *
 *   node tests/ui-tests.mjs                 # headless, writes build/screenshots
 *   PLAYWRIGHT_CHROMIUM=/path/to/chrome node tests/ui-tests.mjs
 *
 * Screenshots are a deliberate output, not a side effect: a barcode that renders wrongly
 * still passes every assertion an automated test can make, so somebody has to look.
 */

import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { stat, mkdir } from "node:fs/promises";
import { extname, join, normalize, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SHOTS = join(ROOT, "build", "screenshots");

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

function serve() {
  const server = createServer(async (request, response) => {
    const path = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
    const relative = normalize(path === "/" ? "/index.html" : path).replace(/^(\.\.[/\\])+/, "");
    const file = join(ROOT, relative);
    try {
      const info = await stat(file);
      if (!info.isFile()) throw new Error("not a file");
      response.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" });
      createReadStream(file).pipe(response);
    } catch {
      response.writeHead(404).end("not found");
    }
  });
  return new Promise((resolve) => {
    // Port 0 lets the OS pick a free one, so parallel runs never collide.
    server.listen(0, "127.0.0.1", () => resolve({ server, port: server.address().port }));
  });
}

const failures = [];
const check = (label, condition, detail = "") => {
  console.log(`${condition ? "  ok  " : " FAIL "} ${label}${detail ? ` — ${detail}` : ""}`);
  if (!condition) failures.push(label);
};

const { server, port } = await serve();
await mkdir(SHOTS, { recursive: true });

const browser = await chromium.launch(
  process.env.PLAYWRIGHT_CHROMIUM ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM } : {}
);
const context = await browser.newContext({
  viewport: { width: 430, height: 932 },
  deviceScaleFactor: 3,
  isMobile: true,
  hasTouch: true,
});
const page = await context.newPage();

const pageProblems = [];
page.on("pageerror", (error) => pageProblems.push(`pageerror: ${error.message}`));
page.on("console", (message) => {
  if (message.type() === "error") pageProblems.push(`console: ${message.text()}`);
});

try {
  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: "networkidle" });

  check("the empty wallet is shown first", await page.isVisible("#wallet-empty"));

  const addCard = async ({ code, format, name, organization, category }) => {
    await page.click("#open-add");
    await page.click("#action-manual");
    await page.selectOption("#field-symbology", format);
    await page.fill("#field-payload", code);
    await page.fill("#field-name", name);
    await page.fill("#field-organization", organization);
    await page.selectOption("#field-category", category);
    await page.waitForSelector("#preview-block:not([hidden]) svg, #preview-block:not([hidden]) canvas", { timeout: 20000 });
    await page.click("#save-card");
    await page.waitForSelector("#view-wallet:not([hidden])");
  };

  await addCard({ code: "590123412345", format: "ean13", name: "Clubcard", organization: "Tesco", category: "loyalty" });
  await addCard({ code: "https://tickets.example.com/t/9f2c41a8", format: "qr", name: "Festival Ticket", organization: "Riverside Open Air", category: "eventTicket" });
  await addCard({ code: "MEMBER-48213", format: "code128", name: "Climbing Gym", organization: "Boulder Club", category: "membership" });

  check("three cards are in the wallet", (await page.locator(".card-tile").count()) === 3);
  check("the empty state is gone", !(await page.isVisible("#wallet-empty")));

  const stored = await page.evaluate(() =>
    JSON.parse(localStorage.getItem("pocketpass.cards")).map((card) => card.payload)
  );
  check(
    "the missing check digit was completed on save",
    stored.includes("5901234123457"),
    stored.join(" | ")
  );

  await page.waitForTimeout(400);
  await page.screenshot({ path: join(SHOTS, "01-wallet.png") });

  await page.locator(".card-tile", { hasText: "Clubcard" }).click();
  await page.waitForSelector("#view-card:not([hidden]) #card-symbol svg");
  const readable = await page.textContent("#card-readable");
  check("the digits are printed under the symbol", readable.trim() === "5901 2341 2345 7", readable);
  await page.waitForTimeout(300);
  await page.screenshot({ path: join(SHOTS, "02-card.png") });

  await page.click("#view-card [data-back]");
  await page.locator(".card-tile", { hasText: "Festival Ticket" }).click();
  await page.waitForSelector("#view-card:not([hidden]) #card-symbol canvas", { timeout: 20000 });
  check("a QR card draws through bwip-js", await page.isVisible("#card-symbol canvas"));
  await page.waitForTimeout(300);
  await page.screenshot({ path: join(SHOTS, "03-qr.png") });

  await page.click("#view-card [data-back]");
  await page.click("#open-settings");
  await page.waitForSelector("#view-settings:not([hidden])");
  await page.screenshot({ path: join(SHOTS, "04-settings.png") });

  const backup = await page.evaluate(async () => {
    const store = await import("./js/store.js");
    const text = store.makeBackup(store.loadCards());
    return { exported: JSON.parse(text).cards.length, restored: store.readBackup(text).length };
  });
  check("a backup exports and reads back", backup.exported === 3 && backup.restored === 3, JSON.stringify(backup));

  const serviceWorker = await page.evaluate(async () => Boolean(await navigator.serviceWorker.getRegistration()));
  check("the service worker registers", serviceWorker);

  check("the page logged no errors", pageProblems.length === 0, pageProblems.join("; "));
} finally {
  await browser.close();
  server.close();
}

console.log(`\nScreenshots in ${SHOTS}`);
if (failures.length) {
  console.log(`${failures.length} check(s) failed.`);
  process.exit(1);
}
console.log("All checks passed.");
