#!/usr/bin/env node

/**
 * Orchestrator MCP Server
 *
 * Manages parallel Codex agents with automatic recovery and monitoring.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import { createTools } from "./tools/index.js";
import {
	startBackgroundParser,
	stopAllBackgroundParsers,
} from "./background-parser.js";
import { isCodexAgentRunning, getAgentTmpDir } from "./codex.js";
import * as fs from "node:fs";

// Initialize database
const db = new OrchestratorDB();

// Create MCP server
const server = new McpServer({
	name: "orchestrator-mcp",
	version: "0.1.0",
});

console.error("Starting Orchestrator MCP Server...");

// Register all tools
const tools = createTools(db);

for (const tool of tools) {
	server.registerTool(tool.name, tool.schema, tool.handler);
}

// ============ Start Server ============

async function main() {
	const transport = new StdioServerTransport();

	await server.connect(transport);

	// Restore watchers for running agents
	const runningAgents = db.getAllAgents({ status: "running" });
	let restored = 0;

	for (const agent of runningAgents) {
		const tmpDir = getAgentTmpDir(agent.id);
		const outputFile = `${tmpDir}/output.json`;

		// Check if agent is still alive and file exists
		if (fs.existsSync(outputFile) && isCodexAgentRunning(agent.shell_id)) {
			startBackgroundParser(agent.id, outputFile, db);
			restored++;
		} else {
			// Agent died while server was down
			db.updateAgent(agent.id, { status: "killed" });
		}
	}

	console.error("✅ Orchestrator MCP Server running");
	console.error(`📊 Database: ${db.getAgentCount()} agents tracked`);
	console.error(`🔧 Tools: ${tools.map((t) => t.name).join(", ")}`);
	if (restored > 0) {
		console.error(`🔄 Restored ${restored} background parsers`);
	}
}

main().catch((error) => {
	console.error("❌ Server error:", error);
	process.exit(1);
});

// Cleanup on exit
process.on("SIGINT", () => {
	console.error("\n👋 Shutting down...");
	stopAllBackgroundParsers();
	db.close();
	process.exit(0);
});

process.on("SIGTERM", () => {
	stopAllBackgroundParsers();
	db.close();
	process.exit(0);
});
