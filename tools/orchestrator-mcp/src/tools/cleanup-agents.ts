/**
 * Cleanup Agents Tool
 */

import { z } from "zod";
import type { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";
import { listWorktrees, removeWorktree } from "../git.js";

type Strategy = "by_status" | "by_age" | "by_date" | "all";

interface CleanupAgentsInput {
  strategy: Strategy;
  status?: string;
  count?: number;
  older_than?: string; // ISO date
  dry_run?: boolean; // default true
  confirm?: boolean; // default false
}

interface CleanupAgentEntry {
  id: string;
  role: string;
  status: string;
  created_at: string;
  worktree?: string | null;
  worktree_will_be_removed?: boolean;
  worktree_removed?: boolean;
  error?: string;
}

interface CleanupAgentsOutput {
  [key: string]: unknown;
  strategy: Strategy;
  dry_run: boolean;
  confirm: boolean;
  selected_count: number;
  skipped_protected_count: number;
  deleted_count: number;
  freed_worktrees: number;
  agents: CleanupAgentEntry[];
  notes?: string[];
}

const PROTECTED_STATUSES = new Set(["running", "needs_fix", "stuck", "blocked"]);

export function createCleanupAgentsTool(db: OrchestratorDB) {
  return {
    name: "cleanup_agents",
    schema: {
      title: "Cleanup Agents",
      description: `Clean up old agent records from the orchestrator database with multiple strategies.

WHAT IT DOES:
Deletes agent rows from the database according to a strategy. Never deletes protected statuses (running, stuck/blocked, needs_fix). When not a dry run and confirmed, also attempts to remove matching Git worktrees created for those agents.

STRATEGIES:
- by_status: Delete agents with a specific status (e.g., killed, completed, validated)
- by_age: Delete N oldest deletable agents
- by_date: Delete agents created at or before a given ISO date
- all: Delete all deletable agents (requires confirm=true)

SAFETY:
- Default dry_run=true (preview without deleting)
- confirm=true required for actual deletion (when dry_run=false)
- Protected statuses are never deleted: running, stuck/blocked, needs_fix
`,
      inputSchema: {
        strategy: z
          .enum(["by_status", "by_age", "by_date", "all"]) 
          .describe(
            "Cleanup strategy: by_status | by_age | by_date | all"
          ),
        status: z
          .string()
          .optional()
          .describe(
            "Target status when strategy='by_status' (e.g., 'killed', 'completed', 'validated'). Protected statuses are never deleted."
          ),
        count: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("Number of oldest agents to delete when strategy='by_age'."),
        older_than: z
          .string()
          .optional()
          .describe(
            "ISO 8601 date; delete agents created on or before this date when strategy='by_date'."
          ),
        dry_run: z
          .boolean()
          .optional()
          .default(true)
          .describe(
            "Preview mode. When true (default), shows what would be deleted without making changes."
          ),
        confirm: z
          .boolean()
          .optional()
          .default(false)
          .describe(
            "Required to perform actual deletion when dry_run=false. Prevents accidental data loss."
          ),
      },
    },
    handler: async (args: CleanupAgentsInput) => {
      try {
        const dryRun = args.dry_run ?? true;
        const confirm = args.confirm ?? false;
        const strategy = args.strategy;
        const projectRoot = process.env.PROJECT_ROOT || process.cwd();

        // Gather candidates based on strategy
        const allAgents = db.getAllAgents();

        // Helper to sort by created_at ASC (oldest first)
        const byCreatedAsc = (a: any, b: any) =>
          new Date(a.created_at).getTime() - new Date(b.created_at).getTime();

        let selected = [] as CleanupAgentEntry[];
        const notes: string[] = [];

        switch (strategy) {
          case "by_status": {
            if (!args.status) {
              throw new Error("'status' is required when strategy='by_status'");
            }
            const target = args.status;
            if (PROTECTED_STATUSES.has(target)) {
              throw new Error(
                `Refusing to delete protected status '${target}'. Allowed examples: killed, completed, validated.`
              );
            }
            selected = allAgents
              .filter((a) => a.status === target)
              .map((a) => ({
                id: a.id,
                role: a.role,
                status: a.status,
                created_at: a.created_at,
                worktree: a.worktree,
              }));
            break;
          }
          case "by_age": {
            if (!args.count || args.count <= 0) {
              throw new Error(
                "'count' must be a positive integer when strategy='by_age'"
              );
            }
            const deletable = allAgents
              .filter((a) => !PROTECTED_STATUSES.has(a.status))
              .sort(byCreatedAsc);
            selected = deletable.slice(0, args.count).map((a) => ({
              id: a.id,
              role: a.role,
              status: a.status,
              created_at: a.created_at,
              worktree: a.worktree,
            }));
            break;
          }
          case "by_date": {
            if (!args.older_than) {
              throw new Error(
                "'older_than' ISO date is required when strategy='by_date'"
              );
            }
            const cutoff = new Date(args.older_than);
            if (isNaN(cutoff.getTime())) {
              throw new Error(
                `Invalid 'older_than' date: ${args.older_than}. Use ISO 8601.`
              );
            }
            selected = allAgents
              .filter((a) => new Date(a.created_at).getTime() <= cutoff.getTime())
              .map((a) => ({
                id: a.id,
                role: a.role,
                status: a.status,
                created_at: a.created_at,
                worktree: a.worktree,
              }));
            break;
          }
          case "all": {
            selected = allAgents.map((a) => ({
              id: a.id,
              role: a.role,
              status: a.status,
              created_at: a.created_at,
              worktree: a.worktree,
            }));
            break;
          }
          default:
            throw new Error(`Unknown strategy: ${strategy}`);
        }

        // Split into deletable vs protected
        const protectedEntries: CleanupAgentEntry[] = [];
        const deletableEntries: CleanupAgentEntry[] = [];
        for (const entry of selected) {
          if (PROTECTED_STATUSES.has(entry.status)) {
            protectedEntries.push(entry);
          } else {
            deletableEntries.push(entry);
          }
        }

        // Determine which worktrees could be removed (preview)
        const worktrees = await listWorktrees(projectRoot).catch(() => []);
        const knownWorktreePaths = new Set(worktrees.map((w) => w.path));

        for (const e of deletableEntries) {
          const path = e.worktree ?? undefined;
          e.worktree_will_be_removed = Boolean(
            path && knownWorktreePaths.has(path) && path !== projectRoot && path.includes("swift-ai-sdk-agent-")
          );
        }

        // Handle dry run or actual deletion
        let deletedCount = 0;
        let freedWorktrees = 0;
        const results: CleanupAgentEntry[] = [];

        if (dryRun) {
          results.push(...[...deletableEntries, ...protectedEntries]);
          notes.push(
            "Dry run: no data was deleted. Set dry_run=false and confirm=true to proceed."
          );
        } else {
          if (!confirm) {
            throw new Error(
              "Refusing to delete without confirm=true. Use dry_run=true to preview."
            );
          }

          // Perform deletions
          for (const entry of deletableEntries) {
            const res: CleanupAgentEntry = { ...entry };
            try {
              // Attempt to remove worktree when recognized and safe
              if (entry.worktree_will_be_removed && entry.worktree) {
                try {
                  await removeWorktree(entry.worktree, projectRoot);
                  res.worktree_removed = true;
                  freedWorktrees += 1;
                } catch (wtErr) {
                  res.error = `Failed to remove worktree: ${wtErr instanceof Error ? wtErr.message : String(wtErr)}`;
                  res.worktree_removed = false;
                }
              }

              // Delete agent record last
              db.deleteAgent(entry.id);
              deletedCount += 1;
            } catch (err) {
              res.error = err instanceof Error ? err.message : String(err);
            }
            results.push(res);
          }

          // Add protected entries to results (skipped)
          for (const entry of protectedEntries) {
            results.push({ ...entry, error: "protected_status" });
          }
        }

        const output: CleanupAgentsOutput = {
          strategy,
          dry_run: dryRun,
          confirm,
          selected_count: selected.length,
          skipped_protected_count: protectedEntries.length,
          deleted_count: deletedCount,
          freed_worktrees: freedWorktrees,
          agents: results,
          notes: notes.length ? notes : undefined,
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
