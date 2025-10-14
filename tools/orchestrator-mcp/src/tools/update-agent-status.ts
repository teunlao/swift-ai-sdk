/**
 * Update Agent Status Tool
 */

import { z } from "zod";
import type {
	OrchestratorDB,
	AgentStatus,
} from "@swift-ai-sdk/orchestrator-db";

export function createUpdateAgentStatusTool(db: OrchestratorDB) {
	return {
		name: "update_agent_status",
		schema: {
			title: "Update Agent Status",
			description: `Manually change an agent's status.

WHAT IT DOES:
Directly updates agent status in database without workflow constraints.

WHEN TO USE:
- **Validator reuse**: Change validator from 'completed' to 'running' for re-validation
- **Error recovery**: Reset stuck agents to correct state
- **Debug/admin**: Manual state corrections
- **Force resume**: Change 'blocked' to 'running'

⚠️  DANGER: This bypasses normal workflow logic! Use carefully.

COMMON SCENARIOS:

1. Reuse validator after rejection:
   - After submit_validation(rejected), OLD CODE set validator='completed'
   - Use: update_agent_status(validator_id, "running")
   - Then: continue_agent(validator_id, "re-validate fixes")

2. Unstuck executor:
   - Executor stuck in 'blocked'
   - Use: update_agent_status(executor_id, "running")

3. Reset for testing:
   - Agent in 'validated' but need to re-run
   - Use: update_agent_status(agent_id, "running")

VALID STATUSES:
- running, blocked, needs_fix, validated, completed, killed

RESULT: Returns new agent status.`,
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID to update (e.g., 'executor-1760408478640' or 'validator-1760408550123'). Must exist in database."
					),
				status: z
					.enum([
						"running",
						"blocked",
						"needs_fix",
						"validated",
						"completed",
						"killed",
					])
					.describe(
						"New status to set. 'running': active work. 'blocked': waiting for validation. 'needs_fix': rejected, must fix bugs. 'validated': approved, ready to merge. 'completed': job done. 'killed': manually terminated."
					),
				clear_validation: z
					.boolean()
					.optional()
					.describe(
						"Whether to clear current_validation_id (default: false). Set to true if changing from validation-related status."
					),
			},
		},
		handler: async (args: {
			agent_id: string;
			status: AgentStatus;
			clear_validation?: boolean;
		}) => {
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

				const now = new Date().toISOString();
				const updates: Record<string, unknown> = {
					status: args.status,
					last_activity: now,
				};

				if (args.clear_validation) {
					updates.current_validation_id = null;
				}

				// Set ended_at if transitioning to terminal state
				if (
					args.status === "completed" ||
					args.status === "killed" ||
					args.status === "validated"
				) {
					updates.ended_at = agent.ended_at ?? now;
				}

				db.updateAgent(args.agent_id, updates as Partial<typeof agent>);

				const result = {
					agent_id: args.agent_id,
					old_status: agent.status,
					new_status: args.status,
					role: agent.role,
					message: `Agent ${args.agent_id} status changed: ${agent.status} → ${args.status}`,
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
