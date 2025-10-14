import type { Agent, AgentLog, ValidationSession } from "./db";

export type ExecutorFlowStatus =
	| "working"
	| "ready_for_validation"
	| "needs_input"
	| "done";

export type ValidatorFlowStatus =
	| "reviewing"
	| "awaiting_executor"
	| "needs_input"
	| "done";

export type FlowRole = "executor" | "validator";

export type FlowBlocker = {
	code: string;
	detail: string;
};

export type FlowRequestMeta = {
	path: string | null;
	ready: boolean;
};

export type FlowReportMeta = {
	path: string | null;
	result: "approved" | "rejected" | null;
};

export type FlowTimestamps = {
	updated_at: string;
};

export type BaseFlowState<TStatus extends string> = {
	agent_id: string;
	role: FlowRole;
	task_id: string | null;
	iteration: number;
	status: TStatus;
	summary: string | null;
	request: FlowRequestMeta;
	report: FlowReportMeta;
	blockers: FlowBlocker[];
	timestamps: FlowTimestamps;
};

export type ExecutorFlowState = BaseFlowState<ExecutorFlowStatus> & {
	role: "executor";
};

export type ValidatorFlowState = BaseFlowState<ValidatorFlowStatus> & {
	role: "validator";
};

export type FlowState = ExecutorFlowState | ValidatorFlowState;

export type AgentFlow = {
	raw: string;
	parsed: FlowState | null;
	path: string;
};

export type AgentSummary = {
  id: string;
  role: Agent["role"];
  status: Agent["status"];
  taskId: string | null;
  worktree: string | null;
  shellId: string;
  model: string | null;
  reasoningEffort: Agent["reasoning_effort"];
  createdAt: string;
  startedAt: string | null;
  endedAt: string | null;
  lastActivity: string | null;
  events: number;
	commands: number;
	patches: number;
	filesCreated: number;
	validation?: {
		id: string;
		status: ValidationSession["status"];
	};
};

export function toAgentSummary(
	agent: Agent,
	validation?: ValidationSession | null,
): AgentSummary {
  return {
    id: agent.id,
    role: agent.role,
    status: agent.status,
    taskId: agent.task_id,
    worktree: agent.worktree,
    shellId: agent.shell_id,
    model: agent.model ?? null,
    reasoningEffort: agent.reasoning_effort ?? null,
    createdAt: agent.created_at,
    startedAt: agent.started_at,
    endedAt: agent.ended_at,
    lastActivity: agent.last_activity,
    events: agent.events_count,
		commands: agent.commands_count,
		patches: agent.patches_count,
		filesCreated: agent.files_created,
		validation: validation
			? { id: validation.id, status: validation.status }
			: undefined,
	};
}

export type ValidationSummary = {
	id: string;
	taskId: string | null;
	executorId: string;
	validatorId: string | null;
	status: ValidationSession["status"];
	executorWorktree: string | null;
	executorBranch: string | null;
	requestPath: string | null;
	reportPath: string | null;
	summary: string | null;
	requestedAt: string;
	startedAt: string | null;
	finishedAt: string | null;
};

export function toValidationSummary(
	session: ValidationSession,
): ValidationSummary {
	return {
		id: session.id,
		taskId: session.task_id,
		executorId: session.executor_id,
		validatorId: session.validator_id,
		status: session.status,
		executorWorktree: session.executor_worktree,
		executorBranch: session.executor_branch,
		requestPath: session.request_path,
		reportPath: session.report_path,
		summary: session.summary,
		requestedAt: session.requested_at,
		startedAt: session.started_at,
		finishedAt: session.finished_at,
	};
}

export type LogDTO = {
	id?: number;
	timestamp: string;
	type: string;
	content: string;
};

export function toLogDto(log: AgentLog): LogDTO {
	return {
		id: log.id,
		timestamp: log.timestamp,
		type: log.event_type,
		content: log.content,
	};
}

export type AgentDetail = AgentSummary & {
	prompt: string | null;
	flow: AgentFlow | null;
};

export type AgentDetailPayload = {
	agent: AgentDetail;
	validation: ValidationSummary | null;
	validationHistory: ValidationSummary[];
	logs: LogDTO[];
};
