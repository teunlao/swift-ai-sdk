/**
 * Launch Agent Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  LaunchAgentInput,
  LaunchAgentOutput,
} from "@swift-ai-sdk/orchestrator-db";
import { createWorktree } from "../git.js";
import { launchCodexAgent } from "../codex.js";
import { startBackgroundParser } from "../background-parser.js";

export function createLaunchAgentTool(db: OrchestratorDB) {
	return {
		name: "launch_agent",
		schema: {
			title: "Launch Agent",
			description: "Launch a new Codex agent in a worktree",
			inputSchema: {
				role: z
					.enum(["executor", "validator"])
					.describe(
						"Agent role. 'executor' implements features and writes code. 'validator' checks implementation against requirements for 100% parity."
					),
				task_id: z
					.string()
					.optional()
					.describe(
						"Task ID from Task Master (e.g., '4.3' or '10.2'). Used to associate agent with specific task for tracking and validation."
					),
				worktree: z
					.enum(["auto", "manual"])
					.describe(
						"Worktree mode. 'auto' creates isolated Git worktree with unique branch for parallel work without conflicts. 'manual' uses cwd parameter for custom directory."
					),
				prompt: z
					.string()
					.describe(
						"Initial task instruction for the agent. Should be clear, actionable command (e.g., 'Implement delay utility function from @ai-sdk/provider-utils/src/delay.ts'). Agent will execute this in Codex session."
					),
				cwd: z
					.string()
					.optional()
					.describe(
						"Working directory path when worktree='manual'. Absolute path where agent will execute commands. If omitted with manual mode, uses PROJECT_ROOT env var or server process cwd."
					),
				model: z
					.string()
					.optional()
					.describe(
						"Override model for this agent (e.g., 'claude-sonnet-4', 'gpt-4'). If omitted, uses default model from Codex configuration."
					),
				reasoning_effort: z
					.enum(["low", "medium", "high"])
					.optional()
					.describe(
						"Reasoning depth for agent decisions. 'low' for simple tasks, 'medium' for moderate complexity, 'high' for complex problem-solving requiring deep analysis."
					),
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
					args.role,
					args.model,
					args.reasoning_effort
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
				current_validation_id: null,
			});

				// Start background parser for real-time log parsing
				startBackgroundParser(agent_id, codexResult.outputFile, db);

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
