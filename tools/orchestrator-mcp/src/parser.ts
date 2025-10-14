/**
 * Codex Output Parser
 *
 * Parses Codex MCP output and extracts useful information.
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
 * Extract logs from Codex output
 */
export function extractLogs(
  output: string,
  filter: "reasoning" | "commands" | "errors" | "stuck" | "all" = "all",
  lastN?: number
): LogEntry[] {
  const lines = output.trim().split("\n");
  const logs: LogEntry[] = [];

  let lineNumber = 0;

  for (const line of lines) {
    lineNumber++;
    if (!line.trim()) continue;

    try {
      const json = JSON.parse(line);

      if (json.result && json.result.content) {
        for (const item of json.result.content) {
          if (item.type === "text" && item.text) {
            const event = inferEventType(item.text);
            const logEntry: LogEntry = {
              type: event.type as "reasoning" | "command" | "error",
              timestamp: new Date().toISOString(), // TODO: extract real timestamp
              content: item.text,
              line_number: lineNumber,
            };

            // Apply filter
            if (filter === "all" || filter === event.type) {
              logs.push(logEntry);
            } else if (filter === "stuck" && event.type === "reasoning") {
              logs.push(logEntry);
            }
          }
        }
      }

      if (json.error) {
        const logEntry: LogEntry = {
          type: "error",
          timestamp: new Date().toISOString(),
          content: json.error.message || JSON.stringify(json.error),
          line_number: lineNumber,
        };

        if (filter === "all" || filter === "errors") {
          logs.push(logEntry);
        }
      }
    } catch {
      continue;
    }
  }

  // Return last N logs if specified
  if (lastN && lastN > 0) {
    return logs.slice(-lastN);
  }

  return logs;
}

/**
 * Infer event type from content
 */
function inferEventType(content: string): { type: string } {
  const lower = content.toLowerCase();

  if (
    lower.includes("reasoning") ||
    lower.includes("thinking") ||
    lower.includes("analyzing")
  ) {
    return { type: "reasoning" };
  }

  if (
    lower.includes("command") ||
    lower.includes("bash") ||
    lower.includes("executing")
  ) {
    return { type: "commands" };
  }

  if (lower.includes("error") || lower.includes("failed")) {
    return { type: "errors" };
  }

  if (lower.includes("patch") || lower.includes("diff")) {
    return { type: "patch" };
  }

  return { type: "reasoning" }; // Default
}
