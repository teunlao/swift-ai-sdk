/**
 * Codex Output Parser
 *
 * Parses Codex MCP output and extracts useful information.
 * Based on scripts/parse-codex-output.py implementation.
 */

import type { ParsedCodexOutput, LogEntry } from "./types.js";

export interface CodexEvent {
  type: string;
  timestamp?: string;
  content?: string;
  [key: string]: any;
}

/**
 * Parse Codex output from JSON-RPC responses
 */
export function parseCodexOutput(output: string): ParsedCodexOutput {
  const lines = output.trim().split("\n");
  const events: CodexEvent[] = [];

  let reasoningCount = 0;
  let commandsCount = 0;
  let patchesCount = 0;

  for (const line of lines) {
    if (!line.trim()) continue;

    try {
      const json = JSON.parse(line);

      // Skip if not a valid JSON-RPC response
      if (!json.jsonrpc) continue;

      // Extract events from result
      if (json.result) {
        const event = extractEvent(json.result);
        if (event) {
          events.push(event);

          // Count event types
          if (event.type === "reasoning") reasoningCount++;
          if (event.type === "command") commandsCount++;
          if (event.type === "patch") patchesCount++;
        }
      }

      // Extract error events
      if (json.error) {
        events.push({
          type: "error",
          content: json.error.message || JSON.stringify(json.error),
        });
      }
    } catch (error) {
      // Skip invalid JSON lines
      continue;
    }
  }

  // Detect stuck state (heuristic: many reasoning, few actions)
  const isStuck =
    reasoningCount > 5 && commandsCount === 0 && patchesCount === 0;
  const stuckScore = isStuck ? calculateStuckScore(events) : 0;

  return {
    total_events: events.length,
    reasoning_count: reasoningCount,
    commands_count: commandsCount,
    patches_count: patchesCount,
    is_stuck: isStuck,
    stuck_score: stuckScore,
  };
}

/**
 * Extract event from Codex result
 */
function extractEvent(result: any): CodexEvent | null {
  // Check for content array (tool call result)
  if (result.content && Array.isArray(result.content)) {
    for (const item of result.content) {
      if (item.type === "text" && item.text) {
        // Try to parse as JSON
        try {
          const parsed = JSON.parse(item.text);
          if (parsed.type) {
            return {
              type: parsed.type,
              content: parsed.content || item.text,
              ...parsed,
            };
          }
        } catch {
          // Not JSON, treat as text content
        }

        // Infer type from content
        if (item.text.includes("reasoning") || item.text.includes("thinking")) {
          return { type: "reasoning", content: item.text };
        }
        if (item.text.includes("command") || item.text.includes("bash")) {
          return { type: "command", content: item.text };
        }
        if (item.text.includes("patch") || item.text.includes("diff")) {
          return { type: "patch", content: item.text };
        }
      }
    }
  }

  return null;
}

/**
 * Calculate stuck score (0-100)
 */
function calculateStuckScore(events: CodexEvent[]): number {
  if (events.length === 0) return 0;

  let reasoningStreak = 0;
  let maxReasoningStreak = 0;

  for (const event of events) {
    if (event.type === "reasoning") {
      reasoningStreak++;
      maxReasoningStreak = Math.max(maxReasoningStreak, reasoningStreak);
    } else {
      reasoningStreak = 0;
    }
  }

  // Score based on reasoning streak length
  // 0-2: not stuck (0)
  // 3-5: possibly stuck (30-50)
  // 6+: likely stuck (60-100)
  if (maxReasoningStreak <= 2) return 0;
  if (maxReasoningStreak <= 5) return 30 + (maxReasoningStreak - 3) * 10;
  return Math.min(60 + (maxReasoningStreak - 6) * 10, 100);
}

/**
 * Extract logs from Codex output with delta merging
 *
 * Based on Python's merge_deltas() implementation.
 */
export function extractLogs(
  output: string,
  filter: "reasoning" | "messages" | "commands" | "errors" | "all" = "all",
  lastN?: number
): LogEntry[] {
  const lines = output.trim().split("\n");
  const logs: LogEntry[] = [];

  // Accumulators for delta events
  let currentReasoning: string[] = [];
  let currentMessage: string[] = [];

  for (const line of lines) {
    if (!line.trim()) continue;

    try {
      const json = JSON.parse(line);

      // Parse only codex/event messages
      if (json.method !== "codex/event") continue;

      const msg = json.params?.msg;
      if (!msg) continue;

      const msgType = msg.type;

      // === Reasoning (internal thinking) ===
      if (msgType === "agent_reasoning_delta") {
        const delta = msg.delta || "";
        currentReasoning.push(delta);
      } else if (msgType === "agent_reasoning") {
        // Finalize: merge all deltas
        if (currentReasoning.length > 0) {
          logs.push({
            type: "reasoning",
            content: currentReasoning.join(""),
            timestamp: new Date().toISOString(),
          });
          currentReasoning = [];
        }
        // Also add complete reasoning if present
        const text = msg.text || "";
        if (text) {
          logs.push({
            type: "reasoning",
            content: text,
            timestamp: new Date().toISOString(),
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
          logs.push({
            type: "message",
            content: currentMessage.join(""),
            timestamp: new Date().toISOString(),
          });
          currentMessage = [];
        }
        // Also add complete message if present
        const text = msg.text || msg.message || "";
        if (text) {
          logs.push({
            type: "message",
            content: text,
            timestamp: new Date().toISOString(),
          });
        }
      }

      // === Commands ===
      else if (msgType === "exec_command_begin") {
        const cmd = Array.isArray(msg.command)
          ? msg.command.join(" ")
          : msg.command || "";
        if (cmd) {
          logs.push({
            type: "command",
            content: cmd,
            timestamp: new Date().toISOString(),
          });
        }
      }

      // === Command output and errors ===
      else if (msgType === "exec_command_end") {
        const exitCode = msg.exit_code || 0;
        const stdout = (msg.stdout || "").substring(0, 200); // First 200 chars

        if (exitCode !== 0) {
          logs.push({
            type: "error",
            content: `Exit code: ${exitCode}`,
            timestamp: new Date().toISOString(),
          });
        } else if (stdout) {
          logs.push({
            type: "output",
            content: stdout,
            timestamp: new Date().toISOString(),
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
            logs.push({
              type: "tokens",
              content: `Tokens: ${tokens.toLocaleString()} (cached: ${cached.toLocaleString()})`,
              timestamp: new Date().toISOString(),
            });
          }
        }
      }
    } catch {
      // Skip invalid JSON lines
      continue;
    }
  }

  // Apply filter
  let filtered = logs;
  if (filter !== "all") {
    const typeMap: Record<string, string> = {
      reasoning: "reasoning",
      messages: "message",
      commands: "command",
      errors: "error",
    };
    const targetType = typeMap[filter];
    if (targetType) {
      filtered = logs.filter((log) => log.type === targetType);
    }
  }

  // Apply lastN
  if (lastN && lastN > 0) {
    filtered = filtered.slice(-lastN);
  }

  return filtered;
}
