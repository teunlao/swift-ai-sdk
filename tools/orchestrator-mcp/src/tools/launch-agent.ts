/**
 * Launch Agent Tool
 */

import type {
	LaunchAgentInput,
	LaunchAgentOutput,
	OrchestratorDB,
} from "@swift-ai-sdk/orchestrator-db";
import { z } from "zod";
import { createAgentSession } from "../automation/agent-factory.js";
import type { AutomationEngine } from "../automation/engine.js";

export function createLaunchAgentTool(
	db: OrchestratorDB,
	automation: AutomationEngine,
) {
	return {
		name: "launch_agent",
		schema: {
			title: "Launch Agent",
			description: `Launch a new Codex executor or validator agent with Git worktree isolation.

⚠️ WORKTREE NAME REQUIRED ⚠️
- Every launch MUST provide the worktree_name argument.
- The orchestrator prefixes 'agent/' automatically (e.g., agent/my-feature).
- Omitting or leaving worktree_name blank will abort the launch.

WHAT IT DOES:
Creates a new autonomous Codex agent that runs in parallel, executes your prompt, and tracks all activity in real-time. Automation injects a system prompt so the agent maintains \`.orchestrator/\` flow files and (for executors) drafts validation requests automatically.

WHEN TO USE:
- Start executor to implement features, write code, fix bugs
- Start validator to check code against requirements, find bugs, verify parity
- Launch multiple agents in parallel for simultaneous work on independent tasks

WORKTREE MODES:
- 'auto': Creates isolated Git worktree + unique branch
  → Each agent gets own directory, no conflicts
- 'manual': Uses existing directory via cwd parameter
  → Validator works in executor's worktree to access files

ROLES:
- executor: Implements features, writes code, creates tests, fixes bugs
- validator: Reviews code, finds bugs, checks requirements, verifies parity

⚠️  DEFAULT BEHAVIOR (unless user explicitly requests otherwise):
- **Executors:** ALWAYS use worktree="auto" → creates NEW isolated worktree
- **Validators:** ALWAYS use worktree="manual" with executor's worktree → works in SAME directory as executor being validated

Automation watches flow JSON and launches validators/continues executors without extra commands. Use manual tools only if you need to override the automated loop.

RESULT: Returns agent_id + shell_id. Use these for status(), get_logs(), continue_agent(), kill_agent().

EXAMPLE:
launch_agent(role="executor", worktree="auto", prompt="Create snake game with 4 bugs")
→ Returns agent_id="executor-1760450655037", creates isolated worktree`,
			inputSchema: {
				role: z
					.enum(["executor", "validator"])
					.describe(
						"Agent role. 'executor' implements features and writes code. 'validator' checks implementation against requirements for 100% parity.",
					),
				task_id: z
					.string()
					.optional()
					.describe(
						"Task ID from Task Master (e.g., '4.3' or '10.2'). Used to associate agent with specific task for tracking and validation.",
					),
				worktree: z
					.enum(["auto", "manual"])
					.describe(
						"Worktree mode. 'auto' creates isolated Git worktree with unique branch for parallel work without conflicts. 'manual' uses cwd parameter for custom directory.",
					),
				worktree_name: z
					.string()
					.min(1, "Worktree name is required")
					.describe(
						"REQUIRED. Human-readable worktree name suffix. The orchestrator automatically prefixes 'agent/' (e.g., 'agent/my-feature'). Only letters, numbers, '/', '-', and '_' are allowed; leaving this empty will cause launch to fail.",
					),
				spawn_new_validator: z
					.boolean()
					.optional()
					.describe(
						"Optional override (executors only). When true, automation will spawn a fresh validator agent for every validation iteration. Default reuses the first validator session.",
					),
				prompt: z
					.string()
					.describe(
						"Initial task instruction for the agent. Should be clear, actionable command (e.g., 'Implement delay utility function from @ai-sdk/provider-utils/src/delay.ts'). Agent will execute this in Codex session.",
					),
				cwd: z
					.string()
					.optional()
					.describe(
						"Working directory path when worktree='manual'. Absolute path where agent will execute commands. If omitted with manual mode, uses PROJECT_ROOT env var or server process cwd.",
					),
				model: z
					.string()
					.optional()
					.describe(
						"Override model for this agent (e.g., 'claude-sonnet-4', 'gpt-4'). If omitted, uses default model from Codex configuration.",
					),
				reasoning_effort: z
					.enum(["low", "medium", "high"])
					.optional()
					.describe(
						"Reasoning depth for agent decisions. 'low' for simple tasks, 'medium' for moderate complexity, 'high' for complex problem-solving requiring deep analysis.",
					),
			},
		},
		handler: async (args: LaunchAgentInput) => {
			try {
				const agent_id = `${args.role}-${Date.now()}`;
				const session = await createAgentSession(
					{
						agentId: agent_id,
						role: args.role,
						prompt: args.prompt,
						taskId: args.task_id ?? null,
						worktreeMode: args.worktree,
						worktreeName: args.worktree_name,
						cwd: args.cwd,
						model: args.model,
						reasoningEffort: args.reasoning_effort,
						spawnNewValidator:
							args.role === "executor"
								? (args.spawn_new_validator ?? false)
								: undefined,
					},
					{
						db,
						registerAgent: (agent) => automation.registerAgent(agent),
					},
				);

				const result: LaunchAgentOutput = {
					agent_id: session.agent_id,
					shell_id: session.shell_id,
					worktree: args.worktree === "auto" ? session.worktree : undefined,
					branch: session.branch,
					status: "running",
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
