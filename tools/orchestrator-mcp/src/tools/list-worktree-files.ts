/**
 * List Worktree Files Tool
 */

import { z } from "zod";
import * as fs from "fs";
import * as path from "path";
import type {
	OrchestratorDB,
	ListWorktreeFilesInput,
	ListWorktreeFilesOutput,
} from "@swift-ai-sdk/orchestrator-db";

const WILDCARD_STAR_PLACEHOLDER = "__wildcard_star__";
const WILDCARD_QUESTION_PLACEHOLDER = "__wildcard_question__";

/**
 * Convert a simple wildcard pattern into an equivalent regular expression.
 * Supports `*` (any number of characters) and `?` (single character) while
 * escaping any other regex meta characters to ensure literal matching.
 */
export function createPatternRegex(pattern: string): RegExp {
	const withPlaceholders = pattern
		.replaceAll("*", WILDCARD_STAR_PLACEHOLDER)
		.replaceAll("?", WILDCARD_QUESTION_PLACEHOLDER);

	const escaped = withPlaceholders.replaceAll(
		/[.+^${}()|[\]\\]/g,
		(match) => `\\${match}`,
	);

	const regexSource = escaped
		.replaceAll(WILDCARD_STAR_PLACEHOLDER, ".*")
		.replaceAll(WILDCARD_QUESTION_PLACEHOLDER, ".");

	return new RegExp(`^${regexSource}$`);
}

export function createListWorktreeFilesTool(db: OrchestratorDB) {
	return {
		name: "list_worktree_files",
		schema: {
			title: "List Worktree Files",
			description: "List files in an agent's worktree",
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Agent ID whose worktree to list (e.g., 'executor-1760408478640'). Returns files created or modified by this agent in its isolated worktree directory."
					),
				pattern: z
					.string()
					.optional()
					.describe(
						"File pattern filter using wildcards. Examples: '*.txt' (text files), '*.swift' (Swift files), 'Test*.swift' (test files), '*' (all files). Default: '*.txt'. Supports * (any chars) and ? (single char)."
					),
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
				const regex = createPatternRegex(pattern);

				for (const entry of entries) {
					if (entry.isFile()) {
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
