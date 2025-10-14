import type { Agent, OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import { simpleGit } from "simple-git";
import * as path from "node:path";
import { continueCodexAgent } from "../codex.js";
import { createAgentSession } from "./agent-factory.js";
import { fileExists } from "./filesystem.js";
import { stopAllFlowWatchers, startFlowWatcher } from "./flow-watcher.js";
import type { ExecutorFlowState, FlowState, ValidatorFlowState } from "./flow-types.js";

interface RegisteredAgent {
  agentId: string;
  worktreePath: string;
  role: "executor" | "validator";
  taskId: string | null;
  reuseValidator?: boolean;
}

export class AutomationEngine {
  private readonly agents = new Map<string, RegisteredAgent>();
  private readonly flowSnapshots = new Map<string, FlowState>();
  private readonly executorSessions = new Map<
    string,
    { validationId: string; iteration: number; requestPath: string; validatorId?: string }
  >();
  private readonly executorValidatorMap = new Map<string, string>();
  private readonly validatorToExecutor = new Map<string, string>();
  private started = false;

  constructor(private readonly db: OrchestratorDB) {}

  start(existingAgents: RegisteredAgent[]): void {
    if (this.started) {
      return;
    }

    this.started = true;

    for (const agent of existingAgents) {
      this.registerAgent(agent);
    }
  }

  registerAgent(agent: RegisteredAgent): void {
    if (!agent.worktreePath) {
      return;
    }

    const normalized: RegisteredAgent = {
      ...agent,
      reuseValidator:
        agent.role === "executor" ? agent.reuseValidator ?? true : false,
    };

    this.agents.set(agent.agentId, normalized);

    startFlowWatcher(normalized.agentId, normalized.worktreePath, ({ state, agentId, flowPath }) => {
      return this.handleFlowUpdate(agentId, flowPath, state);
    });
  }

  private async handleFlowUpdate(agentId: string, flowPath: string, state: FlowState | null): Promise<void> {
    if (!state) {
      console.warn(`[automation] Invalid JSON in flow file ${flowPath} for ${agentId}`);
      return;
    }

    const registered = this.agents.get(agentId);
    if (!registered) {
      console.warn(`[automation] Flow update for unregistered agent ${agentId}`);
      return;
    }

    const agentRecord = this.db.getAgent(agentId);
    if (!agentRecord) {
      console.warn(`[automation] Agent ${agentId} not found in database`);
      return;
    }

    const previous = this.flowSnapshots.get(agentId);
    this.flowSnapshots.set(agentId, state);

    if (previous && this.isDuplicateState(previous, state)) {
      return;
    }

    if (state.role === "executor") {
      await this.handleExecutorFlow(registered, agentRecord, previous as ExecutorFlowState | undefined, state as ExecutorFlowState);
    } else {
      await this.handleValidatorFlow(registered, agentRecord, previous as ValidatorFlowState | undefined, state as ValidatorFlowState);
    }
  }

  stop(): void {
    stopAllFlowWatchers();
    this.started = false;
    this.agents.clear();
    this.flowSnapshots.clear();
    this.executorSessions.clear();
    this.executorValidatorMap.clear();
    this.validatorToExecutor.clear();
  }

  private isDuplicateState(previous: FlowState, current: FlowState): boolean {
    return (
      previous.status === current.status &&
      previous.iteration === current.iteration &&
      previous.timestamps?.updated_at === current.timestamps?.updated_at
    );
  }

  private async handleExecutorFlow(
    registered: RegisteredAgent,
    agentRecord: Agent,
    previous: ExecutorFlowState | undefined,
    current: ExecutorFlowState
  ): Promise<void> {
    switch (current.status) {
      case "ready_for_validation":
        await this.startValidationIfNeeded(registered, agentRecord, previous, current);
        break;
      case "needs_input":
        this.updateAgentStatus(agentRecord, "needs_input");
        break;
      case "done":
        this.updateAgentStatus(agentRecord, "completed", { ended_at: agentRecord.ended_at ?? new Date().toISOString() });
        break;
      case "working":
      default:
        if (agentRecord.status !== "running") {
          this.updateAgentStatus(agentRecord, "running");
        }
        break;
    }
  }

  private async handleValidatorFlow(
    registered: RegisteredAgent,
    validatorRecord: Agent,
    previous: ValidatorFlowState | undefined,
    current: ValidatorFlowState
  ): Promise<void> {
    const executorId = this.resolveExecutorIdForValidator(validatorRecord);
    if (!executorId) {
      console.warn(`[automation] Validator ${validatorRecord.id} update without executor context`);
      return;
    }

    const executorRecord = this.db.getAgent(executorId);
    if (!executorRecord) {
      console.warn(`[automation] Executor ${executorId} missing when processing validator ${validatorRecord.id}`);
      return;
    }

    if (current.status === "needs_input") {
      this.updateAgentStatus(validatorRecord, "stuck");
      return;
    }

    if (!current.report || !current.report.path) {
      return;
    }

    const reportPath = this.normalizeRelativePath(current.report.path);
    const absoluteReport = path.join(registered.worktreePath, reportPath);
    if (!fileExists(absoluteReport)) {
      console.warn(`[automation] Report ${absoluteReport} does not exist for validator ${validatorRecord.id}`);
      return;
    }

    const validationId = this.resolveValidationId(executorRecord, validatorRecord);
    if (!validationId) {
      console.warn(`[automation] Unable to resolve validation session for validator ${validatorRecord.id}`);
      return;
    }

    if (current.report.result === "approved") {
      await this.finalizeValidation({
        validationId,
        executor: executorRecord,
        validator: validatorRecord,
        approved: true,
        summary: current.summary ?? null,
        reportPath,
      });
    } else if (current.report.result === "rejected") {
      await this.finalizeValidation({
        validationId,
        executor: executorRecord,
        validator: validatorRecord,
        approved: false,
        summary: current.summary ?? null,
        reportPath,
        iteration: current.iteration,
      });
    }
  }

  private updateAgentStatus(agent: Agent, status: Agent["status"], extra: Record<string, string> = {}): void {
    if (agent.status === status) {
      return;
    }
    this.db.updateAgent(agent.id, {
      status,
      last_activity: new Date().toISOString(),
      ...extra,
    });
  }

  private normalizeRelativePath(relative: string): string {
    const normalized = relative.replace(/\\/g, "/");
    const segments = normalized
      .split("/")
      .filter((segment) => segment && segment !== "." && segment !== "..");
    return segments.join("/");
  }

  private async startValidationIfNeeded(
    registered: RegisteredAgent,
    agentRecord: Agent,
    previous: ExecutorFlowState | undefined,
    current: ExecutorFlowState
  ): Promise<void> {
    if (!current.request?.ready || !current.request.path) {
      return;
    }

    if (
      previous &&
      previous.status === "ready_for_validation" &&
      previous.iteration === current.iteration &&
      previous.request?.path === current.request.path
    ) {
      return;
    }

    const normalizedPath = this.normalizeRelativePath(current.request.path);
    const absoluteRequest = path.join(registered.worktreePath, normalizedPath);
    if (!fileExists(absoluteRequest)) {
      console.warn(`[automation] Validation request ${absoluteRequest} missing for executor ${agentRecord.id}`);
      return;
    }

    const existingEntry = this.executorSessions.get(agentRecord.id);
    if (existingEntry && existingEntry.iteration === current.iteration) {
      return;
    }

    if (agentRecord.current_validation_id) {
      const session = this.db.getValidationSession(agentRecord.current_validation_id);
      if (session && (session.status === "pending" || session.status === "in_progress")) {
        return;
      }
    }

    await this.startValidationWorkflow({
      registered,
      agentRecord,
      flow: current,
      requestPath: normalizedPath,
    });
  }

  private async startValidationWorkflow({
    registered,
    agentRecord,
    flow,
    requestPath,
  }: {
    registered: RegisteredAgent;
    agentRecord: Agent;
    flow: ExecutorFlowState;
    requestPath: string;
  }): Promise<void> {
    const validationId = `validation-${Date.now()}`;
    const branch = await this.detectBranch(registered.worktreePath);
    const now = new Date().toISOString();

    this.db.createValidationSession({
      id: validationId,
      task_id: flow.task_id ?? agentRecord.task_id,
      executor_id: agentRecord.id,
      validator_id: null,
      status: "pending",
      executor_worktree: registered.worktreePath,
      executor_branch: branch,
      request_path: requestPath,
      report_path: null,
      summary: flow.summary ?? null,
      requested_at: now,
      started_at: null,
      finished_at: null,
    });

    this.db.updateAgent(agentRecord.id, {
      status: "blocked",
      current_validation_id: validationId,
      last_activity: now,
    });

    try {
      const { validatorId, reused } = await this.launchValidatorForSession({
        validationId,
        registered,
        executor: agentRecord,
        flow,
        requestPath,
      });

      this.executorSessions.set(agentRecord.id, {
        validationId,
        iteration: flow.iteration,
        requestPath,
        validatorId,
      });

      if (!reused) {
        this.executorValidatorMap.set(agentRecord.id, validatorId);
      }
    } catch (error) {
      this.executorSessions.delete(agentRecord.id);
      this.db.updateAgent(agentRecord.id, {
        status: "running",
        last_activity: now,
      });
    }
  }

  private async detectBranch(worktreePath: string): Promise<string | null> {
    try {
      const git = simpleGit(worktreePath);
      const branch = await git.revparse(["--abbrev-ref", "HEAD"]);
      return branch.trim();
    } catch (error) {
      return null;
    }
  }

  private async launchValidatorForSession({
    validationId,
    registered,
    executor,
    flow,
    requestPath,
  }: {
    validationId: string;
    registered: RegisteredAgent;
    executor: Agent;
    flow: ExecutorFlowState;
    requestPath: string;
  }): Promise<{ validatorId: string; reused: boolean }> {
    try {
      const prompt = `Validate executor ${executor.id} iteration ${flow.iteration} for task ${flow.task_id ?? executor.task_id ?? "unknown"}. Review the request file at ${requestPath}, compare implementation to upstream requirements, run relevant tests, and produce a detailed report.`;
      const now = new Date().toISOString();

      // Reuse existing validator if configured and available
      if (registered.reuseValidator) {
        const existingId = this.executorValidatorMap.get(executor.id);
        if (existingId) {
          const v = this.db.getAgent(existingId);
          if (v) {
            this.db.updateValidationSession(validationId, {
              validator_id: existingId,
              status: "in_progress",
              started_at: now,
            });
            this.db.updateAgent(existingId, {
              current_validation_id: validationId,
              status: "running",
              last_activity: now,
            });
            this.validatorToExecutor.set(existingId, executor.id);
            // Nudge validator to process new request
            await continueCodexAgent(existingId, prompt, v.model ?? undefined, v.reasoning_effort ?? undefined);
            return { validatorId: existingId, reused: true };
          }
        }
      }

      // Otherwise, create a fresh validator
      const validatorName = `${executor.id}-validator-${flow.iteration}`;
      const session = await createAgentSession(
        {
          role: "validator",
          prompt,
          taskId: executor.task_id,
          worktreeMode: "manual",
          worktreeName: validatorName,
          cwd: registered.worktreePath,
        },
        {
          db: this.db,
          registerAgent: (agent) => this.registerAgent(agent),
        },
      );

      this.db.updateValidationSession(validationId, {
        validator_id: session.agent_id,
        status: "in_progress",
        started_at: now,
      });

      this.db.updateAgent(session.agent_id, {
        current_validation_id: validationId,
        last_activity: now,
      });

      this.validatorToExecutor.set(session.agent_id, executor.id);
      return { validatorId: session.agent_id, reused: false };
    } catch (error) {
      console.error(`[automation] Failed to launch validator for ${executor.id}:`, error);
      throw error;
    }
  }

  private resolveExecutorIdForValidator(validator: Agent): string | null {
    const cached = this.validatorToExecutor.get(validator.id);
    if (cached) {
      return cached;
    }

    if (validator.current_validation_id) {
      const session = this.db.getValidationSession(validator.current_validation_id);
      if (session) {
        this.validatorToExecutor.set(validator.id, session.executor_id);
        return session.executor_id;
      }
    }

    for (const [executorId, entry] of this.executorSessions.entries()) {
      if (entry.validatorId === validator.id) {
        this.validatorToExecutor.set(validator.id, executorId);
        return executorId;
      }
    }

    return null;
  }

  private resolveValidationId(executor: Agent, validator: Agent): string | null {
    const entry = this.executorSessions.get(executor.id);
    if (entry?.validationId) {
      return entry.validationId;
    }
    if (validator.current_validation_id) {
      return validator.current_validation_id;
    }
    if (executor.current_validation_id) {
      return executor.current_validation_id;
    }
    return null;
  }

  private async finalizeValidation({
    validationId,
    executor,
    validator,
    approved,
    summary,
    reportPath,
    iteration,
  }: {
    validationId: string;
    executor: Agent;
    validator: Agent;
    approved: boolean;
    summary: string | null;
    reportPath: string;
    iteration?: number;
  }): Promise<void> {
    const session = this.db.getValidationSession(validationId);
    if (!session) {
      console.warn(`[automation] Validation session ${validationId} not found`);
      return;
    }

    if (session.status === "approved" || session.status === "rejected") {
      return;
    }

    const now = new Date().toISOString();
    this.db.updateValidationSession(validationId, {
      status: approved ? "approved" : "rejected",
      report_path: reportPath,
      summary: summary ?? session.summary,
      finished_at: now,
    });

    if (approved) {
      this.db.updateAgent(executor.id, {
        status: "validated",
        last_activity: now,
        ended_at: executor.ended_at ?? now,
      });
      this.db.updateAgent(validator.id, {
        status: "completed",
        last_activity: now,
        ended_at: validator.ended_at ?? now,
      });
      this.executorSessions.delete(executor.id);
      this.validatorToExecutor.delete(validator.id);
    } else {
      this.db.updateAgent(executor.id, {
        status: "needs_fix",
        last_activity: now,
      });
      this.db.updateAgent(validator.id, {
        status: "completed",
        last_activity: now,
        ended_at: validator.ended_at ?? now,
      });

      await this.promptExecutorFix(executor, {
        reportPath,
        iteration: iteration ?? this.executorSessions.get(executor.id)?.iteration ?? 1,
      });

      this.executorSessions.delete(executor.id);
      this.validatorToExecutor.delete(validator.id);
    }
  }

  private async promptExecutorFix(
    executor: Agent,
    context: { reportPath: string; iteration: number },
  ): Promise<void> {
    const fixPrompt = `Validation report ${context.reportPath} lists required fixes. Address every issue, rerun tests, and produce a new validation request for iteration ${context.iteration + 1}. Update the flow file status to ready_for_validation when finished.`;

    const success = await continueCodexAgent(
      executor.id,
      fixPrompt,
      executor.model ?? undefined,
      executor.reasoning_effort ?? undefined,
    );

    if (success) {
      this.db.updateAgent(executor.id, {
        status: "running",
        last_activity: new Date().toISOString(),
      });
    } else {
      console.error(`[automation] Failed to send continue prompt to executor ${executor.id}`);
    }
  }
}
