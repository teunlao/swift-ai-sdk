#!/usr/bin/env node

const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const dashboardDir = path.resolve(__dirname, "..", "..", "orchestrator-dashboard");
const nextBin = path.resolve(
  dashboardDir,
  "node_modules",
  ".bin",
  process.platform === "win32" ? "next.cmd" : "next"
);

const port = process.env.ORCHESTRATOR_DASHBOARD_PORT || "4444";
const host = process.env.ORCHESTRATOR_DASHBOARD_HOST || "localhost";
const buildIdPath = path.join(dashboardDir, ".next", "BUILD_ID");

function spawnStream(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: "inherit",
      ...options,
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve(undefined);
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
  });
}

async function ensureBuild() {
  if (fs.existsSync(buildIdPath) && !process.env.ORCHESTRATOR_DASHBOARD_FORCE_BUILD) {
    return;
  }

  console.log("🔧 Building orchestrator dashboard...");
  await spawnStream(nextBin, ["build"], { cwd: dashboardDir });
}

function openBrowser(url) {
  const platform = process.platform;
  let command;
  let args;

  if (platform === "darwin") {
    command = "open";
    args = [url];
  } else if (platform === "win32") {
    command = "cmd";
    args = ["/c", "start", "", url];
  } else {
    command = "xdg-open";
    args = [url];
  }

  const opener = spawn(command, args, {
    stdio: "ignore",
    detached: true,
  });
  opener.unref();
}

async function main() {
  try {
    await ensureBuild();

    console.log(`🚀 Starting dashboard on http://${host}:${port}`);
    const server = spawn(nextBin, ["start", "-p", port, "--hostname", host], {
      cwd: dashboardDir,
      stdio: "inherit",
    });

    server.once("spawn", () => {
      if (!process.env.ORCHESTRATOR_DASHBOARD_NO_BROWSER) {
        setTimeout(() => {
          try {
            openBrowser(`http://${host}:${port}`);
          } catch (err) {
            console.warn("⚠️  Could not open browser automatically:", err?.message ?? err);
          }
        }, 1500);
      }
    });

    const shutdown = () => {
      server.kill("SIGINT");
    };

    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    server.on("exit", (code) => {
      process.exit(code ?? 0);
    });
  } catch (error) {
    console.error("❌ Dashboard failed:", error?.message ?? error);
    process.exit(1);
  }
}

main();
