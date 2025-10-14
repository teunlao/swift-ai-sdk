/**
 * SQLite database wrapper for Orchestrator MCP
 */

import Database from "better-sqlite3";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import type {
  Agent,
  AgentLog,
  Config,
  ValidationSession,
  ValidationStatus,
} from "./types.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class OrchestratorDB {
  private db: Database.Database;

  constructor(dbPath?: string) {
    // Priority: 1) parameter, 2) env variable, 3) default (in orchestrator-mcp folder)
    const defaultPath = process.env.DATABASE_PATH || join(__dirname, "../orchestrator.db");
    this.db = new Database(dbPath || defaultPath);
    this.initialize();
  }

  private initialize() {
    // Read and execute schema
    const schemaPath = join(__dirname, "../database/schema.sql");
    const schema = readFileSync(schemaPath, "utf-8");
    this.db.exec(schema);

    // Ensure new columns exist when upgrading from previous schema versions
    try {
      this.db.prepare("ALTER TABLE agents ADD COLUMN current_validation_id TEXT").run();
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("duplicate column")) {
        throw error;
      }
    }
  }

  // ============ Agents ============

  createAgent(
    agent: Omit<
      Agent,
      | "events_count"
      | "commands_count"
      | "patches_count"
      | "files_created"
      | "stuck_detected"
      | "auto_recover_attempts"
    >
  ): Agent {
    const stmt = this.db.prepare(`
      INSERT INTO agents (
        id, role, task_id, shell_id, worktree, prompt, status,
        created_at, started_at, ended_at, last_activity, current_validation_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      agent.id,
      agent.role,
      agent.task_id,
      agent.shell_id,
      agent.worktree,
      agent.prompt,
      agent.status,
      agent.created_at,
      agent.started_at,
      agent.ended_at,
      agent.last_activity,
      agent.current_validation_id
    );

    return this.getAgent(agent.id)!;
  }

  getAgent(id: string): Agent | undefined {
    const stmt = this.db.prepare("SELECT * FROM agents WHERE id = ?");
    return stmt.get(id) as Agent | undefined;
  }

  getAllAgents(filter?: { status?: string; role?: string }): Agent[] {
    let query = "SELECT * FROM agents";
    const conditions: string[] = [];
    const params: any[] = [];

    if (filter?.status) {
      conditions.push("status = ?");
      params.push(filter.status);
    }
    if (filter?.role) {
      conditions.push("role = ?");
      params.push(filter.role);
    }

    if (conditions.length > 0) {
      query += " WHERE " + conditions.join(" AND ");
    }

    query += " ORDER BY created_at DESC";

    const stmt = this.db.prepare(query);
    return stmt.all(...params) as Agent[];
  }

  updateAgent(id: string, updates: Partial<Agent>): void {
    const fields: string[] = [];
    const values: any[] = [];

    for (const [key, value] of Object.entries(updates)) {
      fields.push(`${key} = ?`);
      values.push(value);
    }

    if (fields.length === 0) return;

    values.push(id);
    const stmt = this.db.prepare(`
      UPDATE agents SET ${fields.join(", ")} WHERE id = ?
    `);
    stmt.run(...values);
  }

  deleteAgent(id: string): void {
    const stmt = this.db.prepare("DELETE FROM agents WHERE id = ?");
    stmt.run(id);
  }

  // ============ Agent Logs ============

  addLog(log: Omit<AgentLog, "id">): void {
    const stmt = this.db.prepare(`
      INSERT INTO agent_logs (agent_id, timestamp, event_type, content)
      VALUES (?, ?, ?, ?)
    `);
    stmt.run(log.agent_id, log.timestamp, log.event_type, log.content);
  }

  getLogs(agent_id: string, filter?: string, limit?: number): AgentLog[] {
    let query = "SELECT * FROM agent_logs WHERE agent_id = ?";
    const params: any[] = [agent_id];

    // Apply filter
    if (filter && filter !== "all") {
      const typeMap: Record<string, string> = {
        reasoning: "reasoning",
        messages: "message",
        commands: "command",
        errors: "error",
      };
      const targetType = typeMap[filter];
      if (targetType) {
        query += " AND event_type = ?";
        params.push(targetType);
      }
    }

    query += " ORDER BY timestamp DESC";

    if (limit) {
      query += ` LIMIT ${limit}`;
    }

    const stmt = this.db.prepare(query);
    return stmt.all(...params) as AgentLog[];
  }

  // ============ Config ============

  getConfig(key: string): string | undefined {
    const stmt = this.db.prepare("SELECT value FROM config WHERE key = ?");
    const result = stmt.get(key) as { value: string } | undefined;
    return result?.value;
  }

  setConfig(key: string, value: string): void {
    const stmt = this.db.prepare(`
      INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)
    `);
    stmt.run(key, value);
  }

  getAllConfig(): Config[] {
    const stmt = this.db.prepare("SELECT * FROM config");
    return stmt.all() as Config[];
  }

  // ============ Utilities ============

  close(): void {
    this.db.close();
  }

  // Get agent count by status
  getAgentCount(status?: string): number {
    let query = "SELECT COUNT(*) as count FROM agents";
    if (status) {
      query += " WHERE status = ?";
      const stmt = this.db.prepare(query);
      const result = stmt.get(status) as { count: number };
      return result.count;
    }
    const stmt = this.db.prepare(query);
    const result = stmt.get() as { count: number };
    return result.count;
  }

  // ============ History ============

  getAgentHistory(filters?: {
    from_date?: string;
    to_date?: string;
    task_id?: string;
    role?: string;
  }): Agent[] {
    let query = "SELECT * FROM agents WHERE 1=1";
    const params: any[] = [];

    if (filters?.from_date) {
      query += " AND created_at >= ?";
      params.push(filters.from_date);
    }

    if (filters?.to_date) {
      query += " AND created_at <= ?";
      params.push(filters.to_date);
    }

    if (filters?.task_id) {
      query += " AND task_id = ?";
      params.push(filters.task_id);
    }

    if (filters?.role) {
      query += " AND role = ?";
      params.push(filters.role);
    }

    query += " ORDER BY created_at DESC";

    const stmt = this.db.prepare(query);
    return stmt.all(...params) as Agent[];
  }

  // ============ Validation Sessions ============

  createValidationSession(session: ValidationSession): ValidationSession {
    const stmt = this.db.prepare(`
      INSERT INTO validation_sessions (
        id, task_id, executor_id, validator_id, status,
        executor_worktree, executor_branch, request_path, report_path,
        summary, requested_at, started_at, finished_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      session.id,
      session.task_id,
      session.executor_id,
      session.validator_id,
      session.status,
      session.executor_worktree,
      session.executor_branch,
      session.request_path,
      session.report_path,
      session.summary,
      session.requested_at,
      session.started_at,
      session.finished_at
    );

    return this.getValidationSession(session.id)!;
  }

  getValidationSession(id: string): ValidationSession | undefined {
    const stmt = this.db.prepare(
      "SELECT * FROM validation_sessions WHERE id = ?"
    );
    const result = stmt.get(id) as ValidationSession | undefined;
    return result;
  }

  updateValidationSession(
    id: string,
    updates: Partial<ValidationSession>
  ): void {
    const fields: string[] = [];
    const values: any[] = [];

    for (const [key, value] of Object.entries(updates)) {
      fields.push(`${key} = ?`);
      values.push(value);
    }

    if (fields.length === 0) return;

    values.push(id);
    const stmt = this.db.prepare(
      `UPDATE validation_sessions SET ${fields.join(", ")} WHERE id = ?`
    );
    stmt.run(...values);
  }

  listValidationSessions(filter?: {
    status?: ValidationStatus;
    executor_id?: string;
    validator_id?: string;
  }): ValidationSession[] {
    let query = "SELECT * FROM validation_sessions WHERE 1=1";
    const params: any[] = [];

    if (filter?.status) {
      query += " AND status = ?";
      params.push(filter.status);
    }
    if (filter?.executor_id) {
      query += " AND executor_id = ?";
      params.push(filter.executor_id);
    }
    if (filter?.validator_id) {
      query += " AND validator_id = ?";
      params.push(filter.validator_id);
    }

    query += " ORDER BY requested_at DESC";

    const stmt = this.db.prepare(query);
    return stmt.all(...params) as ValidationSession[];
  }
}
