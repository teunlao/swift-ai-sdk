/**
 * Get Validation Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import type {
	GetValidationInput,
	ValidationSummaryOutput,
} from "../types.js";

export function createGetValidationTool(db: OrchestratorDB) {
  return {
    name: "get_validation",
    schema: {
      title: "Get Validation",
      description: "Retrieve validation session details",
      inputSchema: {
        validation_id: z.string(),
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
