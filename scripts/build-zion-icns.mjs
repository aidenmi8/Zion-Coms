import fs from "node:fs";
import path from "node:path";

const [, , iconsDirectory, outputPath] = process.argv;

if (!iconsDirectory || !outputPath) {
  console.error("usage: build-zion-icns.mjs <icons-directory> <output.icns>");
  process.exit(2);
}

const layers = [
  ["ic07", "128x128.png", 128],
  ["ic08", "128x128@2x.png", 256],
  ["ic09", "icon.png", 512],
  ["ic10", "buzz-source.png", 1024],
];
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function readRgbaPng(filename, expectedSize) {
  const filePath = path.join(iconsDirectory, filename);
  const data = fs.readFileSync(filePath);
  if (!data.subarray(0, pngSignature.length).equals(pngSignature)) {
    throw new Error(`${filePath} is not a PNG`);
  }

  const ihdrLength = data.readUInt32BE(8);
  if (data.toString("ascii", 12, 16) !== "IHDR" || ihdrLength !== 13) {
    throw new Error(`${filePath} has no canonical PNG IHDR`);
  }

  const width = data.readUInt32BE(16);
  const height = data.readUInt32BE(20);
  const bitDepth = data.readUInt8(24);
  const colorType = data.readUInt8(25);
  if (width !== expectedSize || height !== expectedSize) {
    throw new Error(`${filePath} is ${width}x${height}, expected ${expectedSize}x${expectedSize}`);
  }
  if (bitDepth !== 8 || colorType !== 6) {
    throw new Error(`${filePath} is not 8-bit RGBA (bitDepth=${bitDepth}, colorType=${colorType})`);
  }
  return data;
}

const chunks = layers.map(([type, filename, size]) => {
  const data = readRgbaPng(filename, size);
  const chunk = Buffer.alloc(8 + data.length);
  chunk.write(type, 0, 4, "ascii");
  chunk.writeUInt32BE(chunk.length, 4);
  data.copy(chunk, 8);
  return chunk;
});

const output = Buffer.alloc(8);
output.write("icns", 0, 4, "ascii");
output.writeUInt32BE(8 + chunks.reduce((total, chunk) => total + chunk.length, 0), 4);
fs.writeFileSync(outputPath, Buffer.concat([output, ...chunks]));
console.log(`Wrote ${outputPath} with ${layers.length} Zion PNG layers.`);
