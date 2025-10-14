/**
 * Status Tool
 */

import { z } from "zod";
import type {
	OrchestratorDB,
	StatusInput,
	StatusOutput,
	ValidationStatus,
} from "@swift-ai-sdk/orchestrator-db";

export function createStatusTool(db: OrchestratorDB) {
	return {
		name: "status",
		schema: {
			title: "Get Agent Status",
			description: `Check status of agents and validation queue.

WHAT IT DOES:
Shows current state of all agents: what they're doing, how long they've been running, if they're stuck, and validation status.

WHEN TO USE:
- Monitor progress of running agents
- Check if agent is stuck (idle_minutes shows how long since last activity)
- See validation queue (which executors waiting for validators)
- Debug issues (check events count, uptime, last_activity)

STATUS VALUES:
- running: Agent actively working
- blocked: Executor waiting for validation to complete
- validating: Validator checking work
- validated: Executor approved, work ready to merge
- needs_fix: Executor rejected, must fix bugs
- completed: Agent finished successfully
- killed: Manually terminated

RESULT FIELDS:
- agent_id: Unique identifier for agent
- task_id: Associated task (if any)
- status: Current agent status
- events: Number of activities logged (low count may indicate problem)
- uptime: How long agent has been running
- last_activity: Timestamp of last action
- idle_minutes: How long since last activity (high value = stuck)
- validation: If in validation workflow, shows validation_id + status

EXAMPLE:
status() → Shows all agents
status(agent_id="executor-123") → Shows specific agent details`,
			inputSchema: {
				agent_id: z
					.string()
					.optional()
					.describe(
						"Agent ID to get status for (e.g., 'executor-1760408478640'). If omitted, returns status of all running and completed agents."
					),
				format: z
					.enum(["summary", "detailed"])
					.default("summary")
					.describe(
						"Output format level. 'summary' shows essential info (agent_id, task_id, status, events count, uptime, last_activity, idle_minutes). 'detailed' adds full statistics including files_created and extended metadata."
					),
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

					// Calculate idle time from last_activity
					const idleMinutes = agent.last_activity
						? Math.floor((Date.now() - new Date(agent.last_activity).getTime()) / 60000)
						: null;

				const validation = agent.current_validation_id
					? (() => {
						const session = db.getValidationSession(agent.current_validation_id!);
						if (!session) {
							return {
								id: agent.current_validation_id!,
								status: "pending" as ValidationStatus,
							};
						}
						return { id: session.id, status: session.status };
					})()
					: undefined;

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
							last_activity: agent.last_activity,
							idle_minutes: idleMinutes,
							validation,
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
					agents: agents.map((agent) => {
						// Calculate idle time from last_activity
						const idleMinutes = agent.last_activity
							? Math.floor((Date.now() - new Date(agent.last_activity).getTime()) / 60000)
							: null;

						const validation = agent.current_validation_id
							? (() => {
								const session = db.getValidationSession(
									agent.current_validation_id!
								);
								if (!session) {
									return {
										id: agent.current_validation_id!,
										status: "pending" as ValidationStatus,
									};
								}
								return { id: session.id, status: session.status };
							})()
							: undefined;

						return {
							agent_id: agent.id,
							task_id: agent.task_id,
							status: agent.status,
							events: agent.events_count,
							files_created: agent.files_created,
							uptime: agent.started_at
								? `${Math.floor((Date.now() - new Date(agent.started_at).getTime()) / 60000)}m`
								: "0m",
							last_activity: agent.last_activity,
							idle_minutes: idleMinutes,
							validation,
						};
					}),
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
