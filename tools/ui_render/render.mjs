// Draws a GUI dump (from run.luau or rbxl.luau) as a PNG, the way Roblox would lay it out,
// on a phone (844x390) or PC (1280x720) screen.
//   node tools/ui_render/render.mjs <dump.json> <out.png> [Phone|PC] [screen,names] [--disabled]
// Images: ids from Config/Images.luau use the local PNGs; any other rbxassetid is fetched
// once with the Open Cloud asset-delivery API (ROBLOXAPIKEY) into a cache.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..", "..");
const CACHE = process.env.UI_CACHE || "/tmp/claude-0/rbxcache";
const FONTS = process.env.UI_FONTS || "/tmp/claude-0/fonts";
fs.mkdirSync(CACHE, { recursive: true });

const DEVICES = {
  PC: { w: 1280, h: 720, core: [0, 58, 0, 0], safe: [0, 0, 0, 0] },
  Phone: { w: 844, h: 390, core: [47, 40, 47, 21], safe: [47, 0, 47, 21] },
};

const [, , dumpPath, outPath, devName = "PC", only = "", ...flags] = process.argv;
const device = { ...DEVICES[devName], showDisabled: flags.includes("--disabled") };
let screens = JSON.parse(fs.readFileSync(dumpPath, "utf8"));
// Lune encodes empty tables as {}: make child lists arrays again.
const fix = (n) => { if (!Array.isArray(n.k)) n.k = []; if (!n.p || Array.isArray(n.p)) n.p = {}; n.k.forEach(fix); };
if (!Array.isArray(screens)) screens = [];
screens.forEach(fix);
if (only) {
  const want = new Set(only.split(","));
  screens = screens.filter((s) => want.has(s.n));
  if (device.showDisabled) screens.forEach((s) => (s.p.Enabled = true));
}

// local images: Config/Images.luau name -> id, files in the icon folders
const localById = {};
try {
  const src = fs.readFileSync(path.join(ROOT, "src/shared/Config/Images.luau"), "utf8");
  const dirs = ["/mnt/project-files/game-ideas/roll-the-snowball/icons", path.join(ROOT, "art/ui"), path.join(ROOT, "art/out/ui")];
  for (const m of src.matchAll(/(\w+) = "(rbxassetid:\/\/\d+)"/g)) {
    for (const d of dirs) {
      const f = path.join(d, m[1] + ".png");
      if (fs.existsSync(f)) { localById[m[2]] = f; break; }
    }
  }
} catch {}

function fetchImage(uri) {
  const id = (uri.match(/(\d{5,})/) || [])[1];
  if (!id) return null;
  if (localById[uri]) return localById[uri];
  const file = path.join(CACHE, id + ".png");
  if (fs.existsSync(file)) return fs.statSync(file).size > 0 ? file : null;
  try {
    const meta = JSON.parse(execFileSync("curl", ["-s", "-H", `x-api-key: ${process.env.ROBLOXAPIKEY || ""}`,
      `https://apis.roblox.com/asset-delivery-api/v1/assetId/${id}`], { encoding: "utf8" }));
    if (meta.location) {
      execFileSync("curl", ["-s", "--compressed", "-o", file, meta.location]);
      const head = fs.readFileSync(file).subarray(0, 8);
      if (head[0] === 0x89 || head[0] === 0xff || head.toString().startsWith("RIFF")) return file;
      // Decal XML: find the texture id inside and fetch that
      const xml = fs.readFileSync(file, "utf8");
      const inner = xml.match(/id=(\d+)/) || xml.match(/rbxassetid:\/\/(\d+)/);
      fs.writeFileSync(file, "");
      if (inner && inner[1] !== id) {
        const f2 = fetchImage("rbxassetid://" + inner[1]);
        if (f2) { fs.copyFileSync(f2, file); return file; }
      }
      return null;
    }
  } catch {}
  fs.writeFileSync(file, "");
  return null;
}

const ids = new Set();
const walk = (n) => { if (n.p && n.p.Image) ids.add(n.p.Image); (n.k || []).forEach(walk); };
screens.forEach(walk);
const IMAGES = {};
for (const uri of ids) {
  const f = fetchImage(uri);
  if (f) IMAGES[uri] = { src: "file://" + f, w: 0, h: 0 };
}

const fontFaces = [];
const addFont = (fam, file, weight) => { if (fs.existsSync(file)) fontFaces.push(`@font-face{font-family:'${fam}';src:url('file://${file}');font-weight:${weight};}`); };
for (const w of [400, 600, 700, 800, 900]) addFont("Montserrat", `${FONTS}/montserrat-${w}.ttf`, w);
addFont("FredokaOne", `${FONTS}/Fredoka.ttf`, "100 900");
addFont("SourceSans", `${FONTS}/sourcesans-400.ttf`, "100 900");
addFont("Luckiest", `${FONTS}/luckiest.ttf`, "100 900");
const FONTMAP = {
  Montserrat: { family: "Montserrat" }, GothamSSm: { family: "Montserrat" }, Gotham: { family: "Montserrat" },
  FredokaOne: { family: "FredokaOne", forceWeight: 400 }, SourceSansPro: { family: "SourceSans" },
  LuckiestGuy: { family: "Luckiest", forceWeight: 400 }, BuilderSans: { family: "Montserrat" },
  default: { family: "Montserrat" },
};

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
${fontFaces.join("\n")}
html,body{margin:0;background:#000}
#stage{position:relative;overflow:hidden;background:linear-gradient(#8fc3f0 0%,#cfe6fa 52%,#eef5fc 52%,#dfeaf5 100%)}
#stage .tree{position:absolute;bottom:30%;width:0;height:0;border-left:40px solid transparent;border-right:40px solid transparent;border-bottom:120px solid #2f7a52;opacity:.8}
.topbar{position:absolute;top:12px;left:12px;display:flex;gap:10px;z-index:99999}
.topbar div{width:44px;height:44px;border-radius:22px;background:rgba(18,18,21,.75)}
.notch{position:absolute;left:0;top:0;bottom:0;width:30px;background:#000;z-index:99999;border-radius:0 18px 18px 0}
</style></head><body><div id="stage">
<div class="tree" style="left:12%"></div><div class="tree" style="left:22%;transform:scale(.8)"></div><div class="tree" style="right:15%"></div><div class="tree" style="right:26%;transform:scale(.7)"></div>
<div class="topbar"><div></div><div></div></div>${devName === "Phone" ? '<div class="notch"></div>' : ""}
</div>
<script>window.IMAGES=${JSON.stringify(IMAGES)};window.FONTMAP=${JSON.stringify(FONTMAP)};</script>
<script>${fs.readFileSync(path.join(HERE, "engine.js"), "utf8")}</script>
</body></html>`;
const tmp = path.join(CACHE, `page_${process.pid}.html`);
fs.writeFileSync(tmp, html);

const browser = await chromium.launch({ args: ["--allow-file-access-from-files"] });
const page = await browser.newPage({ viewport: { width: device.w, height: device.h }, deviceScaleFactor: Number(process.env.UI_DSF || 1) });
await page.goto("file://" + tmp);
await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all(Object.values(window.IMAGES).map((info) => new Promise((res) => {
    const im = new Image(); im.onload = () => { info.w = im.naturalWidth; info.h = im.naturalHeight; res(); }; im.onerror = res; im.src = info.src;
  })));
  for (const f of ["Montserrat", "FredokaOne", "SourceSans", "Luckiest"]) for (const w of [400, 700, 800, 900]) await document.fonts.load(`${w} 20px ${f}`);
});
await page.evaluate(([s, d]) => window.renderScreens(s, d), [screens, device]);
await page.waitForTimeout(150);
await page.screenshot({ path: outPath });
await browser.close();
fs.unlinkSync(tmp);
console.log("wrote", outPath);
