/**
 * Codex Agent Launcher
 *
 * Handles launching and managing Codex agents via MCP.
 */

import { spawn, ChildProcess } from "child_process";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

export interface CodexLaunchResult {
  shellId: string;
  outputFile: string;
  inputFile: string;
  process: ChildProcess;
}

/**
 * Launch a Codex agent via MCP server
 */
export async function launchCodexAgent(
  agentId: string,
  prompt: string,
  cwd: string,
  role: string
): Promise<CodexLaunchResult> {
  // Create temp directory for this agent
  const tmpDir = path.join(os.tmpdir(), `orchestrator-${agentId}`);
  if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
  }

  const inputFile = path.join(tmpDir, "input.json");
  const outputFile = path.join(tmpDir, "output.json");

  // Create JSON-RPC request for Codex
  const request = {
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "codex",
      arguments: {
        prompt: prompt,
        cwd: cwd,
        "approval-policy": "never",
        sandbox: "danger-full-access",
      },
    },
  };

  // Write initial JSON-RPC request FIRST (before tail -f starts)
  fs.writeFileSync(inputFile, JSON.stringify(request) + "\n");

  // Create shell script for detached execution
  const scriptFile = path.join(tmpDir, "run.sh");
  const shellScript = `#!/bin/bash
cd "${cwd}"
nohup sh -c 'tail -f "${inputFile}" | codex mcp-server' > "${outputFile}" 2> "${path.join(tmpDir, "stderr.log")}" &
echo $! > "${path.join(tmpDir, "pid")}"
disown
`;
  fs.writeFileSync(scriptFile, shellScript);
  fs.chmodSync(scriptFile, "755");

  // Launch detached Codex process via shell script
  const codexProcess = spawn(
    "bash",
    [scriptFile],
    {
      stdio: "ignore",
      cwd: cwd,
      detached: true,
    }
  );

  // Unref to allow parent to exit
  codexProcess.unref();

  // Wait for PID file to be created
  await new Promise(resolve => setTimeout(resolve, 500));

  // Read actual Codex PID from file
  let actualPid = codexProcess.pid?.toString() || "unknown";
  const pidFile = path.join(tmpDir, "pid");
  if (fs.existsSync(pidFile)) {
    actualPid = fs.readFileSync(pidFile, "utf-8").trim();
  }

  return {
    shellId: actualPid,
    outputFile,
    inputFile,
    process: codexProcess,
  };
}

/**
 * Kill a Codex agent process
 */
export function killCodexAgent(shellId: string): boolean {
  try {
    const pid = parseInt(shellId, 10);
    if (isNaN(pid)) {
      return false;
    }

    process.kill(pid, "SIGTERM");
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Check if a Codex agent process is still running
 */
export function isCodexAgentRunning(shellId: string): boolean {
  try {
    const pid = parseInt(shellId, 10);
    if (isNaN(pid)) {
      return false;
    }

    // Send signal 0 to check if process exists
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Read Codex output file
 */
export function readCodexOutput(outputFile: string): string {
  if (!fs.existsSync(outputFile)) {
    return "";
  }

  return fs.readFileSync(outputFile, "utf-8");
}

/**
 * Get temp directory for an agent
 */
export function getAgentTmpDir(agentId: string): string {
  return path.join(os.tmpdir(), `orchestrator-${agentId}`);
}

/**
 * Clean up agent temp files
 */
export function cleanupAgentFiles(agentId: string): void {
  const tmpDir = getAgentTmpDir(agentId);
  if (fs.existsSync(tmpDir)) {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}
