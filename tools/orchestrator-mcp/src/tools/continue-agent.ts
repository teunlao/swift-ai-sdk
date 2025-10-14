/**
 * Continue Agent Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import { continueCodexAgent } from "../codex.js";
import type { ContinueAgentInput, ContinueAgentOutput } from "../types.js";

export function createContinueAgentTool(db: OrchestratorDB) {
	return {
		name: "continue_agent",
		schema: {
			title: "Continue Agent",
			description: "Send a new prompt to an existing agent session",
			inputSchema: {
				agent_id: z.string(),
				prompt: z.string(),
				model: z.string().optional(),
				reasoning_effort: z.enum(["low", "medium", "high"]).optional(),
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

				if (agent.status !== "running") {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent ${args.agent_id} is not running (status: ${agent.status})`,
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
