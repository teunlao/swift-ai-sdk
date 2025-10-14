/**
 * Auto Recover Tool
 */

import { z } from "zod";
import type {
  OrchestratorDB,
  AutoRecoverInput,
  AutoRecoverOutput,
} from "@swift-ai-sdk/orchestrator-db";

export function createAutoRecoverTool(db: OrchestratorDB) {
	return {
		name: "auto_recover",
		schema: {
			title: "Auto Recovery",
			description: "Configure automatic agent recovery",
			inputSchema: {
				enable: z
					.boolean()
					.describe(
						"Enable or disable automatic recovery system. 'true' activates background monitoring and auto-recovery of stuck agents. 'false' disables (manual intervention required). NOTE: Currently only stores config; recovery loop not yet implemented."
					),
				stuck_threshold_minutes: z
					.number()
					.optional()
					.default(10)
					.describe(
						"Minutes of inactivity before agent is considered stuck. System checks idle_minutes field from status. Range: 1-60. Default: 10. Lower values = more aggressive recovery, higher = more patience."
					),
				max_retries: z
					.number()
					.optional()
					.default(2)
					.describe(
						"Maximum automatic recovery attempts before giving up. After this many failed recoveries, agent is marked as 'failed' and requires manual intervention. Range: 0-5. Default: 2."
					),
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
