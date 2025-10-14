"use client";

import type { ChangeEvent } from "react";
import { useEffect, useMemo, useState } from "react";

import { useDashboard } from "@/lib/hooks/dashboard-context";
import type { LogDTO } from "@/lib/transformers";

type LogFilter = "all" | "reasoning" | "messages" | "commands" | "errors";

const FILTER_OPTIONS: { value: LogFilter; label: string }[] = [
	{ value: "all", label: "All" },
	{ value: "reasoning", label: "Reasoning" },
	{ value: "messages", label: "Messages" },
	{ value: "commands", label: "Commands" },
	{ value: "errors", label: "Errors" },
];

async function fetchLogs(
	agentId: string,
	filter: LogFilter,
): Promise<LogDTO[]> {
	const params = new URLSearchParams({ filter, limit: "200" });
	const res = await fetch(`/api/agents/${agentId}/logs?${params.toString()}`, {
		cache: "no-store",
	});
	if (!res.ok) {
		throw new Error(`Failed to load logs for agent ${agentId}`);
	}
	const data = (await res.json()) as { logs: LogDTO[] };
	return data.logs;
}

function formatTimestamp(value: string) {
	return new Intl.DateTimeFormat("en", {
		month: "short",
		day: "numeric",
		hour: "2-digit",
		minute: "2-digit",
		second: "2-digit",
	}).format(new Date(value));
}

export function LogsPanel() {
	const { agents } = useDashboard();
	const [selectedAgent, setSelectedAgent] = useState<string | undefined>(
		() => agents[0]?.id,
	);
	const [filter, setFilter] = useState<LogFilter>("all");
	const [logs, setLogs] = useState<LogDTO[]>([]);
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState<string | null>(null);

	const agentOptions = useMemo(
		() =>
			agents.map((agent) => ({
				id: agent.id,
				label: `${agent.id} (${agent.status})`,
			})),
		[agents],
	);

	useEffect(() => {
		const firstAgent = agents[0];
		if (!selectedAgent && firstAgent) {
			setSelectedAgent(firstAgent.id);
		}
	}, [agents, selectedAgent]);

	useEffect(() => {
		if (!selectedAgent) return;
		setLoading(true);
		setError(null);
		fetchLogs(selectedAgent, filter)
			.then((next) => setLogs(next))
			.catch((err) => {
				console.error(err);
				setError(err instanceof Error ? err.message : String(err));
			})
			.finally(() => setLoading(false));
	}, [selectedAgent, filter]);

	return (
		<section className="flex flex-col gap-4">
			<header className="flex flex-wrap items-center justify-between gap-3">
				<div>
					<h2 className="text-lg font-semibold text-white">Logs</h2>
					<p className="text-sm text-neutral-400">
						Inspect reasoning, commands, and errors for any agent.
					</p>
				</div>
				<div className="flex flex-wrap items-center gap-3">
					<select
						value={selectedAgent ?? ""}
						onChange={(event: ChangeEvent<HTMLSelectElement>) => {
							const value = event.target.value;
							setSelectedAgent(value || undefined);
						}}
						className="rounded-md border border-white/10 bg-muted/60 px-3 py-2 text-sm text-white"
					>
						{agentOptions.map((option) => (
							<option
								key={option.id}
								value={option.id}
								className="bg-gray-900 text-white"
							>
								{option.label}
							</option>
						))}
					</select>
					<div className="flex rounded-lg border border-white/5 bg-muted/40 p-1 text-sm text-neutral-300">
						{FILTER_OPTIONS.map((option) => (
							<button
								type="button"
								key={option.value}
								onClick={() => setFilter(option.value)}
								className={
									"rounded-md px-3 py-1 transition-colors " +
									(filter === option.value
										? "bg-white/10 text-white"
										: "hover:bg-white/5")
								}
							>
								{option.label}
							</button>
						))}
					</div>
				</div>
			</header>

			<div className="h-80 overflow-y-auto rounded-xl border border-white/5 bg-muted/30 p-4">
				{loading && <p className="text-sm text-neutral-400">Loading logs…</p>}
				{error && <p className="text-sm text-red-400">{error}</p>}
				{!loading && logs.length === 0 && !error && (
					<p className="text-sm text-neutral-400">
						No log entries for the current selection.
					</p>
				)}
				<ul className="space-y-3 text-sm">
					{logs.map((log) => (
						<li
							key={`${log.timestamp}-${log.content.slice(0, 32)}`}
							className="rounded-lg border border-white/5 bg-black/20 p-3"
						>
							<div className="mb-2 flex items-center justify-between text-xs text-neutral-500">
								<span className="uppercase tracking-wide text-neutral-400">
									{log.type}
								</span>
								<span>{formatTimestamp(log.timestamp)}</span>
							</div>
							<pre className="whitespace-pre-wrap text-neutral-200">
								{log.content}
							</pre>
						</li>
					))}
				</ul>
			</div>
		</section>
	);
}
