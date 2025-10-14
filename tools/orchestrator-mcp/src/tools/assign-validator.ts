/**
 * Assign Validator Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  AssignValidatorInput,
  AssignValidatorOutput,
  ValidationSession,
} from "@swift-ai-sdk/orchestrator-db";

export function createAssignValidatorTool(db: OrchestratorDB) {
  return {
    name: "assign_validator",
    schema: {
      title: "Assign Validator",
      description:
        "Assign a validator agent to a validation session. Links validator to executor's worktree for verification. CRITICAL: Validator must be launched in the SAME worktree as executor to access implementation files. Updates session status from 'pending' to 'in_progress'.",
      inputSchema: {
        validation_id: z
          .string()
          .describe(
            "Validation session ID from request_validation (e.g., 'validation-1739472000'). Session must be in 'pending' status. Once assigned, session transitions to 'in_progress' and validator is blocked from other validations."
          ),
        validator_id: z
          .string()
          .describe(
            "Validator agent ID to assign (e.g., 'validator-1760408550123'). Agent must have role='validator' and must be launched in executor's worktree directory (matching executor_worktree from session). Validator cannot be assigned to multiple validations simultaneously."
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
          return {
            content: [
              {
                type: "text" as const,
                text: `Validator ${args.validator_id} already assigned to validation ${validator.current_validation_id}`,
              },
            ],
          };
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
