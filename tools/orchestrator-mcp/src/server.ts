#!/usr/bin/env node

/**
 * Orchestrator MCP Server
 *
 * Manages parallel Codex agents with automatic recovery and monitoring.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { OrchestratorDB } from "./database.js";
import { createTools } from "./tools/index.js";

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

	console.error("✅ Orchestrator MCP Server running");
	console.error(`📊 Database: ${db.getAgentCount()} agents tracked`);
	console.error(`🔧 Tools: ${tools.map((t) => t.name).join(", ")}`);
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
