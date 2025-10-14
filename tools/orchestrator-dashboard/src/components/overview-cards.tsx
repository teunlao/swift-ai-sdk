"use client";

import { StatusBadge } from "@/components/status-badge";
import { useDashboard } from "@/lib/hooks/dashboard-context";

function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US", { notation: "compact" }).format(value);
}

function formatRelative(timestamp: number | null) {
  if (!timestamp) return "–";
  const formatter = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
  const delta = Date.now() - timestamp;
  const minutes = Math.round(delta / 60000);
  if (Math.abs(minutes) < 1) return "just now";
  return formatter.format(-minutes, "minute");
}

export function OverviewCards() {
  const { agents, validations, lastUpdated } = useDashboard();

  const running = agents.filter((agent) => agent.status === "running").length;
  const needsFix = agents.filter((agent) => agent.status === "needs_fix").length;
  const pendingValidations = validations.filter((session) => session.status === "pending").length;

  const cards = [
    {
      title: "Active agents",
      value: formatNumber(running),
      badge: <StatusBadge status="running" />,
      hint: `${running} agent${running === 1 ? "" : "s"} currently executing tasks.`,
    },
    {
      title: "Needs fix",
      value: formatNumber(needsFix),
      badge: needsFix > 0 ? <StatusBadge status="needs_fix" /> : null,
      hint:
        needsFix > 0
          ? "Review rejected validations and schedule rework."
          : "All executors are clear to continue.",
    },
    {
      title: "Pending validations",
      value: formatNumber(pendingValidations),
      badge: pendingValidations > 0 ? <StatusBadge status="pending" /> : null,
      hint:
        pendingValidations > 0
          ? "Assign validators to unblock delivery."
          : "No validations waiting for review.",
    },
  ];

  return (
    <section className="grid gap-4 md:grid-cols-3">
      {cards.map((card) => (
        <div
          key={card.title}
          className="flex flex-col gap-3 rounded-xl border border-white/5 bg-muted/50 p-5"
        >
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-medium text-neutral-300">{card.title}</h3>
            {card.badge}
          </div>
          <div className="text-3xl font-semibold text-white">{card.value}</div>
          <p className="text-sm text-neutral-400">{card.hint}</p>
        </div>
      ))}
      <div className="flex flex-col gap-2 rounded-xl border border-white/5 bg-muted/50 p-5">
        <h3 className="text-sm font-medium text-neutral-300">Last update</h3>
        <div className="text-lg text-neutral-200">{formatRelative(lastUpdated)}</div>
        <p className="text-xs text-neutral-500">
          Data refreshes automatically every few seconds.
        </p>
      </div>
    </section>
  );
}
