#!/usr/bin/env node

/**
 * Orchestrator MCP Server
 *
 * Manages parallel Codex agents with automatic recovery and monitoring.
 */

import * as fs from "node:fs";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import { AutomationEngine } from "./automation/engine.js";
import {
	startBackgroundParser,
	stopAllBackgroundParsers,
} from "./background-parser.js";
import { getAgentTmpDir, isCodexAgentRunning } from "./codex.js";
import { StuckMonitor } from "./monitoring/stuck-monitor.js";
import { createTools } from "./tools/index.js";

// Initialize database
const db = new OrchestratorDB();
const automation = new AutomationEngine(db);
const stuckMonitor = new StuckMonitor(db);

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

‼️ VALIDATION MANDATE ‼️
- YOU MUST execute the complete validation workflow for 100% of tasks. No exceptions, no shortcuts.
- The ONLY allowed skip is when the user explicitly writes exactly "skip validation" or "no validation needed". Any other phrasing still requires full validation.

## COMPLETE VALIDATION CYCLE (iterative until approved):

┌─────────────────────────────────────────────────────────────────┐
│  VALIDATION LOOP - Repeats until validator approves             │
└─────────────────────────────────────────────────────────────────┘

1. launch_agent(role="executor", worktree="auto")
   → Executor creates implementation

2. Executor finishes → calls request_validation(executor_id)
   → YOU call this MCP tool, returns validation_id
   → Executor status: 'blocked' (waiting for review)

3. launch_agent(role="validator", worktree="manual", cwd=executor_worktree)
   → Validator works in SAME directory as executor

4. YOU call assign_validator(validation_id, validator_id)
   → Links validator to validation session
   → Session status: 'in_progress'

5. Validator reviews code → creates report

6. YOU call submit_validation(validation_id, result, report_path)

   IF result="rejected":
   ├─ Executor status: 'needs_fix'
   ├─ Validator status: 'completed'
   ├─ Session status: 'rejected'
   └─ → GO TO STEP 7 (fix bugs)

   IF result="approved":
   ├─ Executor status: 'validated' (ready to merge)
   ├─ Validator status: 'completed'
   ├─ Session status: 'approved'
   └─ → DONE! Exit loop

7. YOU call continue_agent(executor_id, "Fix bugs from report")
   → Executor fixes issues
   → GO BACK TO STEP 2 (request new validation)

⚠️  LOOP CAN REPEAT 2, 5, 10 times - until validator approves!

## MCP TOOLS YOU ORCHESTRATE:

- launch_agent(role, worktree, prompt) - Start executor/validator
- request_validation(executor_id) - Create validation session
- assign_validator(validation_id, validator_id) - Link validator to session
- submit_validation(validation_id, result, report_path) - Finalize with verdict
- continue_agent(agent_id, prompt) - Send follow-up instruction to agent
- status() - Check agent statuses and validation queue
- get_logs(agent_id) - View agent activity

## AGENT STATUSES:

- running: Actively working
- blocked: Executor waiting for validation
- needs_fix: Rejected by validator, must fix bugs
- validated: Approved by validator, ready to merge
- completed: Validator finished review
- killed: Manually terminated

## FEATURES:

- Iterative validation: Executor fixes → re-validates until approved
- Parallel execution: Multiple executor/validator pairs via Git worktrees
- Real-time monitoring: Live log parsing, event tracking
- Persistent state: SQLite DB at ~/claude-orchestrator/orchestrator.db

## EXAMPLE (2 validation cycles):

Cycle 1: Executor implements → Validator finds 4 bugs → REJECTED
Cycle 2: Executor fixes 4 bugs → Validator verifies → APPROVED → merge!`,
	},
);

console.error("Starting Orchestrator MCP Server...");

// Register all tools
const tools = createTools(db, automation);

for (const tool of tools) {
	server.registerTool(tool.name, tool.schema, tool.handler);
}

// ============ Start Server ============

async function main() {
	const transport = new StdioServerTransport();

	await server.connect(transport);

	// Restore watchers for running agents
	const allAgents = db.getAllAgents();
	automation.start(
		allAgents
			.filter((agent) => Boolean(agent.worktree))
			.map((agent) => ({
				agentId: agent.id,
				worktreePath: agent.worktree!,
				role: agent.role,
				taskId: agent.task_id,
				reuseValidator: agent.role === "executor",
			})),
	);
	const runningAgents = allAgents.filter((agent) => agent.status === "running");
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

	stuckMonitor.start();
}

main().catch((error) => {
	console.error("❌ Server error:", error);
	process.exit(1);
});

// Cleanup on exit
process.on("SIGINT", () => {
	console.error("\n👋 Shutting down...");
	stopAllBackgroundParsers();
	automation.stop();
	stuckMonitor.stop();
	db.close();
	process.exit(0);
});

process.on("SIGTERM", () => {
	stopAllBackgroundParsers();
	stuckMonitor.stop();
	db.close();
	process.exit(0);
});
