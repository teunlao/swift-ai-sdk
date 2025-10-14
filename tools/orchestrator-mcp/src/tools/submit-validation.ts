/**
 * Submit Validation Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import type {
  SubmitValidationInput,
  SubmitValidationOutput,
  AgentStatus,
} from "../types.js";

export function createSubmitValidationTool(db: OrchestratorDB) {
  return {
    name: "submit_validation",
    schema: {
      title: "Submit Validation Result",
      description: "Finalize a validation session with a verdict",
      inputSchema: {
        validation_id: z.string(),
        result: z.enum(["approved", "rejected"]),
        report_path: z.string(),
        summary: z.string().optional(),
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

        const executorStatus: AgentStatus =
          args.result === "approved" ? "validated" : "needs_fix";

        const executorUpdates = {
          status: executorStatus,
          current_validation_id: null,
          last_activity: now,
          ended_at: executor.ended_at ?? now,
        };
        db.updateAgent(executor.id, executorUpdates);

        let validatorStatus: AgentStatus = validator?.status ?? "running";
        if (validator) {
          validatorStatus = args.result === "approved" ? "completed" : "completed";
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
