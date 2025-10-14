/**
 * Tools Index
 *
 * Exports all MCP tools for the Orchestrator server.
 */

import type { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import { createLaunchAgentTool } from "./launch-agent.js";
import { createStatusTool } from "./status.js";
import { createKillAgentTool } from "./kill-agent.js";
import { createContinueAgentTool } from "./continue-agent.js";
import { createListWorktreeFilesTool } from "./list-worktree-files.js";
import { createReadWorktreeFileTool } from "./read-worktree-file.js";
import { createAutoRecoverTool } from "./auto-recover.js";
import { createGetLogsTool } from "./get-logs.js";
import { createScaleTool } from "./scale.js";
import { createGetHistoryTool } from "./get-history.js";
import { createRequestValidationTool } from "./request-validation.js";
import { createAssignValidatorTool } from "./assign-validator.js";
import { createSubmitValidationTool } from "./submit-validation.js";
import { createGetValidationTool } from "./get-validation.js";

/**
 * Tool definition interface
 */
export interface ToolDefinition {
	name: string;
	schema: any;
	handler: (args: any) => Promise<any>;
}

/**
 * Create all tools for the Orchestrator MCP server
 */
export function createTools(db: OrchestratorDB): ToolDefinition[] {
	return [
		createLaunchAgentTool(db),
		createStatusTool(db),
		createKillAgentTool(db),
		createContinueAgentTool(db),
		createListWorktreeFilesTool(db),
		createReadWorktreeFileTool(db),
		createAutoRecoverTool(db),
		createGetLogsTool(db),
		createScaleTool(db),
		createGetHistoryTool(db),
		createRequestValidationTool(db),
		createAssignValidatorTool(db),
		createSubmitValidationTool(db),
		createGetValidationTool(db),
	];
}
