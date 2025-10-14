/**
 * Kill Agent Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import { removeWorktree } from "../git.js";
import { killCodexAgent, cleanupAgentFiles } from "../codex.js";
import { stopBackgroundParser } from "../background-parser.js";
import type { KillAgentInput, KillAgentOutput } from "../types.js";

export function createKillAgentTool(db: OrchestratorDB) {
	return {
		name: "kill_agent",
		schema: {
			title: "Kill Agent",
			description: "Stop a running agent",
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID to stop (e.g., 'executor-1760408478640'). Terminates the Codex process, stops background parser, and updates database status to 'killed'."
					),
				cleanup_worktree: z
					.boolean()
					.optional()
					.default(false)
					.describe(
						"Whether to remove the Git worktree directory after killing agent. 'true' deletes worktree and branch (useful after validation/merge). 'false' preserves worktree for manual inspection. Default: false."
					),
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

				const validationId = agent.current_validation_id;
				const now = new Date().toISOString();

				// Stop background parser
				stopBackgroundParser(args.agent_id);

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

				// Update validation session links if present
				if (validationId) {
					const session = db.getValidationSession(validationId);
					if (session) {
						if (agent.role === "executor") {
							db.updateValidationSession(validationId, {
								status: "rejected",
								finished_at: now,
							});
							if (session.validator_id) {
								db.updateAgent(session.validator_id, {
									current_validation_id: null,
									last_activity: now,
								});
							}
						} else if (agent.role === "validator") {
							db.updateValidationSession(validationId, {
								validator_id: null,
								status: "pending",
								started_at: null,
								finished_at: null,
							});
						}
					}
				}

				// Update database
				db.updateAgent(args.agent_id, {
					status: "killed",
					ended_at: now,
					current_validation_id: null,
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
