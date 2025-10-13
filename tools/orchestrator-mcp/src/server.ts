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
import type {
	AutoRecoverInput,
	AutoRecoverOutput,
	KillAgentInput,
	KillAgentOutput,
	LaunchAgentInput,
	LaunchAgentOutput,
	StatusInput,
	StatusOutput,
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
			// TODO: Implement actual launch logic
			// For now, return a placeholder response

			const agent_id = `${args.role}-${Date.now()}`;
			const shell_id = "placeholder-shell-id";

			const result: LaunchAgentOutput = {
				agent_id,
				shell_id,
				status: "running",
			};

			// Store in database
			db.createAgent({
				id: agent_id,
				role: args.role,
				task_id: args.task_id || null,
				shell_id: shell_id,
				worktree: args.cwd || null,
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

			// TODO: Implement actual kill logic (KillShell, worktree cleanup)

			db.updateAgent(args.agent_id, {
				status: "killed",
				ended_at: new Date().toISOString(),
			});

			const result: KillAgentOutput = {
				agent_id: args.agent_id,
				status: "killed",
				worktree_removed: args.cleanup_worktree || false,
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

// ============ Start Server ============

async function main() {
	const transport = new StdioServerTransport();

	await server.connect(transport);

	console.error("✅ Orchestrator MCP Server running");
	console.error(`📊 Database: ${db.getAgentCount()} agents tracked`);
	console.error(`🔧 Tools: launch_agent, status, kill_agent, auto_recover`);
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
