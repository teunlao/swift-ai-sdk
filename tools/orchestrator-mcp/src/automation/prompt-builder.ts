import { FLOW_DIR, REPORTS_DIR, REQUESTS_DIR } from "./constants.js";
import { EXECUTOR_SYSTEM_PROMPT, VALIDATOR_SYSTEM_PROMPT } from "../prompts/templates.js";

interface PromptContext {
  agentId: string;
  taskId: string | null;
  iteration?: number;
}

export function buildSystemPrompt(role: "executor" | "validator", context: PromptContext): string {
  const header = role === "executor" ? EXECUTOR_SYSTEM_PROMPT : VALIDATOR_SYSTEM_PROMPT;
  const iteration = context.iteration ?? 1;

  const dynamicContext = `\n\nRuntime context:\n- Agent ID: ${context.agentId}\n- Role: ${role}\n- Task ID: ${context.taskId ?? "unknown"}\n- Default iteration: ${iteration}\n- Flow file: ${FLOW_DIR}/${context.agentId}.json\n- Requests directory: ${REQUESTS_DIR}\n- Reports directory: ${REPORTS_DIR}`;

  return `${header}${dynamicContext}`;
}

export function buildCombinedPrompt(systemPrompt: string, userPrompt: string): string {
  return `System:\n${systemPrompt}\n\nUser:\n${userPrompt}`;
}
