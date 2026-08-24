const path = require("path");
const { run } = require("./build-lib");

const rootDir = path.resolve(__dirname, "..");
if (process.platform === "darwin") {
  run("sh", [path.join(rootDir, "native", "build_native.sh")], { cwd: rootDir });
} else if (process.platform === "win32") {
  run("powershell", ["-ExecutionPolicy", "Bypass", "-File", path.join(rootDir, "native", "build_native.ps1")], { cwd: rootDir });
} else {
  throw new Error(`Unsupported native build platform: ${process.platform}`);
}
