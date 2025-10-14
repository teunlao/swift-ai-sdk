"use client";

import clsx from "clsx";
import type { AgentStatus, ValidationStatus } from "@/lib/db";

type Status = AgentStatus | ValidationStatus;

const STATUS_MAP: Record<Status, { label: string; className: string }> = {
  running: { label: "Running", className: "bg-blue-500/10 text-blue-300 border-blue-500/30" },
  stuck: { label: "Stuck", className: "bg-orange-500/10 text-orange-300 border-orange-500/30" },
  completed: { label: "Completed", className: "bg-neutral-500/10 text-neutral-300 border-neutral-500/30" },
  killed: { label: "Killed", className: "bg-red-500/10 text-red-300 border-red-500/30" },
  validated: { label: "Validated", className: "bg-emerald-500/10 text-emerald-300 border-emerald-500/30" },
  merged: { label: "Merged", className: "bg-emerald-500/10 text-emerald-300 border-emerald-500/30" },
  needs_fix: { label: "Needs Fix", className: "bg-yellow-400/10 text-yellow-300 border-yellow-400/30" },
  needs_input: { label: "Needs Input", className: "bg-amber-400/10 text-amber-200 border-amber-500/30" },
  blocked: { label: "Blocked", className: "bg-fuchsia-500/10 text-fuchsia-300 border-fuchsia-500/30" },
  pending: { label: "Pending", className: "bg-neutral-500/10 text-neutral-200 border-neutral-500/30" },
  in_progress: { label: "In Progress", className: "bg-blue-500/10 text-blue-300 border-blue-500/30" },
  approved: { label: "Approved", className: "bg-emerald-500/10 text-emerald-300 border-emerald-500/30" },
  rejected: { label: "Rejected", className: "bg-red-500/10 text-red-300 border-red-500/30" },
};

export function StatusBadge({ status }: { status: Status }) {
  const meta = STATUS_MAP[status];
  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1 rounded-full border px-2 py-1 text-xs font-medium",
        meta?.className ?? "bg-neutral-500/10 text-neutral-200 border-neutral-600/30"
      )}
    >
      {meta?.label ?? status}
    </span>
  );
}
