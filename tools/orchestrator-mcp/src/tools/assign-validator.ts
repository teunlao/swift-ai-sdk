/**
 * Assign Validator Tool
 */

import type {
	AssignValidatorInput,
	AssignValidatorOutput,
	OrchestratorDB,
	ValidationSession,
} from "@swift-ai-sdk/orchestrator-db";
import { z } from "zod";

export function createAssignValidatorTool(db: OrchestratorDB) {
	return {
		name: "assign_validator",
		schema: {
			title: "Assign Validator",
			description: `Assign a validator agent to a validation session.

Automation handles this step by default: when an executor flow file switches to status="ready_for_validation" the orchestrator automatically spins up a validator in the same worktree and attaches it to the new session. Use this tool only for manual recovery (e.g., you launched your own validator or automation was disabled).

MANUAL WORKFLOW (fallback):
1. Executor creates validation request (automation does this when using the standard prompt).
2. Call request_validation(executor_id) to open a pending session.
3. Call assign_validator(validation_id, validator_id) — this tool — to set status='in_progress'.
4. When validator finishes and writes the report, call submit_validation.

Validator must run inside the executor worktree. Agents still cannot call MCP tools; only the human operator can trigger this override.`,
			inputSchema: {
				validation_id: z
					.string()
					.describe(
						"Validation session ID from request_validation (e.g., 'validation-1739472000'). Session must be in 'pending' status. Once assigned, session transitions to 'in_progress' and validator is blocked from other validations.",
					),
				validator_id: z
					.string()
					.describe(
						"Validator agent ID to assign (e.g., 'validator-1760408550123'). Agent must have role='validator' and must be launched in executor's worktree directory (matching executor_worktree from session). Validator cannot be assigned to multiple validations simultaneously.",
					),
			},
		},
		handler: async (args: AssignValidatorInput) => {
			try {
				const session = db.getValidationSession(args.validation_id);
				if (!session) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Validation session not found: ${args.validation_id}`,
							},
						],
					};
				}

				if (session.status !== "pending") {
					return {
						content: [
							{
								type: "text" as const,
								text: `Validation ${args.validation_id} is not pending (current status: ${session.status})`,
							},
						],
					};
				}

				const executor = db.getAgent(session.executor_id);
				if (!executor) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Executor agent ${session.executor_id} not found`,
							},
						],
					};
				}

				const validator = db.getAgent(args.validator_id);
				if (!validator) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Validator not found: ${args.validator_id}`,
							},
						],
					};
				}

				if (validator.role !== "validator") {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent ${args.validator_id} is not a validator (role: ${validator.role})`,
							},
						],
					};
				}

				if (validator.current_validation_id) {
					// Allow re-assignment if the validator's referenced session is already
					// finished (approved/rejected). This keeps the UI showing the last
					// result until a new assignment, and we overwrite it now.
					const existing = db.getValidationSession(
						validator.current_validation_id,
					);
					const isActive =
						existing &&
						(existing.status === "pending" ||
							existing.status === "in_progress");
					if (isActive) {
						return {
							content: [
								{
									type: "text" as const,
									text: `Validator ${args.validator_id} already assigned to validation ${validator.current_validation_id}`,
								},
							],
						};
					}
					// else finished — proceed and overwrite below
				}

				// Enforce worktree matching
				if (session.executor_worktree && validator.worktree) {
					if (session.executor_worktree !== validator.worktree) {
						return {
							content: [
								{
									type: "text" as const,
									text: `Validator worktree ${validator.worktree} does not match executor worktree ${session.executor_worktree}`,
								},
							],
						};
					}
				} else if (session.executor_worktree && !validator.worktree) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Validator ${args.validator_id} has no worktree; expected ${session.executor_worktree}`,
							},
						],
					};
				}

				const now = new Date().toISOString();
				const updatedSession: Partial<ValidationSession> = {
					validator_id: validator.id,
					status: "in_progress",
					started_at: now,
				};

				db.updateValidationSession(session.id, updatedSession);
				// Overwrite current_validation_id with this session to reflect active work
				db.updateAgent(validator.id, { current_validation_id: session.id });

				const result: AssignValidatorOutput = {
					validation_id: session.id,
					validator_id: validator.id,
					status: "in_progress",
					worktree: session.executor_worktree ?? null,
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
