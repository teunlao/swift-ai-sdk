/**
 * Read Worktree File Tool
 */

import { z } from "zod";
import * as fs from "fs";
import * as path from "path";
import type { OrchestratorDB } from "../database.js";
import type {
	ReadWorktreeFileInput,
	ReadWorktreeFileOutput,
} from "../types.js";

export function createReadWorktreeFileTool(db: OrchestratorDB) {
	return {
		name: "read_worktree_file",
		schema: {
			title: "Read Worktree File",
			description: "Read a file from an agent's worktree",
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID whose worktree file to read (e.g., 'executor-1760408478640'). Must have an active worktree directory."
					),
				file_path: z
					.string()
					.describe(
						"Name or relative path of file to read from agent's worktree. For security, only basename is used (directory traversal prevented). Examples: 'alpha.txt', 'Sources/Delay.swift', 'Tests/DelayTests.swift'."
					),
			},
		},
		handler: async (args: ReadWorktreeFileInput) => {
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

				// Construct full path (prevent directory traversal)
				const worktreePath = agent.worktree;
				const fileName = path.basename(args.file_path);
				const fullPath = path.join(worktreePath, fileName);

				if (!fs.existsSync(fullPath)) {
					return {
						content: [
							{
								type: "text" as const,
								text: `File not found: ${fileName}`,
							},
						],
					};
				}

				const content = fs.readFileSync(fullPath, "utf-8");

				const result: ReadWorktreeFileOutput = {
					agent_id: args.agent_id,
					file_path: fileName,
					content,
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
