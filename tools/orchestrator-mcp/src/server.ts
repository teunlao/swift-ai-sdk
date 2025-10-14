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
const server = new McpServer(
	{
		name: "orchestrator-mcp",
		version: "0.1.0",
	},
	{
		instructions: `Orchestrator MCP - Multi-agent validation workflow manager.

WHAT IT DOES:
Manages parallel Codex executor/validator agents with formal validation workflow, status tracking, and Git worktree isolation.

VALIDATION WORKFLOW (3 steps):
1. Executor completes work → calls 'request_validation' → blocked, creates validation session (status='pending')
2. YOU call 'assign_validator' with validation_id + validator_id → validator starts (status='in_progress')
3. Validator reviews → calls 'submit_validation' with verdict:
   • approved: executor='validated' (ready to merge)
   • rejected: executor='needs_fix' (must fix bugs and re-request validation)

KEY TOOLS:
- launch_agent(role, worktree, prompt) - Start executor/validator in isolated worktree
- request_validation(executor_id) - Executor requests review after completing work
- assign_validator(validation_id, validator_id) - YOU assign validator to review
- submit_validation(validation_id, result, report_path) - Validator submits verdict
- status() - Check agent statuses and validation queue
- get_logs(agent_id) - View agent activity and reasoning

AGENT STATUSES:
- running: Actively working
- blocked: Executor waiting for validation
- validating: Validator checking work
- validated: Approved, ready to merge
- needs_fix: Rejected, must fix bugs
- completed: Job done
- killed: Manually terminated

TYPICAL FLOW:
1. launch_agent(role="executor", worktree="auto") → creates code with bugs
2. Executor finishes → calls request_validation → returns validation_id
3. launch_agent(role="validator", worktree="manual", cwd=executor_worktree)
4. assign_validator(validation_id, validator_id) → validator starts review
5. Validator finds bugs → submit_validation(result="rejected") → executor status='needs_fix'
6. continue_agent(executor_id, "fix bugs") → executor fixes issues
7. Executor calls request_validation again → new validation cycle
8. Validator approves → submit_validation(result="approved") → executor status='validated'

FEATURES:
- Parallel execution: Multiple agents work simultaneously without conflicts via Git worktrees
- Real-time monitoring: Live log parsing, event tracking, background recovery
- Persistent state: SQLite DB at ~/claude-orchestrator/orchestrator.db
- Automatic isolation: Each agent gets own worktree + branch

USE CASES:
- Code review: Executor implements → Validator checks → Executor fixes → Approved
- Testing: Executor creates buggy code → Validator finds bugs → Executor fixes → Passes
- Porting: Executor ports TypeScript → Validator checks 100% parity → Approved`,
	}
);


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
