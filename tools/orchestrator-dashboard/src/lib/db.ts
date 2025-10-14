import { OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";

declare global {
	var __ORCHESTRATOR_DASHBOARD_DB__: OrchestratorDB | undefined;
}

export function getDb(): OrchestratorDB {
	if (!globalThis.__ORCHESTRATOR_DASHBOARD_DB__) {
		// OrchestratorDB automatically uses ~/claude-orchestrator/orchestrator.db
		globalThis.__ORCHESTRATOR_DASHBOARD_DB__ = new OrchestratorDB();
	}

	return globalThis.__ORCHESTRATOR_DASHBOARD_DB__;
}

export type {
	Agent,
	AgentLog,
	AgentRole,
	AgentStatus,
	HistoryEntry,
	ValidationSession,
	ValidationStatus,
} from "@swift-ai-sdk/orchestrator-db";
