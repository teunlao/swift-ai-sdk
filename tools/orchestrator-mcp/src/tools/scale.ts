/**
 * Scale Tool
 */

import type {
	LaunchAgentOutput,
	OrchestratorDB,
	ScaleInput,
	ScaleOutput,
} from "@swift-ai-sdk/orchestrator-db";
import { z } from "zod";
import { AutomationEngine } from "../automation/engine.js";
import { createAgentSession } from "../automation/agent-factory.js";

export function createScaleTool(db: OrchestratorDB, automation: AutomationEngine) {
	return {
		name: "scale",
		schema: {
			title: "Scale Agents",
			description: "Launch multiple agents in parallel",
			inputSchema: {
				tasks: z
					.array(z.string())
					.describe(
						"Array of task IDs to launch agents for (e.g., ['4.3', '5.1', '10.2']). Each task gets dedicated agent with isolated worktree. Agents run in parallel without conflicts. NOTE: Currently uses simple prompt 'Work on task X'; Task Master integration coming soon for full task details.",
					),
				role: z
					.enum(["executor", "validator"])
					.describe(
						"Role for all launched agents. 'executor' implements features in parallel. 'validator' checks multiple implementations simultaneously. All agents in batch use same role.",
					),
				worktree: z
					.enum(["auto", "manual"])
					.default("auto")
					.describe(
						"Worktree mode for all agents. 'auto': creates isolated worktrees for parallel work (DEFAULT for executors). 'manual': uses PROJECT_ROOT (only if user explicitly requests). Default: 'auto'.",
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

					const agent_id = `${args.role}-${Date.now()}-${Math.random()
						.toString(36)
						.substring(7)}`;
					const taskSlug = task_id.replace(/[^A-Za-z0-9/_-]/g, "-");
					const baseWorktreeName = `${args.role}-${taskSlug}`;
					const worktreeMode = args.worktree ?? "auto";

					const session = await createAgentSession(
						{
							agentId: agent_id,
							role: args.role,
							prompt,
							taskId: task_id,
							worktreeMode,
							worktreeName: baseWorktreeName,
						},
						{
							db,
							registerAgent: (agent) => automation.registerAgent(agent),
						},
					);

					return {
						agent_id: session.agent_id,
						shell_id: session.shell_id,
						worktree: worktreeMode === "auto" ? session.worktree : undefined,
						branch: session.branch,
						status: "running" as const,
						task_id,
					};
				}),
			);

			// Process results
			results.forEach((result, index) => {
				if (result.status === "fulfilled") {
					launched.push(result.value);
				} else {
					failed.push({
						task_id: args.tasks[index] ?? "unknown",
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
