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

export interface FlowBlocker {
  code: string;
  detail: string;
}

export interface FlowRequestMeta {
  path: string | null;
  ready: boolean;
}

export interface FlowReportMeta {
  path: string | null;
  result: "approved" | "rejected" | null;
}

export interface FlowTimestamps {
  updated_at: string;
}

export interface BaseFlowState<TStatus extends string> {
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
}

export type ExecutorFlowState = BaseFlowState<ExecutorFlowStatus> & {
  role: "executor";
};

export type ValidatorFlowState = BaseFlowState<ValidatorFlowStatus> & {
  role: "validator";
};

export type FlowState = ExecutorFlowState | ValidatorFlowState;
