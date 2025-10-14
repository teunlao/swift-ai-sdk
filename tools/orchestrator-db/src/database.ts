import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import Database from "better-sqlite3";
import { createEventBus } from "./event-bus.js";
import type {
	Agent,
	AgentLog,
	Config,
	EventBus,
	OrchestratorDBOptions,
	ValidationSession,
	ValidationStatus,
} from "./types.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export class OrchestratorDB {
	private readonly db: Database.Database;
	readonly events: EventBus;
	private readonly schemaPath: string;

	constructor(options: OrchestratorDBOptions = {}) {
		const defaultSchema = join(__dirname, "../schema/schema.sql");
		this.schemaPath = options.schemaPath ?? defaultSchema;

		// Fixed canonical path: ~/claude-orchestrator/orchestrator.db
		const orchestratorDir = join(homedir(), "claude-orchestrator");
		if (!existsSync(orchestratorDir)) {
			mkdirSync(orchestratorDir, { recursive: true });
		}
		const dbPath = join(orchestratorDir, "orchestrator.db");

		console.error(`[OrchestratorDB] Connecting to database: ${dbPath}`);

		this.events = options.eventBus ?? createEventBus();

		this.db = new Database(dbPath);
		this.initialize();
	}

	private initialize() {
		const schema = readFileSync(this.schemaPath, "utf-8");
		this.db.exec(schema);

    try {
      this.db
        .prepare("ALTER TABLE agents ADD COLUMN current_validation_id TEXT")
        .run();
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("duplicate column")) {
        throw error;
      }
    }
    // add columns for model and reasoning_effort if not present
    try {
      this.db.prepare("ALTER TABLE agents ADD COLUMN model TEXT").run();
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("duplicate column")) {
        // ignore duplicate column errors only
        throw error;
      }
    }
    try {
      this.db.prepare("ALTER TABLE agents ADD COLUMN reasoning_effort TEXT").run();
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("duplicate column")) {
        throw error;
      }
    }
	}

	createAgent(
		agent: Omit<
			Agent,
			| "events_count"
			| "commands_count"
			| "patches_count"
			| "files_created"
			| "stuck_detected"
			| "auto_recover_attempts"
		>,
	): Agent {
    const stmt = this.db.prepare(`
      INSERT INTO agents (
        id, role, task_id, shell_id, worktree, prompt, model, reasoning_effort, status,
        created_at, started_at, ended_at, last_activity, current_validation_id
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

		stmt.run(
			agent.id,
			agent.role,
			agent.task_id,
			agent.shell_id,
			agent.worktree,
      agent.prompt,
      agent.model ?? null,
      agent.reasoning_effort ?? null,
      agent.status,
      agent.created_at,
      agent.started_at,
      agent.ended_at,
      agent.last_activity,
      agent.current_validation_id,
    );

		const created = this.getAgent(agent.id)!;
		this.events.publish({ type: "agent-created", agent: created });
		return created;
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

		const agent = this.getAgent(id);
		if (agent) {
			this.events.publish({ type: "agent-updated", agent });
		}
	}

	deleteAgent(id: string): void {
		const stmt = this.db.prepare("DELETE FROM agents WHERE id = ?");
		stmt.run(id);
		this.events.publish({ type: "agent-deleted", agentId: id });
	}

	addLog(log: Omit<AgentLog, "id">): Required<AgentLog> {
		const stmt = this.db.prepare(`
      INSERT INTO agent_logs (agent_id, timestamp, event_type, content)
      VALUES (?, ?, ?, ?)
    `);
		const result = stmt.run(
			log.agent_id,
			log.timestamp,
			log.event_type,
			log.content,
		);
		const stored: Required<AgentLog> = {
			id: Number(result.lastInsertRowid),
			...log,
		};
		this.events.publish({
			type: "log-added",
			agentId: log.agent_id,
			log: stored,
		});
		return stored;
	}

	getLogs(agent_id: string, filter?: string, limit?: number): AgentLog[] {
		let query = "SELECT * FROM agent_logs WHERE agent_id = ?";
		const params: any[] = [agent_id];

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
		this.events.publish({ type: "config-updated", config: { key, value } });
	}

	getAllConfig(): Config[] {
		const stmt = this.db.prepare("SELECT * FROM config");
		return stmt.all() as Config[];
	}

	close(): void {
		this.db.close();
	}

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
			session.finished_at,
		);

		const created = this.getValidationSession(session.id)!;
		this.events.publish({ type: "validation-created", validation: created });
		return created;
	}

	getValidationSession(id: string): ValidationSession | undefined {
		const stmt = this.db.prepare(
			"SELECT * FROM validation_sessions WHERE id = ?",
		);
		return stmt.get(id) as ValidationSession | undefined;
	}

	updateValidationSession(
		id: string,
		updates: Partial<ValidationSession>,
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
			`UPDATE validation_sessions SET ${fields.join(", ")} WHERE id = ?`,
		);
		stmt.run(...values);

		const validation = this.getValidationSession(id);
		if (validation) {
			this.events.publish({ type: "validation-updated", validation });
		}
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
