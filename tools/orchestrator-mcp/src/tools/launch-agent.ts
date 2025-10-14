/**
 * Launch Agent Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import { createWorktree } from "../git.js";
import { launchCodexAgent } from "../codex.js";
import type { LaunchAgentInput, LaunchAgentOutput } from "../types.js";

export function createLaunchAgentTool(db: OrchestratorDB) {
	return {
		name: "launch_agent",
		schema: {
			title: "Launch Agent",
			description: "Launch a new Codex agent in a worktree",
			inputSchema: {
				role: z.enum(["executor", "validator"]),
				task_id: z.string().optional(),
				worktree: z.enum(["auto", "manual"]),
				prompt: z.string(),
				cwd: z.string().optional(),
			},
		},
		handler: async (args: LaunchAgentInput) => {
			try {
				const agent_id = `${args.role}-${Date.now()}`;
				const projectRoot = process.env.PROJECT_ROOT || process.cwd();

				let worktreePath: string;
				let worktreeCreated = false;

				// Handle worktree creation
				if (args.worktree === "auto") {
					const worktreeInfo = await createWorktree(agent_id, projectRoot);
					worktreePath = worktreeInfo.path;
					worktreeCreated = true;
				} else {
					// Manual mode - use provided cwd or project root
					worktreePath = args.cwd || projectRoot;
				}

				// Launch Codex agent
				const codexResult = await launchCodexAgent(
					agent_id,
					args.prompt,
					worktreePath,
					args.role
				);

				const result: LaunchAgentOutput = {
					agent_id,
					shell_id: codexResult.shellId,
					worktree: worktreeCreated ? worktreePath : undefined,
					status: "running",
				};

				// Store in database
				db.createAgent({
					id: agent_id,
					role: args.role,
					task_id: args.task_id || null,
					shell_id: codexResult.shellId,
					worktree: worktreePath,
					prompt: args.prompt,
					status: "running",
					created_at: new Date().toISOString(),
					started_at: new Date().toISOString(),
					ended_at: null,
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
