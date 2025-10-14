/**
 * Scale Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  ScaleInput,
  ScaleOutput,
  LaunchAgentOutput,
} from "@swift-ai-sdk/orchestrator-db";
import { createWorktree } from "../git.js";
import { launchCodexAgent } from "../codex.js";

export function createScaleTool(db: OrchestratorDB) {
	return {
		name: "scale",
		schema: {
			title: "Scale Agents",
			description: "Launch multiple agents in parallel",
			inputSchema: {
				tasks: z
					.array(z.string())
					.describe(
						"Array of task IDs to launch agents for (e.g., ['4.3', '5.1', '10.2']). Each task gets dedicated agent with isolated worktree. Agents run in parallel without conflicts. NOTE: Currently uses simple prompt 'Work on task X'; Task Master integration coming soon for full task details."
					),
				role: z
					.enum(["executor", "validator"])
					.describe(
						"Role for all launched agents. 'executor' implements features in parallel. 'validator' checks multiple implementations simultaneously. All agents in batch use same role."
					),
				worktree: z
					.enum(["auto", "manual"])
					.default("auto")
					.describe(
						"Worktree mode for all agents. 'auto' (recommended for scale): creates isolated worktrees for true parallel work. 'manual': uses PROJECT_ROOT (NOT recommended for parallel - causes conflicts). Default: 'auto'."
					),
			},
		},
		handler: async (args: ScaleInput) => {
			const launched: LaunchAgentOutput[] = [];
			const failed: Array<{ task_id: string; error: string }> = [];

			// Launch agents in parallel
			const results = await Promise.allSettled(
				args.tasks.map(async (task_id) => {
					// For MVP, use simple prompt
					// TODO: Integrate with Task Master to get detailed prompt
					const prompt = `Work on task ${task_id}`;

					const agent_id = `${args.role}-${Date.now()}-${Math.random().toString(36).substring(7)}`;
					const projectRoot = process.env.PROJECT_ROOT || process.cwd();

					let worktreePath: string;
					let worktreeCreated = false;

					// Handle worktree creation
					if (args.worktree === "auto") {
						const worktreeInfo = await createWorktree(agent_id, projectRoot);
						worktreePath = worktreeInfo.path;
						worktreeCreated = true;
					} else {
						worktreePath = projectRoot;
					}

					// Launch Codex agent
					const codexResult = await launchCodexAgent(
						agent_id,
						prompt,
						worktreePath,
						args.role
					);

					// Store in database
					db.createAgent({
						id: agent_id,
						role: args.role,
						task_id: task_id,
						shell_id: codexResult.shellId,
						worktree: worktreePath,
						prompt: prompt,
				status: "running",
				created_at: new Date().toISOString(),
				started_at: new Date().toISOString(),
				ended_at: null,
				last_activity: new Date().toISOString(),
				current_validation_id: null,
			});

					return {
						agent_id,
						shell_id: codexResult.shellId,
						worktree: worktreeCreated ? worktreePath : undefined,
						status: "running" as const,
						task_id,
					};
				})
			);

			// Process results
			results.forEach((result, index) => {
				if (result.status === "fulfilled") {
					launched.push(result.value);
				} else {
					failed.push({
						task_id: args.tasks[index],
						error:
							result.reason instanceof Error
								? result.reason.message
								: String(result.reason),
					});
				}
			});

			const output: ScaleOutput = {
				launched,
				failed,
			};

			return {
				content: [
					{
						type: "text" as const,
						text: JSON.stringify(output, null, 2),
					},
				],
				structuredContent: output,
			};
		},
	};
}
