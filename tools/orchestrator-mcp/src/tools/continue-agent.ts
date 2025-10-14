/**
 * Continue Agent Tool
 */

import type {
	ContinueAgentInput,
	ContinueAgentOutput,
	OrchestratorDB,
} from "@swift-ai-sdk/orchestrator-db";
import { z } from "zod";
import { continueCodexAgent } from "../codex.js";

export function createContinueAgentTool(db: OrchestratorDB) {
	return {
		name: "continue_agent",
		schema: {
			title: "Continue Agent",
			description: `Send follow-up instruction to a running agent.

WHAT IT DOES:
Continues an existing agent session with a new prompt. Automation uses this internally when validator rejects work; you can still call it manually for guidance or to resume a paused agent.

WHEN TO USE:
- Guide stuck agent with clarification or hint
- Request status update ("What are you doing?")
- Provide additional context or corrections
- **⚠️  VALIDATION LOOP: MANDATORY after validator rejects** (see below)
- Escalate to stronger model for complex issues

🔁 AUTOMATION CONTEXT:
- When automation is active, the orchestrator sends the fix-it prompt automatically after a rejection.
- Use this tool if automation was disabled, you need additional instructions, or you want to escalate the model.

RESULT: Returns success/failure. Use get_logs() to see agent's response.

EXAMPLE:
continue_agent(agent_id="executor-123", prompt="Fix all 4 bugs from validation report .validation/reports/report-snake-2025-10-14.md, then create new validation request")`,
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID to send prompt to (e.g., 'executor-1760408478640'). Agent must be in 'running' status. Use status tool to check agent state before continuing.",
					),
				prompt: z
					.string()
					.describe(
						"Follow-up instruction or clarification for the agent. Used to guide stuck agents, provide additional context, request status update, or correct course. Example: 'Run tests again after fixing the import' or 'Check the validation report in .validation/reports/'",
					),
				model: z
					.string()
					.optional()
					.describe(
						"Override model for this continuation (e.g., 'claude-sonnet-4', 'o1'). Useful for escalating complex problems to more capable models. If omitted, uses agent's current model.",
					),
				reasoning_effort: z
					.enum(["low", "medium", "high"])
					.optional()
					.describe(
						"Reasoning depth for this specific prompt. 'high' for debugging complex issues, 'medium' for standard follow-ups, 'low' for simple status checks. If omitted, uses agent's default.",
					),
			},
		},
		handler: async (args: ContinueAgentInput) => {
			try {
				const agent = db.getAgent(args.agent_id);
				if (!agent) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent not found: ${args.agent_id}`,
							},
						],
					};
				}

				const allowedStatuses = new Set(["running", "needs_fix"]);
				if (!allowedStatuses.has(agent.status)) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent ${args.agent_id} is not active (status: ${agent.status})`,
							},
						],
					};
				}

				// Send new prompt to existing session
				const model = args.model ?? agent.model ?? "gpt-5-codex";
				const reasoning =
					args.reasoning_effort ?? agent.reasoning_effort ?? "medium";
				const success = await continueCodexAgent(
					args.agent_id,
					args.prompt,
					model,
					reasoning,
				);

				const result: ContinueAgentOutput = {
					agent_id: args.agent_id,
					success,
					message: success
						? "Prompt sent to agent successfully"
						: "Failed to send prompt to agent",
				};

				// Update last activity
				db.updateAgent(args.agent_id, {
					last_activity: new Date().toISOString(),
					model,
					reasoning_effort: reasoning,
				});

				return {
					content: [
						{
							type: "text" as const,
							text: JSON.stringify(result, null, 2),
						},
					],
					structuredContent: result,
				};
			} catch (error) {
				return {
					content: [
						{
							type: "text" as const,
							text: `Error: ${error instanceof Error ? error.message : String(error)}`,
						},
					],
				};
			}
		},
	};
}
