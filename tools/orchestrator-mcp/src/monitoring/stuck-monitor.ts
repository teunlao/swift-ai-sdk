import type { Agent, OrchestratorDB } from "@swift-ai-sdk/orchestrator-db";

const EXECUTOR_THRESHOLD_MS = 20 * 60 * 1000; // 20 minutes
const VALIDATOR_THRESHOLD_MS = 15 * 60 * 1000; // 15 minutes
const POLL_INTERVAL_MS = 60 * 1000; // evaluate every minute

function getLastActivityTimestamp(agent: Agent): number | null {
	const sources = [agent.last_activity, agent.started_at, agent.created_at];

	for (const source of sources) {
		if (!source) continue;
		const parsed = Date.parse(source);
		if (!Number.isNaN(parsed)) {
			return parsed;
		}
	}

	return null;
}

function getIdleDuration(agent: Agent, now: number): number | null {
	const lastActivity = getLastActivityTimestamp(agent);
	if (!lastActivity) {
		return null;
	}
	return now - lastActivity;
}

function resolveThreshold(agent: Agent): number | null {
	if (agent.status !== "running") {
		return null;
	}

	if (agent.role === "executor") {
		return EXECUTOR_THRESHOLD_MS;
	}

	if (agent.role === "validator") {
		return VALIDATOR_THRESHOLD_MS;
	}

	return null;
}

function formatMinutes(ms: number): string {
	const minutes = Math.floor(ms / 60000);
	const seconds = Math.floor((ms % 60000) / 1000);
	return `${minutes}m ${seconds.toString().padStart(2, "0")}s`;
}

export class StuckMonitor {
	private intervalId: NodeJS.Timeout | null = null;

	constructor(private readonly db: OrchestratorDB) {}

	start(): void {
		if (this.intervalId) {
			return;
		}

		this.intervalId = setInterval(() => {
			this.tick().catch((error) => {
				console.error("[stuck-monitor] tick failed:", error);
			});
		}, POLL_INTERVAL_MS);
	}

	stop(): void {
		if (!this.intervalId) {
			return;
		}
		clearInterval(this.intervalId);
		this.intervalId = null;
	}

	private async tick(): Promise<void> {
		const now = Date.now();
		const agents = this.db.getAllAgents();

		for (const agent of agents) {
			const threshold = resolveThreshold(agent);
			if (!threshold) {
				continue;
			}

			const idleDuration = getIdleDuration(agent, now);
			if (!idleDuration || idleDuration < threshold) {
				continue;
			}

			const lastActivity = getLastActivityTimestamp(agent);
			const lastActivityISO = lastActivity
				? new Date(lastActivity).toISOString()
				: null;
			const nowISO = new Date(now).toISOString();

			console.warn(
				`[stuck-monitor] Marking ${agent.id} (${agent.role}) as stuck: ` +
					`idle ${formatMinutes(idleDuration)} (threshold ${formatMinutes(threshold)})`,
			);

			this.db.updateAgent(agent.id, {
				status: "stuck",
				stuck_detected: 1,
				last_activity: lastActivityISO ?? nowISO,
			});

			this.db.addLog({
				agent_id: agent.id,
				timestamp: nowISO,
				event_type: "stuck",
				content: `Agent marked as stuck after ${formatMinutes(
					idleDuration,
				)} of inactivity (threshold ${formatMinutes(threshold)}).`,
			});
		}
	}
}
