// Screenshots a repo-review report in light, dark and phone width, so the layout can be
// checked by eye. Read-only: it only opens the file.
//
// Usage: node screenshot.cjs <report.html> <out-dir> [repo-path]
// Playwright is looked up in the reviewed repo's node_modules (repo-path), then globally.
// The browser is Playwright's own if installed, otherwise the local Chrome or Edge.
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");

const [report, out, repo] = process.argv.slice(2);
if (!report || !out) {
  console.error("usage: node screenshot.cjs <report.html> <out-dir> [repo-path]");
  process.exit(1);
}

function loadPlaywright() {
  const roots = [repo, process.cwd()].filter(Boolean);
  for (const root of roots)
    for (const name of ["playwright", "@playwright/test", "playwright-core"]) {
      try { return require(require.resolve(name, { paths: [root] })); } catch {}
    }
  for (const name of ["playwright", "playwright-core"]) { try { return require(name); } catch {} }
  return null;
}

const browsers = [
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "C:/Program Files/Microsoft/Edge/Application/msedge.exe",
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
];

(async () => {
  const pw = loadPlaywright();
  if (!pw) { console.error("NO_PLAYWRIGHT: layout not checked"); process.exit(2); }
  let browser;
  try { browser = await pw.chromium.launch(); }
  catch {
    const exe = browsers.find((p) => fs.existsSync(p));
    if (!exe) { console.error("NO_BROWSER: layout not checked"); process.exit(2); }
    browser = await pw.chromium.launch({ executablePath: exe });
  }
  fs.mkdirSync(out, { recursive: true });
  const url = pathToFileURL(path.resolve(report)).href;
  const shots = [
    ["light", { width: 1000, height: 900 }, "light"],
    ["dark", { width: 1000, height: 900 }, "dark"],
    ["mobile", { width: 390, height: 844 }, "light"],
  ];
  for (const [name, viewport, colorScheme] of shots) {
    const page = await browser.newPage({ viewport, colorScheme });
    await page.goto(url);
    // Sticky navigation would cover content in a full-page capture.
    await page.addStyleTag({ content: "nav.toc { position: static !important; }" });
    const file = path.join(out, `report-${name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
    const emptyBars = await page.evaluate(() =>
      [...document.querySelectorAll(".bars .bar, .stack span, .cols span")].filter((e) => e.getBoundingClientRect().width < 1).length);
    console.log(`${name}: ${file}${overflow ? "  HORIZONTAL OVERFLOW" : ""}${emptyBars ? `  ${emptyBars} EMPTY BARS` : ""}`);
  }
  await browser.close();
})();
