/**
 * Submit Validation Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  SubmitValidationInput,
  SubmitValidationOutput,
  AgentStatus,
} from "@swift-ai-sdk/orchestrator-db";

export function createSubmitValidationTool(db: OrchestratorDB) {
  return {
    name: "submit_validation",
    schema: {
      title: "Submit Validation Result",
      description: `Finalize a validation session with verdict. STEP 5 (FINAL) of validation workflow.

WORKFLOW CONTEXT (YOU orchestrate all steps):
Step 1: Executor agent creates .validation/requests/*.md and stops
Step 2: YOU called 'request_validation(executor_id)' → session created (status='pending')
Step 3: YOU called 'assign_validator(validation_id, validator_id)' → validator started work (status='in_progress')
Step 4: Validator agent creates .validation/reports/*.md and stops
Step 5 (THIS TOOL): YOU call 'submit_validation(validation_id, result)' → workflow completes, updates statuses

WHEN TO USE: After validator agent completes verification and creates validation report.

RESULT (result='approved'):
- Validation session → status='approved'
- Executor → status='validated' (work approved, ready to merge)
- Validator → status='completed' (job done)

RESULT (result='rejected'):
- Validation session → status='rejected'
- Executor → status='needs_fix' (must fix issues and request re-validation)
- Validator → status='completed'

NEXT STEPS after rejection: YOU notify user, executor fixes issues, YOU call 'request_validation' again → new validation cycle starts.

CRITICAL: Agents cannot call MCP tools - only YOU can. This is a destructive operation (changes agent statuses permanently).`,
      inputSchema: {
        validation_id: z
          .string()
          .describe(
            "Validation session ID to finalize (e.g., 'validation-1739472000'). Session must be in 'in_progress' or 'pending' status. After submit, session status becomes 'approved' or 'rejected' (final states)."
          ),
        result: z
          .enum(["approved", "rejected"])
          .describe(
            "Validation verdict. 'approved': Implementation meets 100% upstream parity, executor status becomes 'validated', work can be merged. 'rejected': Issues found, executor status becomes 'needs_fix', executor must address problems and request re-validation."
          ),
        report_path: z
          .string()
          .describe(
            "Path to detailed validation report document (e.g., '.validation/reports/report-task-4.3-2025-10-14.md'). Report should contain line-by-line comparison results, test coverage verification, parity assessment. Required for both approved and rejected verdicts."
          ),
        summary: z
          .string()
          .optional()
          .describe(
            "Optional brief summary of validation findings (e.g., 'All tests pass, API matches upstream, approved for merge' or 'Missing 3 test cases, incorrect error handling in line 45'). If omitted, uses summary from validation request."
          ),
      },
    },
    handler: async (args: SubmitValidationInput) => {
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

        if (session.status !== "in_progress" && session.status !== "pending") {
          // Allow finishing even if validator exited unexpectedly but no verdict recorded
          if (session.status === "approved" || session.status === "rejected") {
            return {
              content: [
                {
                  type: "text" as const,
                  text: `Validation ${args.validation_id} already completed (status: ${session.status})`,
                },
              ],
            };
          }
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

        const validatorId = session.validator_id;
        const validator = validatorId ? db.getAgent(validatorId) : undefined;

        const now = new Date().toISOString();
        const validationStatus = args.result === "approved" ? "approved" : "rejected";

        db.updateValidationSession(session.id, {
          status: validationStatus,
          report_path: args.report_path,
          summary: args.summary ?? session.summary,
          finished_at: now,
        });

			const isApproved = args.result === "approved";
			const executorStatus: AgentStatus = isApproved ? "validated" : "needs_fix";

			const executorUpdates: Record<string, unknown> = {
				status: executorStatus,
				current_validation_id: null,
				last_activity: now,
			};
			if (isApproved) {
				executorUpdates.ended_at = executor.ended_at ?? now;
			}
			db.updateAgent(executor.id, executorUpdates as Partial<typeof executor>);

        let validatorStatus: AgentStatus = validator?.status ?? "running";
			if (validator) {
				validatorStatus = "completed";
				db.updateAgent(validator.id, {
					status: validatorStatus,
					current_validation_id: null,
					last_activity: now,
					ended_at: validator.ended_at ?? now,
				});
        }

        const output: SubmitValidationOutput = {
          validation_id: session.id,
          status: validationStatus,
          executor_status: executorStatus,
          validator_status: validatorStatus,
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
