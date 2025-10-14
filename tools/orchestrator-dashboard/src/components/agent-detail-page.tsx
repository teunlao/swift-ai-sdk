"use client";

import clsx from "clsx";
import { ChevronDownIcon } from "@radix-ui/react-icons";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { StatusBadge } from "@/components/status-badge";
import { RoleBadge } from "@/components/role-badge";
import { useTicker } from "@/lib/hooks/use-ticker";
import { calculateUptime } from "@/lib/time";
import type {
	AgentDetail,
	AgentDetailPayload,
	AgentSummary,
	LogDTO,
	ValidationSummary,
} from "@/lib/transformers";
import type { AgentRole } from "@/lib/db";

type LogFilter = "all" | "reasoning" | "messages" | "commands" | "errors";

const LOG_FILTERS: { value: LogFilter; label: string }[] = [
	{ value: "all", label: "All" },
	{ value: "reasoning", label: "Reasoning" },
	{ value: "messages", label: "Messages" },
	{ value: "commands", label: "Commands" },
	{ value: "errors", label: "Errors" },
];

type SnapshotPayload = {
	agents: AgentSummary[];
	validations: ValidationSummary[];
	timestamp: number;
};

async function fetchLogs(
	agentId: string,
	filter: LogFilter,
): Promise<LogDTO[]> {
	const params = new URLSearchParams({ filter, limit: "200" });
	const response = await fetch(
		`/api/agents/${encodeURIComponent(agentId)}/logs?${params.toString()}`,
		{ cache: "no-store" },
	);
	if (!response.ok) {
		throw new Error(`Failed to load logs for ${agentId}`);
	}
	const payload = (await response.json()) as { logs: LogDTO[] };
	return payload.logs;
}

async function fetchAgentDetail(agentId: string): Promise<AgentDetailPayload> {
	const response = await fetch(`/api/agents/${encodeURIComponent(agentId)}`, {
		cache: "no-store",
	});
	if (!response.ok) {
		throw new Error(`Failed to load agent ${agentId}`);
	}
	return (await response.json()) as AgentDetailPayload;
}

function formatDate(value: string | null) {
	if (!value) return "–";
	return new Intl.DateTimeFormat(undefined, {
		month: "short",
		day: "numeric",
		hour: "2-digit",
		minute: "2-digit",
		second: "2-digit",
		hour12: false,
	}).format(new Date(value));
}

function StatCard({ label, value }: { label: string; value: string | number }) {
	return (
		<div className="rounded-xl border border-white/5 bg-muted/30 p-4">
			<p className="text-xs uppercase tracking-wide text-neutral-400">
				{label}
			</p>
			<p className="mt-1 text-xl font-semibold text-white">{value}</p>
		</div>
	);
}

function AccordionCard({
	title,
	description,
	children,
	defaultOpen = false,
}: {
	title: string;
	description?: string;
	children: React.ReactNode;
	defaultOpen?: boolean;
}) {
	const [open, setOpen] = useState(defaultOpen);

	return (
		<div className="rounded-xl border border-white/5 bg-muted/30">
			<button
				type="button"
				onClick={() => setOpen((prev) => !prev)}
				className="flex w-full items-center justify-between gap-4 px-5 py-4 text-left transition hover:bg-white/[0.03]"
				aria-expanded={open}
			>
				<div>
					<p className="text-lg font-semibold text-white">{title}</p>
					{description && (
						<p className="mt-1 text-sm text-neutral-400">{description}</p>
					)}
				</div>
				<ChevronDownIcon
					className={clsx(
						"h-5 w-5 text-neutral-400 transition-transform duration-150",
						open && "rotate-180",
					)}
					aria-hidden
				/>
			</button>
			{open ? (
				<div className="border-t border-white/5 px-5 py-4 text-sm text-neutral-200">
					{children}
				</div>
			) : null}
		</div>
	);
}

export function AgentDetailPage({ agentId }: { agentId: string }) {
	const [agent, setAgent] = useState<AgentDetail | null>(null);
	const [currentValidation, setCurrentValidation] =
		useState<ValidationSummary | null>(null);
	const [history, setHistory] = useState<ValidationSummary[]>([]);
	const [logs, setLogs] = useState<LogDTO[]>([]);
	const [logFilter, setLogFilter] = useState<LogFilter>("all");
	const [logError, setLogError] = useState<string | null>(null);
	const [initialLoading, setInitialLoading] = useState(true);
	const [initialError, setInitialError] = useState<string | null>(null);
	const [lastEventsCount, setLastEventsCount] = useState<number | null>(null);
	const logContainerRef = useRef<HTMLDivElement | null>(null);
	const autoScrollRef = useRef(true);
	const now = useTicker(1000);

	const hasPrompt = Boolean(agent?.prompt);
	const hasFlow = Boolean(agent?.flow);
	const uptime = useMemo(() => {
		if (!agent) return null;
		return calculateUptime(agent.startedAt, agent.endedAt, now);
	}, [agent, now]);

	const loadLogs = useCallback(async () => {
		setLogError(null);
		try {
			const next = await fetchLogs(agentId, logFilter);
			setLogs(next);
		} catch (error) {
			setLogError(
				error instanceof Error ? error.message : "Unable to refresh logs.",
			);
		}
	}, [agentId, logFilter]);

	useEffect(() => {
		let cancelled = false;
		setInitialLoading(true);
		setInitialError(null);
		fetchAgentDetail(agentId)
			.then((payload) => {
				if (cancelled) return;
				setAgent(payload.agent);
				setCurrentValidation(payload.validation);
				setHistory(payload.validationHistory);
			})
			.catch((error) => {
				if (cancelled) return;
				console.error(error);
				setInitialError(error instanceof Error ? error.message : String(error));
			})
			.finally(() => {
				if (!cancelled) {
					setInitialLoading(false);
				}
			});
		return () => {
			cancelled = true;
		};
	}, [agentId]);

	useEffect(() => {
		if (!agent) return undefined;
		const source = new EventSource("/api/events");

		const onSnapshot = (event: MessageEvent<string>) => {
			try {
				const payload: SnapshotPayload = JSON.parse(event.data);
				const matchingAgent = payload.agents.find(
					(item) => item.id === agentId,
				);
				if (matchingAgent) {
					setAgent((prev) => {
						if (!prev) {
							return {
								...matchingAgent,
								prompt: null,
								flow: null,
							} as AgentDetail;
						}

						return {
							...prev,
							...matchingAgent,
							prompt: prev.prompt,
							flow: prev.flow,
						};
					});
				}

				const relevantValidations = payload.validations.filter(
					(session) =>
						session.executorId === agentId || session.validatorId === agentId,
				);
				setHistory(relevantValidations);

				if (matchingAgent?.validation?.id) {
					const active =
						relevantValidations.find(
							(session) => session.id === matchingAgent.validation?.id,
						) ?? null;
					setCurrentValidation(active);
				} else {
					setCurrentValidation(null);
				}
			} catch (error) {
				console.error("Failed to process agent snapshot", error);
			}
		};

		source.addEventListener("snapshot", onSnapshot as EventListener);
		source.onerror = (error) => {
			console.error("Agent detail SSE error", error);
		};

		return () => {
			source.removeEventListener("snapshot", onSnapshot as EventListener);
			source.close();
		};
	}, [agent, agentId]);

	const flowJson = useMemo(() => {
		if (!agent?.flow) return null;
		if (agent.flow.parsed) {
			return JSON.stringify(agent.flow.parsed, null, 2);
		}
		try {
			return JSON.stringify(JSON.parse(agent.flow.raw), null, 2);
		} catch (error) {
			return agent.flow.raw;
		}
	}, [agent?.flow]);

	const agentReady = Boolean(agent);

	useEffect(() => {
		if (!agentReady) return;
		setLogs([]);
		loadLogs().catch(() => undefined);
	}, [agentReady, logFilter, loadLogs]);

	const eventsCount = agent?.events ?? null;

	useEffect(() => {
		if (!agentReady) return;
		if (eventsCount === null) return;
		if (lastEventsCount === null) {
			setLastEventsCount(eventsCount);
			return;
		}
		if (eventsCount !== lastEventsCount) {
			setLastEventsCount(eventsCount);
			loadLogs().catch(() => undefined);
		}
	}, [agentReady, eventsCount, lastEventsCount, loadLogs]);

	useEffect(() => {
		const container = logContainerRef.current;
		if (!container) return;
		if (autoScrollRef.current) {
			container.scrollTop = container.scrollHeight;
		}
	}, [logs]);

	useEffect(() => {
		const container = logContainerRef.current;
		if (!container) return;
		const handler = () => {
			const threshold = 40;
			const atBottom =
				container.scrollTop + container.clientHeight >=
				container.scrollHeight - threshold;
			autoScrollRef.current = atBottom;
		};
		container.addEventListener("scroll", handler);
		return () => {
			container.removeEventListener("scroll", handler);
		};
	}, []);

	const validationRows = useMemo(() => {
		if (!agent) return [];
		return history.map((session) => {
			const role: AgentRole | null =
				session.executorId === agent.id
					? "executor"
					: session.validatorId === agent.id
						? "validator"
						: null;
			return {
				id: session.id,
				status: session.status,
				requestedAt: formatDate(session.requestedAt),
				finishedAt: formatDate(session.finishedAt),
				role,
			};
		});
	}, [history, agent]);

	const isLoadingInitial = initialLoading && !agent;

	if (initialError) {
		return (
			<div className="flex flex-col gap-8">
				<Link
					href="/"
					className="text-sm text-neutral-400 transition hover:text-white"
				>
					&larr; Back to dashboard
				</Link>
				<section className="rounded-xl border border-red-500/40 bg-red-500/10 p-6">
					<h1 className="text-lg font-semibold text-white">
						Failed to load agent
					</h1>
					<p className="mt-2 text-sm text-neutral-200">{initialError}</p>
				</section>
			</div>
		);
	}

	if (isLoadingInitial || !agent) {
		return (
			<div className="flex flex-col gap-8">
				<Link
					href="/"
					className="text-sm text-neutral-400 transition hover:text-white"
				>
					&larr; Back to dashboard
				</Link>
				<section className="rounded-xl border border-white/5 bg-muted/30 p-6">
					<p className="text-sm text-neutral-400">Loading agent details…</p>
				</section>
			</div>
		);
	}

	return (
		<div className="flex flex-col gap-8">
			<Link
				href="/"
				className="text-sm text-neutral-400 transition hover:text-white"
			>
				&larr; Back to dashboard
			</Link>

			<header className="flex flex-col gap-4">
				<div className="flex flex-wrap items-center justify-between gap-3">
					<div>
						<h1 className="text-3xl font-semibold text-white">
							Agent {agent.id}
						</h1>
						<p className="flex flex-wrap items-center gap-2 text-sm text-neutral-400">
							<span className="flex items-center gap-2">
								Role:
								<RoleBadge role={agent.role} />
							</span>
							<span>• Created {formatDate(agent.createdAt)}</span>
						</p>
					</div>
					<div className="flex items-center gap-2">
						<StatusBadge status={agent.status} />
						{currentValidation && (
							<StatusBadge status={currentValidation.status} />
						)}
					</div>
				</div>
				<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
					<StatCard label="Uptime" value={uptime ?? "–"} />
					<StatCard label="Events" value={agent.events} />
					<StatCard label="Commands" value={agent.commands} />
					<StatCard label="Patches" value={agent.patches} />
					<StatCard label="Files Created" value={agent.filesCreated} />
				</div>
			</header>

			<section className="grid gap-6 lg:grid-cols-2">
				<div className="rounded-xl border border-white/5 bg-muted/30 p-5">
					<h2 className="text-lg font-semibold text-white">Details</h2>
					<dl className="mt-4 space-y-3 text-sm text-neutral-300">
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Task</dt>

							<dd>{agent.taskId ?? "–"}</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Worktree</dt>
							<dd className="truncate text-right font-mono">
								{agent.worktree ?? "–"}
							</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Shell ID</dt>
							<dd className="font-mono">{agent.shellId}</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Model</dt>
							<dd className="text-neutral-300">
								{agent.model ?? "gpt-5-codex"}
							</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Reasoning</dt>
							<dd className="text-neutral-300">
								{agent.reasoningEffort ?? "medium"}
							</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Started</dt>
							<dd>{formatDate(agent.startedAt)}</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Last activity</dt>
							<dd>{formatDate(agent.lastActivity)}</dd>
						</div>
						<div className="flex justify-between gap-4">
							<dt className="text-neutral-400">Ended</dt>
							<dd>{formatDate(agent.endedAt)}</dd>
						</div>
					</dl>
				</div>
				<div className="rounded-xl border border-white/5 bg-muted/30 p-5">
					<h2 className="text-lg font-semibold text-white">
						Current Validation
					</h2>
					{currentValidation ? (
						<dl className="mt-4 space-y-3 text-sm text-neutral-300">
							<div className="flex justify-between gap-4">
								<dt className="text-neutral-400">Validation</dt>
								<dd>{currentValidation.id}</dd>
							</div>
							<div className="flex justify-between gap-4">
								<dt className="text-neutral-400">Status</dt>
								<dd>
									<StatusBadge status={currentValidation.status} />
								</dd>
							</div>
							<div className="flex justify-between gap-4">
								<dt className="text-neutral-400">Requested</dt>
								<dd>{formatDate(currentValidation.requestedAt)}</dd>
							</div>
							<div className="flex justify-between gap-4">
								<dt className="text-neutral-400">Finished</dt>
								<dd>{formatDate(currentValidation.finishedAt)}</dd>
							</div>
							<div className="flex justify-between gap-4">
								<dt className="text-neutral-400">Report</dt>
								<dd className="truncate text-right font-mono">
									{currentValidation.reportPath ?? "–"}
								</dd>
							</div>
						</dl>
					) : (
						<p className="mt-4 text-sm text-neutral-400">
							No active validation session.
						</p>
					)}
				</div>
			</section>

			{(hasPrompt || hasFlow) && (
				<section
					className={clsx(
						"grid gap-6",
						hasPrompt && hasFlow && "lg:grid-cols-2",
					)}
				>
					{hasPrompt && (
						<AccordionCard title="Initial Prompt">
							<pre className="max-h-64 overflow-auto rounded-md bg-black/30 p-4 text-sm text-neutral-200">
								{agent.prompt}
							</pre>
						</AccordionCard>
					)}
					{hasFlow && agent.flow && (
						<AccordionCard
							title="Automation Flow"
							description="State exported to .orchestrator/flow"
						>
							<div className="space-y-4">
								{agent.flow.parsed ? (
									<>
										<dl className="space-y-3 text-sm text-neutral-300">
											<div className="flex justify-between gap-4">
												<dt className="text-neutral-400">Role</dt>
												<dd className="font-medium text-white">
													{agent.flow.parsed.role}
												</dd>
											</div>
											<div className="flex justify-between gap-4">
												<dt className="text-neutral-400">Status</dt>
												<dd className="font-medium text-white">
													{agent.flow.parsed.status}
												</dd>
											</div>
											<div className="flex justify-between gap-4">
												<dt className="text-neutral-400">Iteration</dt>
												<dd>{agent.flow.parsed.iteration}</dd>
											</div>
											<div className="flex justify-between gap-4">
												<dt className="text-neutral-400">Updated</dt>
												<dd>
													{formatDate(
														agent.flow.parsed.timestamps?.updated_at ?? null,
													)}
												</dd>
											</div>
											<div className="flex justify-between gap-4">
												<dt className="text-neutral-400">Request</dt>
												<dd className="flex flex-col items-end gap-1 text-right">
													<span className="font-mono text-xs text-neutral-300">
														{agent.flow.parsed.request.path ?? "–"}
													</span>
													<span className="text-xs uppercase tracking-wide text-neutral-500">
														{agent.flow.parsed.request.ready ? "Ready" : "Pending"}
													</span>
												</dd>
											</div>
											<div className="flex justify-between gap-4">
												<dt className="text-neutral-400">Report</dt>
												<dd className="flex flex-col items-end gap-1 text-right">
													<span className="font-mono text-xs text-neutral-300">
														{agent.flow.parsed.report.path ?? "–"}
													</span>
													<span className="text-xs uppercase tracking-wide text-neutral-500">
														{agent.flow.parsed.report.result ?? "Pending"}
													</span>
												</dd>
											</div>
											{agent.flow.parsed.summary && (
												<div className="flex justify-between gap-4">
													<dt className="text-neutral-400">Summary</dt>
													<dd className="max-w-xs text-right text-neutral-200">
														{agent.flow.parsed.summary}
													</dd>
												</div>
											)}
										</dl>
										{agent.flow.parsed.blockers.length > 0 && (
											<div className="space-y-2 rounded-lg border border-yellow-500/30 bg-yellow-500/5 p-3 text-sm text-yellow-100">
												<p className="text-xs font-semibold uppercase tracking-wide text-yellow-300">
													Blockers
												</p>
												<ul className="space-y-1">
													{agent.flow.parsed.blockers.map((blocker) => (
														<li
															key={`${blocker.code}-${blocker.detail}`}
															className="flex flex-col gap-1"
														>
															<span className="font-semibold text-yellow-200">
																{blocker.code}
															</span>
															<span className="text-yellow-100">
																{blocker.detail}
															</span>
														</li>
													))}
												</ul>
											</div>
										)}
									</>
								) : (
									<p className="text-sm text-neutral-400">
										Flow file detected, but content could not be parsed. Showing
										raw payload below.
									</p>
								)}
								<div>
									<p className="mb-2 text-xs uppercase tracking-wide text-neutral-500">
										Raw JSON
										{agent.flow.path ? (
											<>
												{" "}
												<span className="font-mono text-[10px] text-neutral-400">
													{agent.flow.path}
												</span>
											</>
										) : null}
									</p>
									<pre className="max-h-64 overflow-auto rounded-md bg-black/30 p-4 text-xs text-neutral-200">
										{flowJson ?? "Flow artifact not found."}
									</pre>
								</div>
							</div>
						</AccordionCard>
					)}
				</section>
			)}

			<section className="rounded-xl border border-white/5 bg-muted/30 p-5">
				<header className="flex flex-wrap items-center justify-between gap-3">
					<div>
						<h2 className="text-lg font-semibold text-white">
							Validation History
						</h2>
						<p className="text-sm text-neutral-400">
							All validation sessions where this agent acted as executor or
							validator.
						</p>
					</div>
				</header>
				<div className="mt-4 overflow-x-auto">
					<table className="min-w-full text-left text-sm text-neutral-300">
						<thead className="text-xs uppercase tracking-wide text-neutral-500">
							<tr>
								<th className="px-4 py-2">Validation</th>
								<th className="px-4 py-2">Role</th>
								<th className="px-4 py-2">Status</th>
								<th className="px-4 py-2">Requested</th>
								<th className="px-4 py-2">Finished</th>
							</tr>
						</thead>
						<tbody>
							{validationRows.map((row) => (
								<tr key={row.id} className="border-t border-white/5">
									<td className="px-4 py-3 font-mono text-xs text-neutral-300">
										{row.id}
									</td>
									<td className="px-4 py-3">
										{row.role ? <RoleBadge role={row.role} /> : "—"}
									</td>
									<td className="px-4 py-3">
										<StatusBadge status={row.status} />
									</td>
									<td className="px-4 py-3 text-neutral-400">
										{row.requestedAt}
									</td>
									<td className="px-4 py-3 text-neutral-400">
										{row.finishedAt}
									</td>
								</tr>
							))}
							{validationRows.length === 0 && (
								<tr>
									<td
										colSpan={5}
										className="px-4 py-6 text-center text-neutral-400"
									>
										No validation sessions recorded for this agent.
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			</section>

			<section className="rounded-xl border border-white/5 bg-muted/30 p-5">
				<header className="flex flex-wrap items-center justify-between gap-3">
					<div>
						<h2 className="text-lg font-semibold text-white">Logs</h2>
						<p className="text-sm text-neutral-400">
							Streaming output and reasoning captured for this agent.
						</p>
					</div>
					<div className="flex flex-wrap items-center gap-2">
						<div className="flex rounded-lg border border-white/5 bg-muted/40 p-1 text-sm text-neutral-300">
							{LOG_FILTERS.map((option) => (
								<button
									key={option.value}
									type="button"
									onClick={() => setLogFilter(option.value)}
									className={
										"rounded-md px-3 py-1 transition-colors " +
										(logFilter === option.value
											? "bg-white/10 text-white"
											: "hover:bg-white/5")
									}
								>
									{option.label}
								</button>
							))}
						</div>
						<button
							type="button"
							onClick={() => loadLogs().catch(() => undefined)}
							className="rounded-md border border-white/10 bg-white/5 px-3 py-1 text-sm text-white hover:bg-white/10 disabled:opacity-50"
							disabled={!agent}
						>
							Refresh
						</button>
					</div>
				</header>
				<div
					ref={logContainerRef}
					className="mt-4 h-96 overflow-y-auto rounded-lg border border-white/5 bg-black/20 p-4"
				>
					{logError && <p className="text-sm text-red-400">{logError}</p>}
					{logs.length === 0 && !logError && (
						<p className="text-sm text-neutral-400">
							No log entries for the selected filter.
						</p>
					)}
					<ul className="space-y-3 text-sm">
						{logs.map((log) => (
							<li
								key={`${log.timestamp}-${log.content.slice(0, 24)}`}
								className="rounded-md border border-white/5 bg-black/30 p-3"
							>
								<div className="mb-2 flex items-center justify-between text-xs text-neutral-500">
									<span className="uppercase tracking-wide text-neutral-400">
										{log.type}
									</span>
									<span>{formatDate(log.timestamp)}</span>
								</div>
								<pre className="whitespace-pre-wrap text-neutral-200">
									{log.content}
								</pre>
							</li>
						))}
					</ul>
				</div>
			</section>
		</div>
	);
}
