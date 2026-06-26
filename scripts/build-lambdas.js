"use strict";

const esbuild = require("esbuild");
const archiver = require("archiver");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const ARTIFACTS_DIR = path.join(ROOT, "artifacts");

const LAMBDAS = [
  { name: "ingestion", entry: "services/ingestion/src/handler.js" },
  { name: "processor", entry: "services/processor/src/handler.js" },
  { name: "orders-query", entry: "services/orders-query/src/handler.js" },
];

/**
 * Bundles a Lambda handler with ESBuild.
 * - Inlines local requires (including shared/metrics)
 * - Marks @aws-sdk/* as external (available in Lambda node20 runtime)
 */
async function bundle(name, entry, outFile) {
  await esbuild.build({
    entryPoints: [path.join(ROOT, entry)],
    outfile: outFile,
    bundle: true,
    platform: "node",
    target: "node20",
    format: "cjs",
    external: ["@aws-sdk/*"],
    minify: false,
    sourcemap: false,
    logLevel: "silent",
  });

  console.log(`  [bundle]  ${name} → ${path.relative(ROOT, outFile)}`);
}

/**
 * Zips a single bundled handler.js into a deployment-ready archive.
 */
function createZip(sourceFile, destZip) {
  return new Promise((resolve, reject) => {
    const output = fs.createWriteStream(destZip);
    const archive = archiver("zip", { zlib: { level: 9 } });

    output.on("close", resolve);
    archive.on("error", reject);

    archive.pipe(output);
    archive.file(sourceFile, { name: path.basename(sourceFile) });
    archive.finalize();
  });
}

async function buildLambda({ name, entry }) {
  const outDir = path.join(ARTIFACTS_DIR, name);
  const bundleFile = path.join(outDir, "handler.js");
  const zipFile = path.join(outDir, "function.zip");

  fs.mkdirSync(outDir, { recursive: true });

  await bundle(name, entry, bundleFile);
  await createZip(bundleFile, zipFile);

  const sizeKb = (fs.statSync(zipFile).size / 1024).toFixed(1);
  console.log(
    `  [zip]     ${name} → ${path.relative(ROOT, zipFile)} (${sizeKb} KB)`,
  );
}

async function main() {
  console.log("\nBuilding lambdas...\n");

  if (fs.existsSync(ARTIFACTS_DIR)) {
    fs.rmSync(ARTIFACTS_DIR, { recursive: true, force: true });
  }

  await Promise.all(LAMBDAS.map(buildLambda));

  console.log("\nDone. Artifacts:\n");
  for (const { name } of LAMBDAS) {
    console.log(`  artifacts/${name}/function.zip`);
  }
  console.log("");
}

main().catch((err) => {
  console.error("\nBuild failed:", err.message);
  process.exit(1);
});
