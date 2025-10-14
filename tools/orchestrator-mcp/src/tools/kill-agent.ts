/**
 * Kill Agent Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import { removeWorktree } from "../git.js";
import { killCodexAgent, cleanupAgentFiles } from "../codex.js";
import type { KillAgentInput, KillAgentOutput } from "../types.js";

export function createKillAgentTool(db: OrchestratorDB) {
	return {
		name: "kill_agent",
		schema: {
			title: "Kill Agent",
			description: "Stop a running agent",
			inputSchema: {
				agent_id: z.string(),
				cleanup_worktree: z.boolean().optional().default(false),
			},
		},
		handler: async (args: KillAgentInput) => {
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

				// Kill Codex process
				killCodexAgent(agent.shell_id);

				// Cleanup temp files
				cleanupAgentFiles(args.agent_id);

				// Remove worktree if requested
				let worktreeRemoved = false;
				if (args.cleanup_worktree && agent.worktree) {
					try {
						const projectRoot = process.env.PROJECT_ROOT || process.cwd();
						await removeWorktree(agent.worktree, projectRoot);
						worktreeRemoved = true;
					} catch (error) {
						// Worktree removal failed, but continue
						console.error(
							`Failed to remove worktree: ${error instanceof Error ? error.message : String(error)}`
						);
					}
				}

				// Update database
				db.updateAgent(args.agent_id, {
					status: "killed",
					ended_at: new Date().toISOString(),
				});

				const result: KillAgentOutput = {
					agent_id: args.agent_id,
					status: "killed",
					worktree_removed: worktreeRemoved,
				};

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
