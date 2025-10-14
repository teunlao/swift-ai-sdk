import * as fs from "node:fs";
import * as path from "node:path";
import { FLOW_DIR, REPORTS_DIR, REQUESTS_DIR } from "./constants.js";

const DIRECTORIES = [FLOW_DIR, REPORTS_DIR, REQUESTS_DIR];

export function ensureAutomationDirectories(worktreePath: string): void {
  for (const relative of DIRECTORIES) {
    const absolute = path.join(worktreePath, relative);
    if (!fs.existsSync(absolute)) {
      fs.mkdirSync(absolute, { recursive: true });
    }
  }
}

export function readFlowFile(flowPath: string): string | null {
  try {
    return fs.readFileSync(flowPath, "utf-8");
  } catch (error) {
    return null;
  }
}

export function fileExists(filePath: string): boolean {
  return fs.existsSync(filePath);
}
