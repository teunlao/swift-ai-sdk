/**
 * Background Parser for Codex Output
 *
 * Watches output.json files in real-time and parses events into database.
 */

import * as fs from "node:fs";
import type { OrchestratorDB } from "./database.js";

interface Watcher {
  agent_id: string;
  outputFile: string;
  intervalId: NodeJS.Timeout;
  lastOffset: number;
  lastParsedRequestId: number;
}

// Global state: active watchers
const watchers = new Map<string, Watcher>();

/**
 * Start background parser for an agent
 */
export function startBackgroundParser(
  agent_id: string,
  outputFile: string,
  db: OrchestratorDB
): void {
  // Protection: prevent duplicates
  if (watchers.has(agent_id)) {
    console.error(`⚠️  Watcher already exists for ${agent_id}, skipping`);
    return;
  }

  let lastOffset = 0;

  // Accumulators for delta events (same as extractLogs)
  let currentReasoning: string[] = [];
  let currentMessage: string[] = [];

  // Polling every second
  const intervalId = setInterval(() => {
    try {
      // Check if file exists
      if (!fs.existsSync(outputFile)) {
        return;
      }

      const stats = fs.statSync(outputFile);
      const currentSize = stats.size;

      // No new data
      if (currentSize <= lastOffset) {
        return;
      }

      // Read only new lines
      const stream = fs.createReadStream(outputFile, {
        start: lastOffset,
        end: currentSize,
        encoding: "utf-8",
      });

      let buffer = "";

      stream.on("data", (chunk) => {
        buffer += chunk;
      });

      stream.on("end", () => {
        const lines = buffer.split("\n");

        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const json = JSON.parse(line);

            // Parse only codex/event messages
            if (json.method !== "codex/event") continue;

            const msg = json.params?.msg;
            if (!msg) continue;

            const msgType = msg.type;
            const timestamp = new Date().toISOString();

            // === Reasoning (internal thinking) ===
            if (msgType === "agent_reasoning_delta") {
              const delta = msg.delta || "";
              currentReasoning.push(delta);
            } else if (msgType === "agent_reasoning") {
              // Finalize: merge all deltas
              if (currentReasoning.length > 0) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "reasoning",
                  content: currentReasoning.join(""),
                });
                currentReasoning = [];
              }
              // Also add complete reasoning if present
              const text = msg.text || "";
              if (text) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "reasoning",
                  content: text,
                });
              }
            }

            // === Messages (final answers to user) ===
            else if (msgType === "agent_message_delta") {
              const delta = msg.delta || "";
              currentMessage.push(delta);
            } else if (msgType === "agent_message") {
              // Finalize: merge all deltas
              if (currentMessage.length > 0) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "message",
                  content: currentMessage.join(""),
                });
                currentMessage = [];
              }
              // Also add complete message if present
              const text = msg.text || msg.message || "";
              if (text) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "message",
                  content: text,
                });
              }
            }

            // === Commands ===
            else if (msgType === "exec_command_begin") {
              const cmd = Array.isArray(msg.command)
                ? msg.command.join(" ")
                : msg.command || "";
              if (cmd) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "command",
                  content: cmd,
                });
              }
            }

            // === Command output and errors ===
            else if (msgType === "exec_command_end") {
              const exitCode = msg.exit_code || 0;
              const stdout = (msg.stdout || "").substring(0, 200);

              if (exitCode !== 0) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "error",
                  content: `Exit code: ${exitCode}`,
                });
              } else if (stdout) {
                db.addLog({
                  agent_id,
                  timestamp,
                  event_type: "output",
                  content: stdout,
                });
              }
            }

            // === Token count ===
            else if (msgType === "token_count") {
              const info = msg.info;
              if (info) {
                const total = info.total_token_usage || {};
                const tokens = total.total_tokens || 0;
                const cached = total.cached_input_tokens || 0;
                if (tokens > 0) {
                  db.addLog({
                    agent_id,
                    timestamp,
                    event_type: "tokens",
                    content: `Tokens: ${tokens.toLocaleString()} (cached: ${cached.toLocaleString()})`,
                  });
                }
              }
            }

            // Update last_activity in agents table
            db.updateAgent(agent_id, {
              last_activity: timestamp,
            });
          } catch (err) {
            // Skip invalid JSON lines
          }
        }

        lastOffset = currentSize;
      });

      stream.on("error", () => {
        // Handle read errors silently
      });
    } catch {
      // Handle file access errors silently
    }
  }, 1000); // Poll every second

  // Store watcher
  watchers.set(agent_id, {
    agent_id,
    outputFile,
    intervalId,
    lastOffset,
    lastParsedRequestId: 0,
  });

  console.error(`✅ Background parser started for ${agent_id}`);
}

/**
 * Stop background parser for an agent
 */
export function stopBackgroundParser(agent_id: string): void {
  const watcher = watchers.get(agent_id);
  if (!watcher) {
    console.error(`⚠️  No watcher found for ${agent_id}`);
    return;
  }

  clearInterval(watcher.intervalId);
  watchers.delete(agent_id);

  console.error(`🛑 Background parser stopped for ${agent_id}`);
}

/**
 * Stop all background parsers
 */
export function stopAllBackgroundParsers(): void {
  for (const watcher of watchers.values()) {
    clearInterval(watcher.intervalId);
  }
  watchers.clear();
  console.error(`🛑 All background parsers stopped`);
}

/**
 * Get active watcher count
 */
export function getActiveWatcherCount(): number {
  return watchers.size;
}

/**
 * Check if watcher exists for agent
 */
export function hasWatcher(agent_id: string): boolean {
  return watchers.has(agent_id);
}
