import * as path from "node:path";
import { FLOW_DIR, REPORTS_DIR, REQUESTS_DIR } from "./constants.js";

export function getFlowFilePath(agentId: string): string {
  return path.posix.join(FLOW_DIR, `${agentId}.json`);
}

export function buildRequestFileName(
  taskId: string | null,
  iteration: number,
  timestamp: string
): string {
  const taskPart = taskId ? taskId.replace(/[^A-Za-z0-9_-]/g, "-") : "task";
  return `validate-${taskPart}-${iteration}-${timestamp}.md`;
}

export function buildReportFileName(
  taskId: string | null,
  iteration: number,
  timestamp: string
): string {
  const taskPart = taskId ? taskId.replace(/[^A-Za-z0-9_-]/g, "-") : "task";
  return `validate-${taskPart}-${iteration}-${timestamp}-report.md`;
}

export function getRequestFilePath(fileName: string): string {
  return path.posix.join(REQUESTS_DIR, fileName);
}

export function getReportFilePath(fileName: string): string {
  return path.posix.join(REPORTS_DIR, fileName);
}
