/**
 * Git Worktree Management
 *
 * Handles creation and removal of Git worktrees for agent isolation.
 */

import { simpleGit, SimpleGit } from "simple-git";
import * as fs from "fs";
import * as path from "path";

export interface WorktreeInfo {
  path: string;
  branch: string;
}

/**
 * Create a new Git worktree for an agent
 */
export async function createWorktree(
  agentId: string,
  projectRoot: string
): Promise<WorktreeInfo> {
  const git: SimpleGit = simpleGit(projectRoot);

  // Generate worktree path and branch name
  const worktreeName = `agent-${agentId}`;
  const worktreePath = path.join(
    path.dirname(projectRoot),
    `swift-ai-sdk-${worktreeName}`
  );
  const branchName = `agent/${agentId}`;

  // Check if worktree already exists
  if (fs.existsSync(worktreePath)) {
    throw new Error(`Worktree already exists at ${worktreePath}`);
  }

  // Create worktree with new branch
  await git.raw(["worktree", "add", "-b", branchName, worktreePath, "main"]);

  return {
    path: worktreePath,
    branch: branchName,
  };
}

/**
 * Remove a Git worktree
 */
export async function removeWorktree(
  worktreePath: string,
  projectRoot: string
): Promise<void> {
  const git: SimpleGit = simpleGit(projectRoot);

  // Check if worktree exists
  if (!fs.existsSync(worktreePath)) {
    throw new Error(`Worktree does not exist at ${worktreePath}`);
  }

  // Remove worktree
  await git.raw(["worktree", "remove", worktreePath, "--force"]);
}

/**
 * List all worktrees
 */
export async function listWorktrees(
  projectRoot: string
): Promise<Array<{ path: string; branch: string }>> {
  const git: SimpleGit = simpleGit(projectRoot);

  const output = await git.raw(["worktree", "list", "--porcelain"]);
  const lines = output.trim().split("\n");

  const worktrees: Array<{ path: string; branch: string }> = [];
  let currentWorktree: { path?: string; branch?: string } = {};

  for (const line of lines) {
    if (line.startsWith("worktree ")) {
      currentWorktree.path = line.substring("worktree ".length);
    } else if (line.startsWith("branch ")) {
      currentWorktree.branch = line.substring("branch ".length);
    } else if (line === "") {
      if (currentWorktree.path && currentWorktree.branch) {
        worktrees.push({
          path: currentWorktree.path,
          branch: currentWorktree.branch,
        });
      }
      currentWorktree = {};
    }
  }

  // Handle last worktree
  if (currentWorktree.path && currentWorktree.branch) {
    worktrees.push({
      path: currentWorktree.path,
      branch: currentWorktree.branch,
    });
  }

  return worktrees;
}

/**
 * Check if a worktree exists for an agent
 */
export async function worktreeExists(
  agentId: string,
  projectRoot: string
): Promise<boolean> {
  const worktreeName = `agent-${agentId}`;
  const worktreePath = path.join(
    path.dirname(projectRoot),
    `swift-ai-sdk-${worktreeName}`
  );

  return fs.existsSync(worktreePath);
}

/**
 * Get worktree path for an agent
 */
export function getWorktreePath(
  agentId: string,
  projectRoot: string
): string {
  const worktreeName = `agent-${agentId}`;
  return path.join(
    path.dirname(projectRoot),
    `swift-ai-sdk-${worktreeName}`
  );
}
