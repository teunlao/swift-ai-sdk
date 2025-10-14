/**
 * Get Logs Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import { readCodexOutput, getAgentTmpDir } from "../codex.js";
import { extractLogs } from "../parser.js";
import type { GetLogsInput, GetLogsOutput } from "../types.js";

export function createGetLogsTool(db: OrchestratorDB) {
	return {
		name: "get_logs",
		schema: {
			title: "Get Agent Logs",
			description: "Get parsed logs from a Codex agent",
			inputSchema: {
				agent_id: z.string(),
				filter: z
					.enum(["reasoning", "messages", "commands", "errors", "all"])
					.default("all"),
				last: z.number().optional(),
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
		},
	};
}
