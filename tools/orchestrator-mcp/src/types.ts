/**
 * Type definitions for Orchestrator MCP Server
 */

// Agent roles
export type AgentRole = "executor" | "validator";

// Agent status
export type AgentStatus = "running" | "stuck" | "completed" | "killed";

// Agent record in database
export interface Agent {
  id: string;
  role: AgentRole;
  task_id: string | null;
  shell_id: string;
  worktree: string | null;
  prompt: string;
  status: AgentStatus;
  created_at: string;
  started_at: string | null;
  ended_at: string | null;
  events_count: number;
  commands_count: number;
  patches_count: number;
  files_created: number;
  last_activity: string | null;
  stuck_detected: number; // 0 or 1 (boolean)
  auto_recover_attempts: number;
}

// Agent log entry
export interface AgentLog {
  id?: number;
  agent_id: string;
  timestamp: string;
  event_type: string;
  content: string;
}

// Config entry
export interface Config {
  key: string;
  value: string;
}

// Tool input/output schemas

export interface LaunchAgentInput {
  role: AgentRole;
  task_id?: string;
  worktree: "auto" | "manual";
  prompt: string;
  cwd?: string; // if worktree is manual
  model?: string; // e.g. "gpt-5", "gpt-5-codex"
  reasoning_effort?: "low" | "medium" | "high"; // reasoning level
}

export interface LaunchAgentOutput {
  [key: string]: unknown;
  agent_id: string;
  shell_id: string;
  worktree?: string;
  status: AgentStatus;
}

export interface StatusInput {
  agent_id?: string;
  format: "summary" | "detailed";
}

export interface AgentSummary {
  agent_id: string;
  task_id: string | null;
  status: AgentStatus;
  events: number;
  files_created: number;
  uptime: string;
  last_activity: string | null;
  idle_minutes: number | null;
}

export interface AgentDetailed extends AgentSummary {
  shell_id: string;
  worktree: string | null;
  reasoning_count: number;
  commands_executed: number;
  patches_applied: number;
  last_activity: string | null;
  stuck_detection: {
    is_stuck: boolean;
    score: number;
  };
}

export interface StatusOutput {
  [key: string]: unknown;
  agents: AgentSummary[] | AgentDetailed[];
}

export interface GetLogsInput {
  agent_id: string;
  filter: "reasoning" | "messages" | "commands" | "errors" | "all";
  last?: number;
}

export interface LogEntry {
  type: "reasoning" | "message" | "command" | "output" | "error" | "tokens";
  timestamp: string;
  content: string;
  line_number?: number;
}

export interface GetLogsOutput {
  [key: string]: unknown;
  agent_id: string;
  logs: LogEntry[];
}

export interface KillAgentInput {
  agent_id: string;
  cleanup_worktree?: boolean;
}

export interface KillAgentOutput {
  [key: string]: unknown;
  agent_id: string;
  status: "killed";
  worktree_removed: boolean;
}

export interface AutoRecoverInput {
  enable: boolean;
  stuck_threshold_minutes?: number;
  max_retries?: number;
}

export interface AutoRecoverOutput {
  [key: string]: unknown;
  enabled: boolean;
  config: {
    stuck_threshold_minutes: number;
    max_retries: number;
  };
}

export interface ScaleInput {
  tasks: string[];
  role: AgentRole;
  worktree?: "auto" | "manual";
}

export interface ScaleOutput {
  [key: string]: unknown;
  launched: LaunchAgentOutput[];
  failed: Array<{ task_id: string; error: string }>;
}

export interface GetHistoryInput {
  from_date?: string;
  to_date?: string;
  task_id?: string;
  role?: AgentRole;
}

export interface HistoryEntry {
  agent_id: string;
  task_id: string | null;
  started: string;
  ended: string | null;
  duration: string;
  status: AgentStatus;
  events: number;
  result: "success" | "validation_failed" | "killed";
}

export interface GetHistoryOutput {
  [key: string]: unknown;
  sessions: HistoryEntry[];
}

export interface ContinueAgentInput {
  agent_id: string;
  prompt: string;
  model?: string; // e.g. "gpt-5", "gpt-5-codex"
  reasoning_effort?: "low" | "medium" | "high"; // reasoning level
}

export interface ContinueAgentOutput {
  [key: string]: unknown;
  agent_id: string;
  success: boolean;
  message: string;
}

export interface ListWorktreeFilesInput {
  agent_id: string;
  pattern?: string;
}

export interface ListWorktreeFilesOutput {
  [key: string]: unknown;
  agent_id: string;
  worktree: string;
  files: Array<{
    name: string;
    size: number;
    modified: string;
  }>;
}

export interface ReadWorktreeFileInput {
  agent_id: string;
  file_path: string;
}

export interface ReadWorktreeFileOutput {
  [key: string]: unknown;
  agent_id: string;
  file_path: string;
  content: string;
}

// Codex output parsing types
export interface CodexEvent {
  type: string;
  [key: string]: any;
}

export interface ParsedCodexOutput {
  total_events: number;
  reasoning_count: number;
  commands_count: number;
  patches_count: number;
  is_stuck: boolean;
  stuck_score: number;
}
