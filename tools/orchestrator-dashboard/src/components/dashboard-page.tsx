"use client";

import { DashboardProvider, useDashboard } from "@/lib/hooks/dashboard-context";
import { OverviewCards } from "@/components/overview-cards";
import { AgentsPanel } from "@/components/agents-panel";
import { ValidationsPanel } from "@/components/validations-panel";
import { LogsPanel } from "@/components/logs-panel";
import { TabSwitcher } from "@/components/tab-switcher";

function DashboardHeader() {
  const { agents } = useDashboard();
  const totalExecutors = agents.filter((agent) => agent.role === "executor").length;
  const totalValidators = agents.filter((agent) => agent.role === "validator").length;

  return (
    <header className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-3xl font-semibold text-white">Orchestrator Dashboard</h1>
          <p className="text-sm text-neutral-400">
            Live view of Codex executors, validators, validation queue, and agent logs.
          </p>
        </div>
        <div className="flex gap-2 text-sm text-neutral-300">
          <span className="rounded-md border border-white/10 bg-white/5 px-3 py-1">
            Executors: {totalExecutors}
          </span>
          <span className="rounded-md border border-white/10 bg-white/5 px-3 py-1">
            Validators: {totalValidators}
          </span>
        </div>
      </div>
      <OverviewCards />
    </header>
  );
}

function DashboardContent() {
  return (
    <div className="flex flex-col gap-8">
      <DashboardHeader />
      <TabSwitcher
        tabs={[
          {
            id: "agents",
            label: "Agents",
            content: <AgentsPanel />,
          },
          {
            id: "validations",
            label: "Validations",
            content: <ValidationsPanel />,
          },
          {
            id: "logs",
            label: "Logs",
            content: <LogsPanel />,
          },
        ]}
      />
    </div>
  );
}

export function DashboardPage() {
  return (
    <DashboardProvider>
      <DashboardContent />
    </DashboardProvider>
  );
}
