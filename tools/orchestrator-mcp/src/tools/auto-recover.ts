/**
 * Auto Recover Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "../database.js";
import type { AutoRecoverInput, AutoRecoverOutput } from "../types.js";

export function createAutoRecoverTool(db: OrchestratorDB) {
	return {
		name: "auto_recover",
		schema: {
			title: "Auto Recovery",
			description: "Configure automatic agent recovery",
			inputSchema: {
				enable: z.boolean(),
				stuck_threshold_minutes: z.number().optional().default(10),
				max_retries: z.number().optional().default(2),
			},
		},
		handler: async (args: AutoRecoverInput) => {
			try {
				// Save config
				db.setConfig("auto_recover_enabled", String(args.enable));
				db.setConfig(
					"stuck_threshold_minutes",
					String(args.stuck_threshold_minutes || 10)
				);
				db.setConfig("max_retries", String(args.max_retries || 2));

				const result: AutoRecoverOutput = {
					enabled: args.enable,
					config: {
						stuck_threshold_minutes: args.stuck_threshold_minutes || 10,
						max_retries: args.max_retries || 2,
					},
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
