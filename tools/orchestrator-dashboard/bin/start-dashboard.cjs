#!/usr/bin/env node

const { spawn } = require("node:child_process");
const crypto = require("node:crypto");
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
const snapshotPath = path.join(dashboardDir, ".next", "dashboard-snapshot.json");
const repoRoot = path.resolve(dashboardDir, "..", "..");

const WATCH_PATHS = [
  path.join(dashboardDir, "src"),
  path.join(dashboardDir, "next.config.ts"),
  path.join(dashboardDir, "package.json"),
  path.join(dashboardDir, "tsconfig.json"),
  path.join(dashboardDir, "tailwind.config.ts"),
  path.join(dashboardDir, "postcss.config.cjs"),
  path.join(dashboardDir, "next-env.d.ts"),
  path.join(repoRoot, "pnpm-lock.yaml"),
  path.join(repoRoot, "package.json"),
];
const IGNORED_DIRECTORIES = new Set(["node_modules", ".next", ".git", "dist", "build"]);

function listDirectory(dirPath) {
  try {
    return fs.readdirSync(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }
}

function addPathToHash(targetPath, hash, visited) {
  if (!fs.existsSync(targetPath)) {
    return;
  }

  const stats = fs.statSync(targetPath);

  if (stats.isDirectory()) {
    if (visited.has(targetPath)) return;
    visited.add(targetPath);

    const entries = listDirectory(targetPath).filter((entry) => !IGNORED_DIRECTORIES.has(entry.name));
    entries.sort((a, b) => a.name.localeCompare(b.name));

    for (const entry of entries) {
      addPathToHash(path.join(targetPath, entry.name), hash, visited);
    }
    return;
  }

  const rel = path.relative(dashboardDir, targetPath);
  hash.update(rel);
  hash.update(fs.readFileSync(targetPath));
}

function computeSourceHash() {
  const hash = crypto.createHash("sha256");
  const visited = new Set();

  for (const target of WATCH_PATHS) {
    addPathToHash(target, hash, visited);
  }

  // Include ABI to force rebuild when Node/ABI changes.
  hash.update(String(process.versions.node));
  hash.update(String(process.versions.modules));

  return hash.digest("hex");
}

function readSnapshot() {
  if (!fs.existsSync(snapshotPath)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(snapshotPath, "utf-8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeSnapshot(data) {
  fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
  fs.writeFileSync(snapshotPath, JSON.stringify(data, null, 2));
}

function buildSnapshot() {
  return {
    hash: computeSourceHash(),
    nodeVersion: process.versions.node,
    abiVersion: process.versions.modules,
  };
}

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
  const forceBuild = Boolean(process.env.ORCHESTRATOR_DASHBOARD_FORCE_BUILD);
  const existingSnapshot = readSnapshot();
  const currentSnapshot = buildSnapshot();
  const buildExists = fs.existsSync(buildIdPath);

  const needsBuild =
    forceBuild ||
    !buildExists ||
    !existingSnapshot ||
    existingSnapshot.hash !== currentSnapshot.hash ||
    existingSnapshot.nodeVersion !== currentSnapshot.nodeVersion ||
    existingSnapshot.abiVersion !== currentSnapshot.abiVersion;

  if (!needsBuild) {
    return;
  }

  console.log("🔧 Building orchestrator dashboard...");
  await spawnStream(nextBin, ["build"], { cwd: dashboardDir });

  const finalSnapshot = buildSnapshot();
  writeSnapshot({ ...finalSnapshot, builtAt: new Date().toISOString() });
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
