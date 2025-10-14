/**
 * Get Validation Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  GetValidationInput,
  ValidationSummaryOutput,
} from "@swift-ai-sdk/orchestrator-db";

export function createGetValidationTool(db: OrchestratorDB) {
  return {
    name: "get_validation",
    schema: {
      title: "Get Validation Session",
      description:
        "Retrieve detailed information about a validation session. Shows current status, executor/validator IDs, worktree paths, request/report locations, and timestamps. Use this to monitor validation progress or check validation results after completion.",
      inputSchema: {
        validation_id: z
          .string()
          .describe(
            "Validation session ID to inspect (e.g., 'validation-1739472000'). Returns full session metadata including status (pending/in_progress/approved/rejected), executor_id, validator_id, executor_worktree, executor_branch, request_path, report_path, and timestamps (requested_at, started_at, finished_at)."
          ),
      },
    },
    handler: async (args: GetValidationInput) => {
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

        const output: ValidationSummaryOutput = {
          session,
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
