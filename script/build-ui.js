const fs = require("fs");
const path = require("path");
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
const distRoot = path.resolve(args["dist-root"] || path.join(rootDir, "dist", "ui"));
const buildRoot = path.resolve(args["build-root"] || path.join(rootDir, "build", "ui"));
const appName = "QKKDecrypt-UI";
const isMac = process.platform === "darwin";
const pythonExe = resolvePythonExe(rootDir);
const mainPy = path.join(rootDir, "ui_main.py");
const assetsDir = path.join(rootDir, "assets");
const kuwoRuntimeDir = path.join(rootDir, "src", "Infrastructure", "platforms", "kuwo", "runtime_m");
const appIcon = path.join(rootDir, "封面", isMac ? "封面.png" : "封面.ico");

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

ensureModule("PySide6", "PySide6");
ensureModule("shiboken6", "PySide6");
ensureModule("qfluentwidgets", "PySide6-Fluent-Widgets");
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

const excludedQtModules = [
  "PySide6.Qt3DAnimation",
  "PySide6.Qt3DCore",
  "PySide6.Qt3DExtras",
  "PySide6.Qt3DInput",
  "PySide6.Qt3DLogic",
  "PySide6.Qt3DRender",
  "PySide6.QtBluetooth",
  "PySide6.QtCharts",
  "PySide6.QtConcurrent",
  "PySide6.QtDataVisualization",
  "PySide6.QtDBus",
  "PySide6.QtDesigner",
  "PySide6.QtHelp",
  "PySide6.QtHttpServer",
  "PySide6.QtLocation",
  "PySide6.QtMultimedia",
  "PySide6.QtMultimediaWidgets",
  "PySide6.QtNetworkAuth",
  "PySide6.QtNfc",
  "PySide6.QtOpenGL",
  "PySide6.QtOpenGLWidgets",
  "PySide6.QtPdf",
  "PySide6.QtPdfWidgets",
  "PySide6.QtPositioning",
  "PySide6.QtQml",
  "PySide6.QtQuick",
  "PySide6.QtQuick3D",
  "PySide6.QtQuickControls2",
  "PySide6.QtQuickWidgets",
  "PySide6.QtRemoteObjects",
  "PySide6.QtScxml",
  "PySide6.QtSensors",
  "PySide6.QtSerialBus",
  "PySide6.QtSerialPort",
  "PySide6.QtSpatialAudio",
  "PySide6.QtSql",
  "PySide6.QtStateMachine",
  "PySide6.QtSvg",
  "PySide6.QtSvgWidgets",
  "PySide6.QtTest",
  "PySide6.QtTextToSpeech",
  "PySide6.QtUiTools",
  "PySide6.QtWebChannel",
  "PySide6.QtWebEngineCore",
  "PySide6.QtWebEngineQuick",
  "PySide6.QtWebEngineWidgets",
  "PySide6.QtWebSockets",
  "PySide6.QtXml",
  "PySide6.QtXmlPatterns",
];

const qfluentRequiredQtModules = new Set([
  "PySide6.QtMultimedia",
  "PySide6.QtMultimediaWidgets",
  "PySide6.QtSvg",
  "PySide6.QtSvgWidgets",
  "PySide6.QtXml",
]);

const pyinstallerArgs = [
  "-m",
  "PyInstaller",
  "--noconfirm",
  "--clean",
  "--onedir",
  "--windowed",
  "--icon",
  appIcon,
  "--name",
  appName,
  "--contents-directory",
  "_internal",
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
  "--collect-all",
  "qfluentwidgets",
  "--hidden-import",
  "shiboken6",
  "--hidden-import",
  "PySide6.QtCore",
  "--hidden-import",
  "PySide6.QtGui",
  "--hidden-import",
  "PySide6.QtWidgets",
  "--add-data",
  `${assetsDir}${path.delimiter}assets`,
  "--add-data",
  `${path.dirname(appIcon)}${path.delimiter}封面`,
  "--add-data",
  `${kuwoRuntimeDir}${path.delimiter}src/Infrastructure/platforms/kuwo/runtime_m`,
  mainPy,
];

for (const moduleName of qfluentRequiredQtModules) {
  pyinstallerArgs.push("--hidden-import", moduleName);
}

for (const moduleName of excludedQtModules) {
  if (!qfluentRequiredQtModules.has(moduleName)) {
    pyinstallerArgs.push("--exclude-module", moduleName);
  }
}

if (isMac) {
  pyinstallerArgs.push("--osx-bundle-identifier", "io.github.acooldog.qkkdecrypt");
  if (!ffmpegPath.startsWith(assetsDir + path.sep)) {
    pyinstallerArgs.push("--add-binary", `${ffmpegPath}${path.delimiter}assets`);
  }
}

run(pythonExe, pyinstallerArgs, {
  cwd: rootDir,
  env: {
    ...process.env,
    PYINSTALLER_CONFIG_DIR: path.join(buildRoot, "pyinstaller-config"),
  },
});
if (isMac) {
  ensureDir(path.join(distRoot, `${appName}.app`), "macOS UI application bundle");
} else {
  ensureFile(path.join(distRoot, appName, `${appName}.exe`), "ui onedir executable");
}
