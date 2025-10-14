/**
 * Get Logs Tool
 *
 * Reads parsed logs from database (populated by background parser).
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  GetLogsInput,
  GetLogsOutput,
  LogEntry,
} from "@swift-ai-sdk/orchestrator-db";

export function createGetLogsTool(db: OrchestratorDB) {
	return {
		name: "get_logs",
		schema: {
			title: "Get Agent Logs",
			description: `View real-time activity logs from agent.

WHAT IT DOES:
Shows agent's thinking, commands executed, errors, and messages. Logs parsed in real-time from Codex output.

WHEN TO USE:
- Monitor agent progress
- Debug stuck agent
- See what agent is currently doing
- Check errors or failures
- Verify agent completed task

FILTER OPTIONS:
- 'reasoning': Thinking blocks only
- 'messages': User/assistant messages
- 'commands': Bash/tool executions
- 'errors': Error events
- 'all': Everything (default)

LAST PARAMETER: Limit to N most recent entries (e.g., last=10 for last 10 events)

EXAMPLE:
get_logs(agent_id="executor-123", filter="messages", last=20)`,
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID to retrieve logs from (e.g., 'executor-1760408478640'). Logs are parsed in real-time by background parser from Codex output.json."
					),
				filter: z
					.enum(["reasoning", "messages", "commands", "errors", "all"])
					.default("all")
					.describe(
						"Log event type filter. 'reasoning': thinking blocks. 'messages': user/assistant messages. 'commands': bash/tool executions. 'errors': error events. 'all': everything. Default: 'all'."
					),
				last: z
					.number()
					.optional()
					.describe(
						"Limit to N most recent log entries. Useful for checking latest activity without loading full history. Example: last=10 shows last 10 events. If omitted, returns all logs matching filter."
					),
			},
		},
		handler: async (args: GetLogsInput) => {
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

				// Read from database (already parsed by background watcher!)
				const dbLogs = db.getLogs(args.agent_id, args.filter, args.last);

				// Convert AgentLog[] to LogEntry[]
				const logs: LogEntry[] = dbLogs.map((log) => ({
					type: log.event_type as LogEntry["type"],
					timestamp: log.timestamp,
					content: log.content,
				}));

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
		},
	};
}
