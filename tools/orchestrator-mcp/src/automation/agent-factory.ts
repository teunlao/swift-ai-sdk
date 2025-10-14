import type { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import { createWorktree, normalizeWorktreeName } from "../git.js";
import { launchCodexAgent } from "../codex.js";
import { startBackgroundParser } from "../background-parser.js";
import { buildCombinedPrompt, buildSystemPrompt } from "./prompt-builder.js";

export interface CreateAgentParams {
  agentId?: string;
  role: "executor" | "validator";
  prompt: string;
  taskId?: string | null;
  worktreeMode: "auto" | "manual";
  worktreeName: string;
  cwd?: string;
  model?: string;
  reasoningEffort?: "low" | "medium" | "high";
}

export interface CreateAgentResult {
  agent_id: string;
  shell_id: string;
  worktree: string;
  branch?: string;
  created: boolean;
}

export async function createAgentSession(
  params: CreateAgentParams,
  context: {
    db: OrchestratorDB;
    registerAgent: (agent: {
      agentId: string;
      role: "executor" | "validator";
      worktreePath: string;
      taskId: string | null;
    }) => void;
  }
): Promise<CreateAgentResult> {
  const agentId = params.agentId ?? `${params.role}-${Date.now()}`;
  const projectRoot = process.env.PROJECT_ROOT || process.cwd();

  let worktreePath: string;
  let worktreeCreated = false;
  let branch: string | undefined;

  if (params.worktreeMode === "auto") {
    const worktreeInfo = await createWorktree(agentId, projectRoot, params.worktreeName);
    worktreePath = worktreeInfo.path;
    worktreeCreated = true;
    branch = worktreeInfo.branch;
  } else {
    worktreePath = params.cwd || projectRoot;
    ({ branch } = normalizeWorktreeName(params.worktreeName));
  }

  const systemPrompt = buildSystemPrompt(params.role, {
    agentId,
    taskId: params.taskId ?? null,
  });
  const combinedPrompt = buildCombinedPrompt(systemPrompt, params.prompt);

  const defaultModel = params.model ?? "gpt-5-codex";
  const defaultReasoning = params.reasoningEffort ?? "medium";

  const codexResult = await launchCodexAgent(
    agentId,
    combinedPrompt,
    worktreePath,
    params.role,
    defaultModel,
    defaultReasoning,
  );

  context.db.createAgent({
    id: agentId,
    role: params.role,
    task_id: params.taskId ?? null,
    shell_id: codexResult.shellId,
    worktree: worktreePath,
    prompt: params.prompt,
    model: defaultModel,
    reasoning_effort: defaultReasoning,
    status: "running",
    created_at: new Date().toISOString(),
    started_at: new Date().toISOString(),
    ended_at: null,
    last_activity: new Date().toISOString(),
    current_validation_id: null,
  });

  startBackgroundParser(agentId, codexResult.outputFile, context.db);
  context.registerAgent({
    agentId,
    role: params.role,
    worktreePath,
    taskId: params.taskId ?? null,
  });

  return {
    agent_id: agentId,
    shell_id: codexResult.shellId,
    worktree: worktreePath,
    branch,
    created: worktreeCreated,
  };
}
