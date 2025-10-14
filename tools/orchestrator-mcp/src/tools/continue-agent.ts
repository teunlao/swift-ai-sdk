/**
 * Continue Agent Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  ContinueAgentInput,
  ContinueAgentOutput,
} from "@swift-ai-sdk/orchestrator-db";
import { continueCodexAgent } from "../codex.js";

export function createContinueAgentTool(db: OrchestratorDB) {
	return {
		name: "continue_agent",
		schema: {
			title: "Continue Agent",
			description: "Send a new prompt to an existing agent session",
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID to send prompt to (e.g., 'executor-1760408478640'). Agent must be in 'running' status. Use status tool to check agent state before continuing."
					),
				prompt: z
					.string()
					.describe(
						"Follow-up instruction or clarification for the agent. Used to guide stuck agents, provide additional context, request status update, or correct course. Example: 'Run tests again after fixing the import' or 'Check the validation report in .validation/reports/'"
					),
				model: z
					.string()
					.optional()
					.describe(
						"Override model for this continuation (e.g., 'claude-sonnet-4', 'o1'). Useful for escalating complex problems to more capable models. If omitted, uses agent's current model."
					),
				reasoning_effort: z
					.enum(["low", "medium", "high"])
					.optional()
					.describe(
						"Reasoning depth for this specific prompt. 'high' for debugging complex issues, 'medium' for standard follow-ups, 'low' for simple status checks. If omitted, uses agent's default."
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
				const success = await continueCodexAgent(
					args.agent_id,
					args.prompt,
					args.model,
					args.reasoning_effort
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
