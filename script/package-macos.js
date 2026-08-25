const fs = require("fs");
const os = require("os");
const path = require("path");
const { ensureDir, ensureEmptyDir, ensureFile, run } = require("./build-lib");

const rootDir = path.resolve(__dirname, "..");
const releaseDir = path.join(rootDir, "release");
const distDir = path.join(rootDir, "dist", "console");
const buildDir = path.join(rootDir, "build", "console");
const executable = path.join(distDir, "QKKDecrypt");
const releaseExecutable = path.join(releaseDir, "QKKDecrypt");
const uiDistDir = path.join(rootDir, "dist", "ui");
const uiBuildDir = path.join(rootDir, "build", "ui");
const uiApp = path.join(uiDistDir, "QKKDecrypt-UI.app");
const dmgStageDir = path.join(rootDir, "build", "dmg-stage");

function main() {
  if (process.platform !== "darwin") {
    throw new Error("package-macos.js must be run on macOS.");
  }
  ensureEmptyDir(releaseDir);
  run("sh", [path.join(rootDir, "native", "build_native.sh")], { cwd: rootDir });
  run("node", [path.join(rootDir, "script", "build-console.js"), "--dist-root", distDir, "--build-root", buildDir], { cwd: rootDir });
  ensureFile(executable, "macOS console build");
  fs.copyFileSync(executable, releaseExecutable);
  fs.chmodSync(releaseExecutable, 0o755);
  const archive = path.join(releaseDir, `QKKDecrypt-macOS-${os.arch()}.zip`);
  run("/usr/bin/zip", ["-j", "-9", archive, releaseExecutable], { cwd: rootDir });
  run("node", [path.join(rootDir, "script", "build-macos-ui.js"), "--dist-root", uiDistDir, "--build-root", uiBuildDir], { cwd: rootDir });
  ensureDir(uiApp, "macOS UI application bundle");
  const uiArchive = path.join(releaseDir, `QKKDecrypt-UI-macOS-${os.arch()}.zip`);
  run("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", uiApp, uiArchive], { cwd: rootDir });
  ensureEmptyDir(dmgStageDir);
  run("ditto", [uiApp, path.join(dmgStageDir, "QKKDecrypt-UI.app")], { cwd: rootDir });
  fs.symlinkSync("/Applications", path.join(dmgStageDir, "Applications"));
  const uiDmg = path.join(releaseDir, `QKKDecrypt-UI-macOS-${os.arch()}.dmg`);
  run("hdiutil", [
    "create",
    "-volname",
    "QKKDecrypt",
    "-srcfolder",
    dmgStageDir,
    "-ov",
    "-format",
    "UDZO",
    uiDmg,
  ], { cwd: rootDir });
  console.log(`macOS releases ready: ${archive}, ${uiArchive}, ${uiDmg}`);
}

main();
