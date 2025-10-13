-- Orchestrator MCP Database Schema

-- Table: agents
CREATE TABLE IF NOT EXISTS agents (
  id TEXT PRIMARY KEY,              -- "executor-1", "validator-2"
  role TEXT NOT NULL,               -- "executor" | "validator"
  task_id TEXT,                     -- "6.2", "10.3"
  shell_id TEXT NOT NULL,           -- hex ID from Bash tool
  worktree TEXT,                    -- "/path/to/worktree"
  prompt TEXT,                      -- initial prompt
  status TEXT NOT NULL DEFAULT 'running', -- "running" | "stuck" | "completed" | "killed"
  created_at TEXT NOT NULL,         -- ISO 8601 timestamp
  started_at TEXT,
  ended_at TEXT,
  events_count INTEGER DEFAULT 0,
  commands_count INTEGER DEFAULT 0,
  patches_count INTEGER DEFAULT 0,
  files_created INTEGER DEFAULT 0,
  last_activity TEXT,
  stuck_detected INTEGER DEFAULT 0, -- boolean 0/1
  auto_recover_attempts INTEGER DEFAULT 0
);

-- Table: agent_logs (optional, for detailed logging)
CREATE TABLE IF NOT EXISTS agent_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  agent_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  event_type TEXT,                 -- "reasoning" | "command" | "error" | "stuck"
  content TEXT,
  FOREIGN KEY (agent_id) REFERENCES agents(id)
);

-- Table: config
CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);
CREATE INDEX IF NOT EXISTS idx_agents_role ON agents(role);
CREATE INDEX IF NOT EXISTS idx_agents_task_id ON agents(task_id);
CREATE INDEX IF NOT EXISTS idx_agent_logs_agent_id ON agent_logs(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_logs_timestamp ON agent_logs(timestamp);

-- Insert default config
INSERT OR IGNORE INTO config (key, value) VALUES ('auto_recover_enabled', 'false');
INSERT OR IGNORE INTO config (key, value) VALUES ('stuck_threshold_minutes', '10');
INSERT OR IGNORE INTO config (key, value) VALUES ('max_retries', '2');
