/**
 * Status Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import type { StatusInput, StatusOutput } from "../types.js";

export function createStatusTool(db: OrchestratorDB) {
	return {
		name: "status",
		schema: {
			title: "Get Agent Status",
			description: "Get status of one or all agents",
			inputSchema: {
				agent_id: z.string().optional(),
				format: z.enum(["summary", "detailed"]).default("summary"),
			},
		},
		handler: async (args: StatusInput) => {
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
	};
}
