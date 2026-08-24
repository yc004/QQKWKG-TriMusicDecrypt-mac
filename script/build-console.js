const path = require("path");
const fs = require("fs");
const { spawnSync } = require("child_process");
const {
  commandSucceeds,
  ensureDir,
  ensureEmptyDir,
  ensureFile,
  parseArgs,
  resolvePythonExe,
  run,
} = require("./build-lib");

const args = parseArgs(process.argv.slice(2));
const rootDir = path.resolve(__dirname, "..");
const distRoot = path.resolve(args["dist-root"] || path.join(rootDir, "dist", "console"));
const buildRoot = path.resolve(args["build-root"] || path.join(rootDir, "build", "console"));
const appName = "QKKDecrypt";
const pythonExe = resolvePythonExe(rootDir);
const mainPy = path.join(rootDir, "main.py");
const assetsDir = path.join(rootDir, "assets");
const kuwoRuntimeDir = path.join(rootDir, "src", "Infrastructure", "platforms", "kuwo", "runtime_m");
const appIcon = path.join(rootDir, "封面", "封面.ico");
const isMac = process.platform === "darwin";

ensureFile(mainPy, "main entry");
ensureDir(assetsDir, "assets directory");
ensureDir(kuwoRuntimeDir, "kuwo runtime directory");
ensureFile(path.join(assetsDir, "kugou_key.xz"), "kugou_key.xz");
ensureFile(
  path.join(assetsDir, isMac ? "libkudog_native.dylib" : "kudog_native.dll"),
  "native acceleration library",
);
const ffmpegCandidates = isMac
  ? fs.readdirSync(assetsDir).filter((name) => /^ffmpeg(?:-|$)/.test(name) && !name.endsWith(".exe"))
  : ["ffmpeg-win-x86_64-v7.1.exe"];
let ffmpegPath = ffmpegCandidates.length > 0 ? path.join(assetsDir, ffmpegCandidates[0]) : "";
if (!ffmpegPath && isMac) {
  const result = spawnSync("which", ["ffmpeg"], { encoding: "utf8", shell: false });
  if (result.status === 0) {
    ffmpegPath = (result.stdout || "").trim();
  }
}
ensureFile(ffmpegPath, "ffmpeg (bundle it in assets or install it with Homebrew)");
ensureFile(path.join(kuwoRuntimeDir, "kwm_export_agent.js"), "kwm_export_agent.js");
ensureFile(path.join(kuwoRuntimeDir, "out", "recovered_signature.json"), "kuwo recovered signature");
ensureFile(appIcon, "application icon");

function hasModule(moduleName) {
  const script = [
    "import importlib.util, sys",
    `sys.exit(0 if importlib.util.find_spec(${JSON.stringify(moduleName)}) else 1)`,
  ].join("; ");
  return commandSucceeds(pythonExe, ["-c", script], { cwd: rootDir });
}

function ensureModule(moduleName, packageName = moduleName) {
  if (hasModule(moduleName)) {
    return;
  }
  run(pythonExe, ["-m", "pip", "install", packageName], { cwd: rootDir });
  if (!hasModule(moduleName)) {
    throw new Error(`Python module '${moduleName}' is still unavailable after installing '${packageName}'.`);
  }
}

ensureModule("ncmdump", "ncmdump-py");
ensureModule("cryptography");
ensureModule("frida");
ensureModule("mutagen");
ensureModule("PyInstaller", "pyinstaller");

ensureEmptyDir(distRoot);
ensureEmptyDir(buildRoot);

run(pythonExe, ["-m", "PyInstaller", "--version"], { cwd: rootDir });

const specRoot = path.join(buildRoot, "spec");
ensureEmptyDir(specRoot);

const pyinstallerArgs = [
  "-m",
  "PyInstaller",
  "--noconfirm",
  "--clean",
  "--onefile",
  "--name",
  appName,
  "--distpath",
  distRoot,
  "--workpath",
  path.join(buildRoot, "work"),
  "--specpath",
  specRoot,
  "--paths",
  rootDir,
  "--collect-submodules",
  "src",
  "--collect-all",
  "frida",
  "--collect-all",
  "ncmdump",
  "--add-data",
  `${assetsDir}${path.delimiter}assets`,
  "--add-data",
  `${path.dirname(appIcon)}${path.delimiter}封面`,
  "--add-data",
  `${kuwoRuntimeDir}${path.delimiter}src/Infrastructure/platforms/kuwo/runtime_m`,
  mainPy,
];

if (!isMac) {
  pyinstallerArgs.splice(4, 0, "--icon", appIcon);
} else if (!ffmpegPath.startsWith(assetsDir + path.sep)) {
  pyinstallerArgs.splice(pyinstallerArgs.length - 1, 0, "--add-binary", `${ffmpegPath}${path.delimiter}assets`);
}

run(pythonExe, pyinstallerArgs, {
  cwd: rootDir,
  env: {
    ...process.env,
    PYINSTALLER_CONFIG_DIR: path.join(buildRoot, "pyinstaller-config"),
  },
});
ensureFile(path.join(distRoot, isMac ? appName : `${appName}.exe`), "console onefile executable");
