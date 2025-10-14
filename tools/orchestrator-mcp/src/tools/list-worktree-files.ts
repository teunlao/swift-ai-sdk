/**
 * List Worktree Files Tool
 */

import { z } from "zod";
import * as fs from "fs";
import * as path from "path";
import type { OrchestratorDB } from "../database.js";
import type {
	ListWorktreeFilesInput,
	ListWorktreeFilesOutput,
} from "../types.js";

export function createListWorktreeFilesTool(db: OrchestratorDB) {
	return {
		name: "list_worktree_files",
		schema: {
			title: "List Worktree Files",
			description: "List files in an agent's worktree",
			inputSchema: {
				agent_id: z.string(),
				pattern: z.string().optional(),
			},
		},
		handler: async (args: ListWorktreeFilesInput) => {
			try {
				const agent = db.getAgent(args.agent_id);
				if (!agent || !agent.worktree) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent ${args.agent_id} not found or has no worktree`,
							},
						],
					};
				}

				const worktreePath = agent.worktree;
				const pattern = args.pattern || "*.txt";
				const files: Array<{ name: string; size: number; modified: string }> =
					[];

				// Read directory
				const entries = fs.readdirSync(worktreePath, { withFileTypes: true });

				for (const entry of entries) {
					if (entry.isFile()) {
						// Simple pattern matching (only * wildcard)
						const regex = new RegExp(
							"^" + pattern.replace(/\*/g, ".*").replace(/\?/g, ".") + "$"
						);
						if (regex.test(entry.name)) {
							const fullPath = path.join(worktreePath, entry.name);
							const stats = fs.statSync(fullPath);
							files.push({
								name: entry.name,
								size: stats.size,
								modified: stats.mtime.toISOString(),
							});
						}
					}
				}

				const result: ListWorktreeFilesOutput = {
					agent_id: args.agent_id,
					worktree: worktreePath,
					files: files.sort((a, b) => a.name.localeCompare(b.name)),
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
