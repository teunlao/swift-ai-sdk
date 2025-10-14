"use client";

import clsx from "clsx";
import type { AgentRole } from "@/lib/db";

const ROLE_MAP: Record<AgentRole, { label: string; className: string }> = {
	executor: {
		label: "Executor",
		className: "bg-blue-500/10 text-blue-300 border-blue-500/30",
	},
	validator: {
		label: "Validator",
		className: "bg-emerald-500/10 text-emerald-300 border-emerald-500/30",
	},
};

export function RoleBadge({ role }: { role: AgentRole }) {
	const meta = ROLE_MAP[role];
	return (
		<span
			className={clsx(
				"inline-flex items-center gap-1 rounded-full border px-2 py-1 text-xs font-medium capitalize",
				meta?.className ?? "bg-neutral-500/10 text-neutral-200 border-neutral-600/30",
			)}
		>
			{meta?.label ?? role}
		</span>
	);
}
