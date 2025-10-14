/**
 * Merge Agent Worktree Tool
 */

import type { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import * as fs from "fs";
import { simpleGit } from "simple-git";
import { z } from "zod";
import { removeWorktree } from "../git.js";

interface MergeAgentInput {
	agent_id: string;
	commit_message: string;
	target_branch?: string;
}

interface MergeAgentOutput {
	agent_id: string;
	role: string;
	status: string;
	worktree?: string | null;
	source_branch: string;
	target_branch: string;
	commit: string;
	merge_summary: {
		changes: number;
		insertions: number;
		deletions: number;
	};
	cleanup: {
		worktree_removed: boolean;
		branch_deleted: boolean;
	};
	message: string;
}

function formatResult(params: {
	agent_id: string;
	agent_role: string;
	agent_status: string;
	worktree: string | null;
	source_branch: string;
	target_branch: string;
	commit: string;
	mergeSummary: {
		changes: number;
		insertions: number;
		deletions: number;
	};
	cleanup: {
		worktreeRemoved: boolean;
		branchDeleted: boolean;
	};
}): {
	content: Array<{ type: "text"; text: string }>;
	structuredContent: MergeAgentOutput;
} {
	const { mergeSummary, cleanup } = params;
	const structured: MergeAgentOutput = {
		agent_id: params.agent_id,
		role: params.agent_role,
		status: params.agent_status,
		worktree: params.worktree,
		source_branch: params.source_branch,
		target_branch: params.target_branch,
		commit: params.commit,
		merge_summary: {
			changes: mergeSummary.changes,
			insertions: mergeSummary.insertions,
			deletions: mergeSummary.deletions,
		},
		cleanup: {
			worktree_removed: cleanup.worktreeRemoved,
			branch_deleted: cleanup.branchDeleted,
		},
		message: `Merged ${params.source_branch} into ${params.target_branch} with commit ${params.commit}`,
	};

	return {
		content: [
			{
				type: "text",
				text: JSON.stringify(structured, null, 2),
			},
		],
		structuredContent: structured,
	};
}

export function createMergeAgentTool(db: OrchestratorDB) {
	return {
		name: "merge_agent_worktree",
		schema: {
			title: "Merge Agent Worktree",
			description: `Commit and merge an agent's worktree into the main branch, then clean up the worktree.

WHAT IT DOES:
- Stages and commits all changes in the agent's worktree using the provided commit message.
- Merges the agent branch into the main branch in the primary repository worktree.
- Updates the agent status to 'merged' on success.
- Removes the agent's Git worktree directory and deletes the agent branch.

WHEN TO USE:
- After validation approves executor changes and you are ready to land them.
- To replace the manual workflow of git add/commit/merge/cleanup for agent worktrees.

REQUIREMENTS:
- Commit message is REQUIRED.
- Agent must have an existing worktree (auto mode launch).
- Main worktree must have a clean status (no uncommitted changes).`,
			inputSchema: {
				agent_id: z
					.string()
					.describe(
						"Executor agent ID whose worktree should be merged (e.g., 'executor-1760408478640').",
					),
				commit_message: z
					.string()
					.min(1, "Commit message cannot be empty")
					.describe(
						"Commit message to use when committing the agent's work. Required.",
					),
				target_branch: z
					.string()
					.default("main")
					.describe(
						"Target branch to merge into. Defaults to 'main'. Override only for non-standard workflows.",
					),
			},
		},
		handler: async (args: MergeAgentInput) => {
			const agentId = args.agent_id;
			const commitMessage = args.commit_message.trim();
			const targetBranch = (args.target_branch ?? "main").trim() || "main";

			try {
				const agent = db.getAgent(agentId);
				if (!agent) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent not found: ${agentId}`,
							},
						],
					};
				}

				if (agent.role !== "executor") {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent ${agentId} is not an executor (role: ${agent.role}). Only executor worktrees can be merged automatically.`,
							},
						],
					};
				}

				if (!agent.worktree) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Agent ${agentId} has no recorded worktree`,
							},
						],
					};
				}

				if (!fs.existsSync(agent.worktree)) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Worktree path does not exist: ${agent.worktree}`,
							},
						],
					};
				}

				if (!commitMessage) {
					return {
						content: [
							{
								type: "text" as const,
								text: "Commit message cannot be empty",
							},
						],
					};
				}

				const projectRoot = process.env.PROJECT_ROOT || process.cwd();
				const worktreeGit = simpleGit(agent.worktree);
				const rootGit = simpleGit(projectRoot);

				const rootStatus = await rootGit.status();
				if (!rootStatus.isClean()) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Main worktree has uncommitted changes. Please clean main before merging. Status: ${JSON.stringify(rootStatus, null, 2)}`,
							},
						],
					};
				}

				const status = await worktreeGit.status();
				if (status.isClean()) {
					return {
						content: [
							{
								type: "text" as const,
								text: `No changes to commit in worktree for agent ${agentId}`,
							},
						],
					};
				}

				const sourceBranch = (
					await worktreeGit.revparse(["--abbrev-ref", "HEAD"])
				).trim();
				if (!sourceBranch || sourceBranch === "HEAD") {
					return {
						content: [
							{
								type: "text" as const,
								text: `Unable to determine branch for agent ${agentId}. Ensure the worktree is on a named branch.`,
							},
						],
					};
				}

				await worktreeGit.add(["-A"]);
				const commitResult = await worktreeGit.commit(commitMessage);
				if (!commitResult.commit) {
					return {
						content: [
							{
								type: "text" as const,
								text: `Git commit failed for agent ${agentId}`,
							},
						],
					};
				}

				const commitSha = (await worktreeGit.revparse(["HEAD"])).trim();

				const initialBranch = (
					await rootGit.revparse(["--abbrev-ref", "HEAD"])
				).trim();
				let checkoutPerformed = false;
				if (initialBranch !== targetBranch) {
					await rootGit.checkout(targetBranch);
					checkoutPerformed = true;
				}

				let mergeSummary: any;
				try {
					mergeSummary = await rootGit.merge([sourceBranch]);
				} catch (error) {
					try {
						await rootGit.raw(["merge", "--abort"]);
					} catch (abortError) {
						console.error(
							`Failed to abort merge: ${abortError instanceof Error ? abortError.message : String(abortError)}`,
						);
					}

					if (checkoutPerformed) {
						await rootGit.checkout(initialBranch);
					}

					return {
						content: [
							{
								type: "text" as const,
								text: `Merge failed: ${error instanceof Error ? error.message : String(error)}`,
							},
						],
					};
				}

				if (
					mergeSummary.failed ||
					(mergeSummary.conflicts && mergeSummary.conflicts.length > 0)
				) {
					try {
						await rootGit.raw(["merge", "--abort"]);
					} catch (abortError) {
						console.error(
							`Failed to abort merge: ${abortError instanceof Error ? abortError.message : String(abortError)}`,
						);
					}

					if (checkoutPerformed) {
						await rootGit.checkout(initialBranch);
					}

					return {
						content: [
							{
								type: "text" as const,
								text: `Merge produced conflicts. Resolve manually before retrying. Conflicts: ${JSON.stringify(mergeSummary.conflicts ?? [], null, 2)}`,
							},
						],
					};
				}

				let worktreeRemoved = false;
				if (agent.worktree !== projectRoot) {
					await removeWorktree(agent.worktree, projectRoot);
					worktreeRemoved = true;
				}

				let branchDeleted = false;
				if (sourceBranch !== targetBranch) {
					try {
						await rootGit.branch(["-d", sourceBranch]);
						branchDeleted = true;
					} catch (branchError) {
						// Attempt forced delete if branch remains after merge
						try {
							await rootGit.branch(["-D", sourceBranch]);
							branchDeleted = true;
						} catch {
							throw new Error(
								`Merged but failed to delete branch ${sourceBranch}: ${
									branchError instanceof Error
										? branchError.message
										: String(branchError)
								}`,
							);
						}
					}
				}

				const shouldRestoreBranch =
					checkoutPerformed &&
					initialBranch !== targetBranch &&
					initialBranch !== sourceBranch;
				if (shouldRestoreBranch) {
					await rootGit.checkout(initialBranch);
				}

				const mergeStats = {
					changes: mergeSummary.summary.changes,
					insertions: mergeSummary.summary.insertions,
					deletions: mergeSummary.summary.deletions,
				};

				const now = new Date().toISOString();
				const agentUpdates: Record<string, unknown> = {
					status: "merged",
					last_activity: now,
				};
				if (!agent.ended_at) {
					agentUpdates.ended_at = now;
				}
				if (worktreeRemoved) {
					agentUpdates.worktree = null;
				}
				db.updateAgent(agentId, agentUpdates as Partial<typeof agent>);

				return formatResult({
					agent_id: agentId,
					agent_role: agent.role,
					agent_status: "merged",
					worktree: worktreeRemoved ? null : agent.worktree,
					source_branch: sourceBranch,
					target_branch: targetBranch,
					commit: commitSha,
					mergeSummary: mergeStats,
					cleanup: {
						worktreeRemoved,
						branchDeleted,
					},
				});
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
