import fs from "node:fs";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const assets = [
  "public/branding/zion-mark.svg",
  "public/branding/zion-app-icon-1024.png",
  "public/branding/zion-app-icon@2x.png",
  "public/branding/zion-app-icon@3x.png",
  "public/branding/sentra-wordmark.svg",
  "public/branding/sentra-lockup-horizontal.svg",
  "public/branding/sentra-status-glyph.svg",
  "public/branding/sentra-dmg-background-1200x800.png",
  "public/branding/sentra-dmg-background-600x400.png",
];

for (const relative of assets) {
  const file = path.join(root, relative);
  if (!fs.existsSync(file)) throw new Error(`Missing Zion asset: ${relative}`);
  const bytes = fs.readFileSync(file);
  if (relative.endsWith(".png")) {
    const signature = "89504e470d0a1a0a";
    if (bytes.subarray(0, 8).toString("hex") !== signature) {
      throw new Error(`Invalid PNG signature: ${relative}`);
    }
  } else if (!bytes.toString("utf8").includes("<svg")) {
    throw new Error(`Invalid SVG: ${relative}`);
  }
}

console.log(`Validated ${assets.length} Zion/Sentra brand assets.`);
console.log(
  "Animation frame pack: pending supplied frame inventory; CSS fallback active.",
);
