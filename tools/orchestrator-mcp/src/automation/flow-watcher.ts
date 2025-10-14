import * as path from "node:path";
import { ensureAutomationDirectories, readFlowFile } from "./filesystem.js";
import { getFlowFilePath } from "./flow-utils.js";
import type { FlowState } from "./flow-types.js";

export type FlowUpdateHandler = (args: {
  agentId: string;
  worktreePath: string;
  flowPath: string;
  content: string;
  state: FlowState | null;
}) => void | Promise<void>;

interface WatcherState {
  intervalId: NodeJS.Timeout;
  lastContentHash: string | null;
}

const watchers = new Map<string, WatcherState>();

function hashContent(content: string): string {
  let hash = 0;
  for (let i = 0; i < content.length; i++) {
    hash = (hash * 31 + content.charCodeAt(i)) >>> 0;
  }
  return hash.toString(16);
}

function parseFlow(content: string): FlowState | null {
  try {
    const parsed = JSON.parse(content) as FlowState;
    if (!parsed || typeof parsed !== "object") {
      return null;
    }
    return parsed;
  } catch (error) {
    return null;
  }
}

export function startFlowWatcher(
  agentId: string,
  worktreePath: string,
  handler: FlowUpdateHandler,
  intervalMs = 1500
): void {
  if (watchers.has(agentId)) {
    return;
  }

  ensureAutomationDirectories(worktreePath);
  const flowRelative = getFlowFilePath(agentId);
  const flowPath = path.join(worktreePath, flowRelative);

  const intervalId = setInterval(() => {
    const content = readFlowFile(flowPath);
    if (!content) {
      return;
    }

    const hash = hashContent(content);
    const state = watchers.get(agentId);
    if (state && state.lastContentHash === hash) {
      return;
    }

    watchers.set(agentId, {
      intervalId,
      lastContentHash: hash,
    });

    Promise.resolve(
      handler({
        agentId,
        worktreePath,
        flowPath,
        content,
        state: parseFlow(content),
      }),
    ).catch((error) => {
      console.error(`[automation] Flow handler error for ${agentId}:`, error);
    });
  }, intervalMs);

  watchers.set(agentId, {
    intervalId,
    lastContentHash: null,
  });
}

export function stopFlowWatcher(agentId: string): void {
  const watcher = watchers.get(agentId);
  if (!watcher) {
    return;
  }

  clearInterval(watcher.intervalId);
  watchers.delete(agentId);
}

export function stopAllFlowWatchers(): void {
  for (const [agentId, state] of watchers.entries()) {
    clearInterval(state.intervalId);
    watchers.delete(agentId);
  }
}
