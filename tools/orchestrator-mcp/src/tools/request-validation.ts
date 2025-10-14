/**
 * Request Validation Tool
 */

import { z } from "zod";
import { simpleGit } from "simple-git";
import type {
  OrchestratorDB,
  RequestValidationInput,
  RequestValidationOutput,
  ValidationSession,
  ValidationStatus,
} from "@swift-ai-sdk/orchestrator-db";

const validationId = () => `validation-${Date.now()}`;

async function detectBranch(worktree: string | null): Promise<string | null> {
  if (!worktree) {
    return null;
  }

  try {
    const git = simpleGit(worktree);
    const branch = await git.revparse(["--abbrev-ref", "HEAD"]);
    return branch.trim();
  } catch {
    return null;
  }
}

export function createRequestValidationTool(db: OrchestratorDB) {
  return {
    name: "request_validation",
    schema: {
      title: "Request Validation",
      description: "Create a validation session for an executor agent",
      inputSchema: {
        executor_id: z
          .string()
          .describe(
            "Executor agent ID that completed work and needs validation (e.g., 'executor-1760408478640'). Agent must have role='executor' and must have been launched with worktree isolation. This creates a validation session and blocks the executor until validation completes."
          ),
        task_id: z
          .string()
          .optional()
          .describe(
            "Optional Task Master task ID override (e.g., '4.3', '10.2'). If omitted, uses task_id from executor agent record. Used to track which task this validation is for."
          ),
        request_path: z
          .string()
          .optional()
          .describe(
            "Optional path to validation request document (e.g., '.validation/requests/validate-task-4.3-2025-10-14.md'). Used by validator to understand what needs to be checked. If omitted, validator should look for standard validation request in executor's worktree."
          ),
        summary: z
          .string()
          .optional()
          .describe(
            "Optional brief summary of work completed (e.g., 'Implemented delay utility with all tests passing'). Helps validator understand scope without reading full request. Will be included in validation session metadata."
          ),
      },
    },
    handler: async (args: RequestValidationInput) => {
      try {
        const executor = db.getAgent(args.executor_id);
        if (!executor) {
          return {
            content: [
              {
                type: "text" as const,
                text: `Executor not found: ${args.executor_id}`,
              },
            ],
          };
        }

        if (executor.role !== "executor") {
          return {
            content: [
              {
                type: "text" as const,
                text: `Agent ${args.executor_id} is not an executor (role: ${executor.role})`,
              },
            ],
          };
        }

        if (!executor.worktree) {
          return {
            content: [
              {
                type: "text" as const,
                text: `Executor ${args.executor_id} has no recorded worktree; cannot establish validation context. Launch executor with worktree isolation first.`,
              },
            ],
          };
        }

        if (executor.current_validation_id) {
          return {
            content: [
              {
                type: "text" as const,
                text: `Executor ${args.executor_id} already has active validation (${executor.current_validation_id})`,
              },
            ],
          };
        }

        const now = new Date().toISOString();
        const id = validationId();
        const branch = await detectBranch(executor.worktree);

        const session: ValidationSession = {
          id,
          task_id: args.task_id ?? executor.task_id,
          executor_id: executor.id,
          validator_id: null,
          status: "pending" as ValidationStatus,
          executor_worktree: executor.worktree,
          executor_branch: branch,
          request_path: args.request_path ?? null,
          report_path: null,
          summary: args.summary ?? null,
          requested_at: now,
          started_at: null,
          finished_at: null,
        };

        db.createValidationSession(session);
        db.updateAgent(executor.id, { current_validation_id: id });

        const result: RequestValidationOutput = {
          validation_id: id,
          status: "pending",
          executor_id: executor.id,
          executor_worktree: executor.worktree,
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
