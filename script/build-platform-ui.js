const path = require("path");
const { run } = require("./build-lib");

const rootDir = path.resolve(__dirname, "..");
const script = process.platform === "darwin" ? "build-macos-ui.js" : "build-ui.js";
run("node", [path.join(rootDir, "script", script), ...process.argv.slice(2)], { cwd: rootDir });
