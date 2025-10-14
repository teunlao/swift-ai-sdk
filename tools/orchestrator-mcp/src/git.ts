/**
 * Git Worktree Management
 *
 * Handles creation and removal of Git worktrees for agent isolation.
 */

import { simpleGit, SimpleGit } from "simple-git";
import * as fs from "fs";
import * as path from "path";

const WORKTREE_BRANCH_PREFIX = "agent/";

function normalizeWorktreeInput(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) {
    throw new Error("Worktree name is required");
  }

  const withoutPrefix = trimmed.startsWith(WORKTREE_BRANCH_PREFIX)
    ? trimmed.slice(WORKTREE_BRANCH_PREFIX.length)
    : trimmed;

  const normalized = withoutPrefix
    .replace(/\s+/g, "-")
    .replace(/[^A-Za-z0-9\/_-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/\/{2,}/g, "/")
    .replace(/^[-/]+|[-/]+$/g, "");

  if (!normalized) {
    throw new Error(
      "Worktree name must contain alphanumeric characters after the 'agent/' prefix",
    );
  }

  if (!/^[A-Za-z0-9][A-Za-z0-9\/_-]*$/.test(normalized)) {
    throw new Error(
      "Worktree name must start with an alphanumeric character and may only include letters, numbers, '/', '-', or '_'",
    );
  }

  return normalized;
}

export function normalizeWorktreeName(name: string): {
  branch: string;
  slug: string;
  directory: string;
} {
  const slug = normalizeWorktreeInput(name);
  const branch = `${WORKTREE_BRANCH_PREFIX}${slug}`;
  const directory = `swift-ai-sdk-${WORKTREE_BRANCH_PREFIX.replace(/\//g, "-")}${slug.replace(/\//g, "-")}`;
  return { branch, slug, directory };
}

export interface WorktreeInfo {
  path: string;
  branch: string;
}

/**
 * Create a new Git worktree for an agent
 */
export async function createWorktree(
  agentId: string,
  projectRoot: string,
  requestedName: string
): Promise<WorktreeInfo> {
  const git: SimpleGit = simpleGit(projectRoot);

  const { branch, directory } = normalizeWorktreeName(requestedName);
  const worktreePath = path.join(path.dirname(projectRoot), directory);

  // Ensure branch does not already exist
  const branchList = await git.branch(["--list", branch]);
  if (branchList.all.includes(branch)) {
    throw new Error(`Branch ${branch} already exists. Choose a different worktree name.`);
  }

  // Check if worktree already exists
  if (fs.existsSync(worktreePath)) {
    throw new Error(`Worktree already exists at ${worktreePath}`);
  }

  // Create worktree with new branch
  await git.raw(["worktree", "add", "-b", branch, worktreePath, "main"]);

  return {
    path: worktreePath,
    branch,
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
  requestedName: string,
  projectRoot: string
): Promise<boolean> {
  const { directory } = normalizeWorktreeName(requestedName);
  const worktreePath = path.join(path.dirname(projectRoot), directory);
  return fs.existsSync(worktreePath);
}

/**
 * Get worktree path for an agent
 */
export function getWorktreePath(
  requestedName: string,
  projectRoot: string
): string {
  const { directory } = normalizeWorktreeName(requestedName);
  return path.join(path.dirname(projectRoot), directory);
}
