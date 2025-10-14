"use client";

import Link from "next/link";
import { useMemo, useState } from "react";

import { StatusBadge } from "@/components/status-badge";
import { useDashboard } from "@/lib/hooks/dashboard-context";
import type { AgentSummary } from "@/lib/transformers";

function formatDate(value: string | null) {
	if (!value) return "–";
	return new Intl.DateTimeFormat(undefined, {
		month: "short",
		day: "numeric",
		hour: "2-digit",
		minute: "2-digit",
		hour12: false,
	}).format(new Date(value));
}

function AgentRow({ agent }: { agent: AgentSummary }) {
	return (
		<tr className="border-b border-white/5">
			<td className="py-2 text-sm text-neutral-400">
				<Link
					href={`/agents/${encodeURIComponent(agent.id)}`}
					className="font-medium text-white hover:underline"
				>
					{agent.id}
				</Link>
			</td>
			<td className="py-2 text-sm">
				<StatusBadge status={agent.status} />
			</td>
			<td className="py-2 text-sm text-neutral-300">{agent.role}</td>
			<td className="py-2 text-sm text-neutral-300">{agent.taskId ?? "–"}</td>
			<td className="py-2 text-sm text-neutral-400">{agent.worktree ?? "–"}</td>
			<td className="py-2 text-sm text-neutral-300">{agent.events}</td>
			<td className="py-2 text-sm text-neutral-300">
				{agent.model ?? "gpt-5-codex"}
			</td>
			<td className="py-2 text-sm text-neutral-300">
				{agent.reasoningEffort ?? "medium"}
			</td>
			<td className="py-2 text-sm text-neutral-400">
				{formatDate(agent.lastActivity)}
			</td>
			<td className="py-2 text-sm text-neutral-300">
				{agent.validation ? (
					<StatusBadge status={agent.validation.status} />
				) : (
					"–"
				)}
			</td>
		</tr>
	);
}

const STATUS_FILTERS = [
	{ label: "All", value: "all" },
	{ label: "Running", value: "running" },
	{ label: "Needs Fix", value: "needs_fix" },
	{ label: "Validated", value: "validated" },
];

export function AgentsPanel() {
	const { agents, loading, refresh } = useDashboard();
	const [status, setStatus] = useState<string>("all");

	const filtered = useMemo(() => {
		if (status === "all") return agents;
		return agents.filter((agent) => agent.status === status);
	}, [agents, status]);

	return (
		<section className="flex flex-col gap-4">
			<header className="flex flex-wrap items-center justify-between gap-3">
				<div>
					<h2 className="text-lg font-semibold text-white">Agents</h2>
					<p className="text-sm text-neutral-400">
						Track executors and validators, their status, and validation
						progress.
					</p>
				</div>
				<div className="flex items-center gap-3">
					<div className="flex rounded-lg border border-white/5 bg-muted/40 p-1 text-sm text-neutral-300">
						{STATUS_FILTERS.map((item) => (
							<button
								key={item.value}
								type="button"
								onClick={() => setStatus(item.value)}
								className={
									"rounded-md px-3 py-1 transition-colors " +
									(status === item.value
										? "bg-white/10 text-white"
										: "hover:bg-white/5")
								}
							>
								{item.label}
							</button>
						))}
					</div>
					<button
						type="button"
						onClick={() => refresh().catch(() => undefined)}
						className="rounded-md border border-white/10 bg-white/5 px-3 py-1 text-sm text-white hover:bg-white/10"
						disabled={loading}
					>
						Refresh
					</button>
				</div>
			</header>

			<div className="overflow-x-auto rounded-xl border border-white/5 bg-muted/30">
				<table className="min-w-full text-left">
					<thead>
						<tr className="border-b border-white/10 text-xs uppercase tracking-wide text-neutral-500">
							<th className="px-4 py-2">Agent</th>
							<th className="px-4 py-2">Status</th>
							<th className="px-4 py-2">Role</th>
							<th className="px-4 py-2">Task</th>
							<th className="px-4 py-2">Worktree</th>
							<th className="px-4 py-2">Events</th>
							<th className="px-4 py-2">Model</th>
							<th className="px-4 py-2">Reasoning</th>
							<th className="px-4 py-2">Last activity</th>
							<th className="px-4 py-2">Validation</th>
						</tr>
					</thead>
					<tbody>
						{filtered.map((agent) => (
							<AgentRow key={agent.id} agent={agent} />
						))}
						{filtered.length === 0 && (
							<tr>
								<td
									colSpan={8}
									className="px-4 py-6 text-center text-sm text-neutral-400"
								>
									{loading
										? "Loading agents..."
										: "No agents match the selected filter."}
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</section>
	);
}
