/**
 * Get History Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import type {
	GetHistoryInput,
	GetHistoryOutput,
	HistoryEntry,
} from "../types.js";

export function createGetHistoryTool(db: OrchestratorDB) {
	return {
		name: "get_history",
		schema: {
			title: "Get Agent History",
			description: "Get historical agent sessions",
			inputSchema: {
				from_date: z.string().optional(),
				to_date: z.string().optional(),
				task_id: z.string().optional(),
				role: z.enum(["executor", "validator"]).optional(),
			},
		},
		handler: async (args: GetHistoryInput) => {
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
		},
	};
}
