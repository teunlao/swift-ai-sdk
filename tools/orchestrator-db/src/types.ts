/**
 * Shared type definitions for the orchestrator database and UI.
 */

export type AgentRole = "executor" | "validator";

export type AgentStatus =
  | "running"
  | "blocked"
  | "stuck"
  | "completed"
  | "killed"
  | "validated"
  | "merged"
  | "needs_fix"
  | "needs_input";

export type ValidationStatus =
  | "pending"
  | "in_progress"
  | "approved"
  | "rejected";

export interface Agent {
  id: string;
  role: AgentRole;
  task_id: string | null;
  shell_id: string;
  worktree: string | null;
  prompt: string;
  model: string | null;
  reasoning_effort: "low" | "medium" | "high" | null;
  status: AgentStatus;
  created_at: string;
  started_at: string | null;
  ended_at: string | null;
  events_count: number;
  commands_count: number;
  patches_count: number;
  files_created: number;
  last_activity: string | null;
  stuck_detected: number;
  auto_recover_attempts: number;
  current_validation_id: string | null;
}

export interface ValidationSession {
  id: string;
  task_id: string | null;
  executor_id: string;
  validator_id: string | null;
  status: ValidationStatus;
  executor_worktree: string | null;
  executor_branch: string | null;
  request_path: string | null;
  report_path: string | null;
  summary: string | null;
  requested_at: string;
  started_at: string | null;
  finished_at: string | null;
}

export interface AgentLog {
  id?: number;
  agent_id: string;
  timestamp: string;
  event_type: string;
  content: string;
}

export interface Config {
  key: string;
  value: string;
}

export interface HistoryEntry {
  agent_id: string;
  task_id: string | null;
  started: string;
  ended: string | null;
  duration: string;
  status: AgentStatus;
  events: number;
  result: "success" | "validation_failed" | "killed" | "validated" | "needs_fix";
}

export interface LogEntry {
  type: "reasoning" | "message" | "command" | "output" | "error" | "tokens";
  timestamp: string;
  content: string;
  line_number?: number;
}

export interface LaunchAgentInput {
  role: AgentRole;
  task_id?: string;
  worktree: "auto" | "manual";
  worktree_name: string;
  prompt: string;
  cwd?: string;
  model?: string;
  reasoning_effort?: "low" | "medium" | "high";
}

export interface LaunchAgentOutput {
  [key: string]: unknown;
  agent_id: string;
  shell_id: string;
  worktree?: string;
  branch?: string;
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
  validation?: {
    id: string;
    status: ValidationStatus;
  };
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

export interface ValidationSummaryOutput {
  [key: string]: unknown;
  session: ValidationSession;
}

export interface GetLogsInput {
  agent_id: string;
  filter: "reasoning" | "messages" | "commands" | "errors" | "all";
  last?: number;
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

export interface GetHistoryOutput {
  [key: string]: unknown;
  sessions: HistoryEntry[];
}

export interface RequestValidationInput {
  executor_id: string;
  task_id?: string;
  request_path?: string;
  summary?: string;
}

export interface RequestValidationOutput {
  [key: string]: unknown;
  validation_id: string;
  status: ValidationStatus;
  executor_id: string;
  executor_worktree: string | null;
}

export interface AssignValidatorInput {
  validation_id: string;
  validator_id: string;
}

export interface AssignValidatorOutput {
  [key: string]: unknown;
  validation_id: string;
  validator_id: string;
  status: ValidationStatus;
  worktree: string | null;
}

export interface SubmitValidationInput {
  validation_id: string;
  result: "approved" | "rejected";
  report_path: string;
  summary?: string;
}

export interface SubmitValidationOutput {
  [key: string]: unknown;
  validation_id: string;
  status: ValidationStatus;
  executor_status: AgentStatus;
  validator_status: AgentStatus;
}

export interface GetValidationInput {
  validation_id: string;
}

export interface ContinueAgentInput {
  agent_id: string;
  prompt: string;
  model?: string;
  reasoning_effort?: "low" | "medium" | "high";
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

export type OrchestratorEvent =
  | { type: "agent-created"; agent: Agent }
  | { type: "agent-updated"; agent: Agent }
  | { type: "agent-deleted"; agentId: string }
  | { type: "log-added"; agentId: string; log: Required<AgentLog> }
  | { type: "validation-created"; validation: ValidationSession }
  | { type: "validation-updated"; validation: ValidationSession }
  | { type: "config-updated"; config: Config };

export type EventListener = (event: OrchestratorEvent) => void;

export interface EventBus {
  publish(event: OrchestratorEvent): void;
  subscribe(listener: EventListener): () => void;
}

export interface OrchestratorDBOptions {
  /** Path to sqlite database file. */
  dbPath?: string;
  /** Path to SQL schema file. */
  schemaPath?: string;
  /** Custom event bus instance. */
  eventBus?: EventBus;
}
