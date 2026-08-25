const fs = require("fs");
const path = require("path");
const {
  capture,
  ensureDir,
  ensureEmptyDir,
  ensureFile,
  parseArgs,
  run,
} = require("./build-lib");

const args = parseArgs(process.argv.slice(2));
const rootDir = path.resolve(__dirname, "..");
const distRoot = path.resolve(args["dist-root"] || path.join(rootDir, "dist", "ui"));
const buildRoot = path.resolve(args["build-root"] || path.join(rootDir, "build", "ui-native"));
const consoleDist = path.join(buildRoot, "backend-dist");
const consoleBuild = path.join(buildRoot, "backend-build");
const packageDir = path.join(rootDir, "native", "macos-ui");
const appDir = path.join(distRoot, "QKKDecrypt-UI.app");
const contentsDir = path.join(appDir, "Contents");
const macOSDir = path.join(contentsDir, "MacOS");
const resourcesDir = path.join(contentsDir, "Resources");

if (process.platform !== "darwin") {
  throw new Error("build-macos-ui.js requires macOS");
}

ensureEmptyDir(distRoot);
ensureEmptyDir(buildRoot);
run("node", [path.join(rootDir, "script", "build-console.js"), "--dist-root", consoleDist, "--build-root", consoleBuild], { cwd: rootDir });
const xcodeDeveloperDir = "/Applications/Xcode-beta.app/Contents/Developer";
const swiftEnvironment = {
  ...process.env,
  ...(fs.existsSync(xcodeDeveloperDir) ? { DEVELOPER_DIR: xcodeDeveloperDir } : {}),
  CLANG_MODULE_CACHE_PATH: path.join(buildRoot, "clang-module-cache"),
  SWIFTPM_MODULECACHE_OVERRIDE: path.join(buildRoot, "swift-module-cache"),
};
const macOSSDK = capture("xcrun", ["--sdk", "macosx", "--show-sdk-path"], { cwd: rootDir, env: swiftEnvironment });
swiftEnvironment.SDKROOT = macOSSDK;
const swiftOutputDir = path.join(buildRoot, "swift");
const swiftExecutable = path.join(swiftOutputDir, "QKKDecrypt-UI");
fs.mkdirSync(swiftOutputDir, { recursive: true });
const swiftSources = fs.readdirSync(path.join(packageDir, "Sources"))
  .filter((name) => name.endsWith(".swift"))
  .sort()
  .map((name) => path.join(packageDir, "Sources", name));
run("xcrun", [
  "swiftc", "-O", "-whole-module-optimization",
  "-sdk", macOSSDK,
  "-target", "arm64-apple-macosx15.0",
  ...swiftSources,
  "-o", swiftExecutable,
], { cwd: rootDir, env: swiftEnvironment });

const builtExecutable = swiftExecutable;
ensureFile(builtExecutable, "SwiftUI executable");
ensureFile(path.join(consoleDist, "QKKDecrypt"), "embedded Python backend");

fs.mkdirSync(macOSDir, { recursive: true });
fs.mkdirSync(resourcesDir, { recursive: true });
fs.copyFileSync(builtExecutable, path.join(macOSDir, "QKKDecrypt-UI"));
fs.copyFileSync(path.join(consoleDist, "QKKDecrypt"), path.join(resourcesDir, "QKKDecryptBackend"));
fs.copyFileSync(path.join(packageDir, "Info.plist"), path.join(contentsDir, "Info.plist"));
fs.chmodSync(path.join(macOSDir, "QKKDecrypt-UI"), 0o755);
fs.chmodSync(path.join(resourcesDir, "QKKDecryptBackend"), 0o755);

const iconset = path.join(buildRoot, "AppIcon.iconset");
fs.mkdirSync(iconset, { recursive: true });
const sourceIcon = path.join(rootDir, "封面", "封面.png");
ensureFile(sourceIcon, "application icon PNG");
for (const [name, size] of [["icon_16x16.png", 16], ["icon_16x16@2x.png", 32], ["icon_32x32.png", 32], ["icon_32x32@2x.png", 64], ["icon_128x128.png", 128], ["icon_128x128@2x.png", 256], ["icon_256x256.png", 256], ["icon_256x256@2x.png", 512], ["icon_512x512.png", 512], ["icon_512x512@2x.png", 1024]]) {
  run("sips", ["-z", String(size), String(size), sourceIcon, "--out", path.join(iconset, name)], { cwd: rootDir });
}
run("iconutil", ["-c", "icns", iconset, "-o", path.join(resourcesDir, "AppIcon.icns")], { cwd: rootDir });
run("codesign", ["--force", "--deep", "--sign", "-", appDir], { cwd: rootDir });
ensureDir(appDir, "native macOS UI application bundle");
console.log(`Native macOS UI ready: ${appDir}`);
