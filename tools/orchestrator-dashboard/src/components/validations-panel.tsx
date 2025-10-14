"use client";

import { useMemo, useState } from "react";

import { StatusBadge } from "@/components/status-badge";
import { useDashboard } from "@/lib/hooks/dashboard-context";

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

const VALIDATION_FILTERS = [
	{ label: "All", value: "all" },
	{ label: "Pending", value: "pending" },
	{ label: "In Progress", value: "in_progress" },
	{ label: "Rejected", value: "rejected" },
	{ label: "Approved", value: "approved" },
];

export function ValidationsPanel() {
	const { validations } = useDashboard();
	const [status, setStatus] = useState<string>("all");

	const filtered = useMemo(() => {
		if (status === "all") return validations;
		return validations.filter((session) => session.status === status);
	}, [validations, status]);

	return (
		<section className="flex flex-col gap-4">
			<header className="flex flex-wrap items-center justify-between gap-3">
				<div>
					<h2 className="text-lg font-semibold text-white">Validations</h2>
					<p className="text-sm text-neutral-400">
						Monitor review queue and track executor/validator pairing.
					</p>
				</div>
				<div className="flex rounded-lg border border-white/5 bg-muted/40 p-1 text-sm text-neutral-300">
					{VALIDATION_FILTERS.map((item) => (
						<button
							type="button"
							key={item.value}
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
			</header>

			<div className="overflow-x-auto rounded-xl border border-white/5 bg-muted/30">
				<table className="min-w-full text-left">
					<thead>
						<tr className="border-b border-white/10 text-xs uppercase tracking-wide text-neutral-500">
							<th className="px-4 py-2">Validation</th>
							<th className="px-4 py-2">Status</th>
							<th className="px-4 py-2">Executor</th>
							<th className="px-4 py-2">Validator</th>
							<th className="px-4 py-2">Task</th>
							<th className="px-4 py-2">Requested</th>
							<th className="px-4 py-2">Updated</th>
						</tr>
					</thead>
					<tbody>
						{filtered.map((session) => (
							<tr key={session.id} className="border-b border-white/5">
								<td className="py-2 text-sm text-neutral-400">{session.id}</td>
								<td className="py-2 text-sm">
									<StatusBadge status={session.status} />
								</td>
								<td className="py-2 text-sm text-neutral-300">
									{session.executorId}
								</td>
								<td className="py-2 text-sm text-neutral-300">
									{session.validatorId ?? "–"}
								</td>
								<td className="py-2 text-sm text-neutral-300">
									{session.taskId ?? "–"}
								</td>
								<td className="py-2 text-sm text-neutral-400">
									{formatDate(session.requestedAt)}
								</td>
								<td className="py-2 text-sm text-neutral-400">
									{formatDate(session.finishedAt ?? session.startedAt)}
								</td>
							</tr>
						))}
						{filtered.length === 0 && (
							<tr>
								<td
									colSpan={7}
									className="px-4 py-6 text-center text-sm text-neutral-400"
								>
									No validations match the selected filter.
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</section>
	);
}
