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

function copyBetterSqlite3Binary() {
  let resolved;
  try {
    resolved = require.resolve("better-sqlite3");
  } catch (error) {
    console.warn("⚠️  better-sqlite3 not found, skipping native binary copy", error?.message ?? error);
    return;
  }

  const nativePath = path.resolve(path.dirname(resolved), "..", "build", "Release", "better_sqlite3.node");
  if (!fs.existsSync(nativePath)) {
    console.warn("⚠️  better-sqlite3 native binary missing at", nativePath);
    return;
  }

  const moduleCode = process.versions.modules;
  const bindingDirName = `node-v${moduleCode}-${process.platform}-${process.arch}`;

  const targets = [
    path.join(dashboardDir, ".next", "build", "better_sqlite3.node"),
    path.join(dashboardDir, ".next", "build", "Release", "better_sqlite3.node"),
    path.join(dashboardDir, ".next", "lib", "binding", bindingDirName, "better_sqlite3.node"),
    path.join(dashboardDir, ".next", "standalone", "node_modules", "better-sqlite3", "build", "Release", "better_sqlite3.node"),
    path.join(dashboardDir, ".next", "standalone", "node_modules", "better-sqlite3", "lib", "binding", bindingDirName, "better_sqlite3.node"),
  ];

  for (const target of targets) {
    try {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(nativePath, target);
    } catch (error) {
      console.warn("⚠️  Failed to copy better-sqlite3 binary to", target, error?.message ?? error);
    }
  }
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

async function killPortProcess(port) {
  const { execSync } = require("node:child_process");
  try {
    const command = process.platform === "win32"
      ? `netstat -ano | findstr :${port}`
      : `lsof -ti:${port}`;

    const pid = execSync(command, { encoding: "utf-8" }).trim();
    if (pid) {
      console.log(`⚠️  Port ${port} is in use by PID ${pid}, killing it...`);
      const killCmd = process.platform === "win32" ? `taskkill /PID ${pid} /F` : `kill -9 ${pid}`;
      execSync(killCmd);
      await new Promise(resolve => setTimeout(resolve, 1000));
      console.log(`✅ Killed process on port ${port}`);
    }
  } catch (error) {
    // Port is free or command failed
  }
}

async function main() {
  let server;
  try {
    await ensureBuild();
    copyBetterSqlite3Binary();

    await killPortProcess(port);

    console.log(`🚀 Starting dashboard on http://${host}:${port}`);
    server = spawn(nextBin, ["start", "-p", port, "--hostname", host], {
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

    let shuttingDown = false;
    const forwardExit = (code = 0) => {
      if (!shuttingDown) {
        process.exit(code);
      }
    };

    const requestShutdown = (signal) => {
      if (shuttingDown) return;
      shuttingDown = true;
      console.log(`\n🛑 Received ${signal}, shutting down dashboard...`);

      if (!server || server.exitCode !== null) {
        forwardExit(server?.exitCode ?? 0);
        return;
      }

      const timeout = setTimeout(() => {
        console.warn("⚠️ Dashboard did not exit in time, forcing shutdown.");
        try {
          server.kill("SIGKILL");
        } catch {
          // ignore
        }
        forwardExit(1);
      }, 5000);

      server.once("exit", (code) => {
        clearTimeout(timeout);
        forwardExit(code ?? 0);
      });

      try {
        const sent = server.kill(signal);
        if (!sent) {
          server.kill("SIGKILL");
        }
      } catch (error) {
        console.warn("⚠️ Failed to forward signal:", error?.message ?? error);
        forwardExit(1);
      }
    };

    process.once("SIGINT", () => requestShutdown("SIGINT"));
    process.once("SIGTERM", () => requestShutdown("SIGTERM"));

    server.on("exit", (code) => {
      forwardExit(code ?? 0);
    });
    server.on("error", (error) => {
      console.error("❌ Dashboard process error:", error?.message ?? error);
      forwardExit(1);
    });
  } catch (error) {
    console.error("❌ Dashboard failed:", error?.message ?? error);
    process.exit(1);
  }
}

main();
