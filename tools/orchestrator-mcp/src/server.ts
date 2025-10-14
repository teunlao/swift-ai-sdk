#!/usr/bin/env node

/**
 * Orchestrator MCP Server
 *
 * Manages parallel Codex agents with automatic recovery and monitoring.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { OrchestratorDB } from "./database.js";
import {
	createWorktree,
	removeWorktree,
	getWorktreePath,
} from "./git.js";
import {
	launchCodexAgent,
	killCodexAgent,
	readCodexOutput,
	cleanupAgentFiles,
	getAgentTmpDir,
} from "./codex.js";
import { extractLogs } from "./parser.js";
import type {
	AutoRecoverInput,
	AutoRecoverOutput,
	KillAgentInput,
	KillAgentOutput,
	LaunchAgentInput,
	LaunchAgentOutput,
	StatusInput,
	StatusOutput,
	GetLogsInput,
	GetLogsOutput,
	ScaleInput,
	ScaleOutput,
	GetHistoryInput,
	GetHistoryOutput,
	HistoryEntry,
} from "./types.js";

// Initialize database
const db = new OrchestratorDB();

// Create MCP server
const server = new McpServer({
	name: "orchestrator-mcp",
	version: "0.1.0",
});

console.error("Starting Orchestrator MCP Server...");

// ============ Tool: launch_agent ============

server.registerTool(
	"launch_agent",
	{
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
	async (args: LaunchAgentInput) => {
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
);

// ============ Tool: status ============

server.registerTool(
	"status",
	{
		title: "Get Agent Status",
		description: "Get status of one or all agents",
		inputSchema: {
			agent_id: z.string().optional(),
			format: z.enum(["summary", "detailed"]).default("summary"),
		},
	},
	async (args: StatusInput) => {
		try {
			if (args.agent_id) {
				// Get specific agent
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

				// TODO: Add more detailed info from parsing output files
				const result: StatusOutput = {
					agents: [
						{
							agent_id: agent.id,
							task_id: agent.task_id,
							status: agent.status,
							events: agent.events_count,
							files_created: agent.files_created,
							uptime: agent.started_at
								? `${Math.floor((Date.now() - new Date(agent.started_at).getTime()) / 60000)}m`
								: "0m",
						},
					],
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
			} else {
				// Get all agents
				const agents = db.getAllAgents();

				const result: StatusOutput = {
					agents: agents.map((agent) => ({
						agent_id: agent.id,
						task_id: agent.task_id,
						status: agent.status,
						events: agent.events_count,
						files_created: agent.files_created,
						uptime: agent.started_at
							? `${Math.floor((Date.now() - new Date(agent.started_at).getTime()) / 60000)}m`
							: "0m",
					})),
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
			}
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
);

// ============ Tool: kill_agent ============

server.registerTool(
	"kill_agent",
	{
		title: "Kill Agent",
		description: "Stop a running agent",
		inputSchema: {
			agent_id: z.string(),
			cleanup_worktree: z.boolean().optional().default(false),
		},
	},
	async (args: KillAgentInput) => {
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
			const killed = killCodexAgent(agent.shell_id);

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
);

// ============ Tool: auto_recover ============

server.registerTool(
	"auto_recover",
	{
		title: "Auto Recovery",
		description: "Configure automatic agent recovery",
		inputSchema: {
			enable: z.boolean(),
			stuck_threshold_minutes: z.number().optional().default(10),
			max_retries: z.number().optional().default(2),
		},
	},
	async (args: AutoRecoverInput) => {
		try {
			// Save config
			db.setConfig("auto_recover_enabled", String(args.enable));
			db.setConfig(
				"stuck_threshold_minutes",
				String(args.stuck_threshold_minutes || 10),
			);
			db.setConfig("max_retries", String(args.max_retries || 2));

			const result: AutoRecoverOutput = {
				enabled: args.enable,
				config: {
					stuck_threshold_minutes: args.stuck_threshold_minutes || 10,
					max_retries: args.max_retries || 2,
				},
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
);

// ============ Tool: get_logs ============

server.registerTool(
	"get_logs",
	{
		title: "Get Agent Logs",
		description: "Get parsed logs from a Codex agent",
		inputSchema: {
			agent_id: z.string(),
			filter: z
				.enum(["reasoning", "commands", "errors", "stuck", "all"])
				.default("all"),
			last: z.number().optional(),
		},
	},
	async (args: GetLogsInput) => {
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

			// Read Codex output file
			const tmpDir = getAgentTmpDir(args.agent_id);
			const outputFile = `${tmpDir}/output.json`;
			const output = readCodexOutput(outputFile);

			if (!output) {
				return {
					content: [
						{
							type: "text" as const,
							text: `No output available for agent ${args.agent_id}`,
						},
					],
				};
			}

			// Parse and extract logs
			const logs = extractLogs(output, args.filter, args.last);

			const result: GetLogsOutput = {
				agent_id: args.agent_id,
				logs,
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
	}
);

// ============ Tool: scale ============

server.registerTool(
	"scale",
	{
		title: "Scale Agents",
		description: "Launch multiple agents in parallel",
		inputSchema: {
			tasks: z.array(z.string()),
			role: z.enum(["executor", "validator"]),
			worktree: z.enum(["auto", "manual"]).default("auto"),
		},
	},
	async (args: ScaleInput) => {
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
					error: result.reason instanceof Error ? result.reason.message : String(result.reason),
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
	}
);

// ============ Tool: get_history ============

server.registerTool(
	"get_history",
	{
		title: "Get Agent History",
		description: "Get historical agent sessions",
		inputSchema: {
			from_date: z.string().optional(),
			to_date: z.string().optional(),
			task_id: z.string().optional(),
			role: z.enum(["executor", "validator"]).optional(),
		},
	},
	async (args: GetHistoryInput) => {
		try {
			const agents = db.getAgentHistory({
				from_date: args.from_date,
				to_date: args.to_date,
				task_id: args.task_id,
				role: args.role,
			});

			// Map to HistoryEntry format
			const sessions: HistoryEntry[] = agents.map((agent) => {
				// Calculate duration
				let duration = "0m";
				if (agent.started_at && agent.ended_at) {
					const start = new Date(agent.started_at).getTime();
					const end = new Date(agent.ended_at).getTime();
					const minutes = Math.floor((end - start) / 60000);
					if (minutes < 60) {
						duration = `${minutes}m`;
					} else {
						const hours = Math.floor(minutes / 60);
						const mins = minutes % 60;
						duration = `${hours}h${mins}m`;
					}
				}

				// Determine result based on status
				let result: "success" | "validation_failed" | "killed" = "success";
				if (agent.status === "killed") {
					result = "killed";
				} else if (agent.status === "completed") {
					result = "success";
				} else {
					result = "validation_failed";
				}

				return {
					agent_id: agent.id,
					task_id: agent.task_id,
					started: agent.started_at || agent.created_at,
					ended: agent.ended_at,
					duration,
					status: agent.status,
					events: agent.events_count,
					result,
				};
			});

			const output: GetHistoryOutput = {
				sessions,
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
	}
);

// ============ Start Server ============

async function main() {
	const transport = new StdioServerTransport();

	await server.connect(transport);

	console.error("✅ Orchestrator MCP Server running");
	console.error(`📊 Database: ${db.getAgentCount()} agents tracked`);
	console.error(
		`🔧 Tools: launch_agent, status, kill_agent, auto_recover, get_logs, scale, get_history`
	);
}

main().catch((error) => {
	console.error("❌ Server error:", error);
	process.exit(1);
});

// Cleanup on exit
process.on("SIGINT", () => {
	console.error("\n👋 Shutting down...");
	db.close();
	process.exit(0);
});

process.on("SIGTERM", () => {
	db.close();
	process.exit(0);
});
