"use client";

import { useState } from "react";

type TabItem = {
  id: string;
  label: string;
  content: React.ReactNode;
};

export function TabSwitcher({ tabs }: { tabs: TabItem[] }) {
  const [active, setActive] = useState(tabs[0]?.id ?? "");

  return (
    <div className="flex flex-col gap-6">
      <nav className="flex flex-wrap gap-2">
        {tabs.map((tab) => {
          const isActive = tab.id === active;
          return (
            <button
              key={tab.id}
              onClick={() => setActive(tab.id)}
              className={
                "rounded-lg border px-4 py-2 text-sm font-medium transition-colors " +
                (isActive
                  ? "border-primary/50 bg-primary/10 text-white"
                  : "border-white/10 bg-muted/60 text-neutral-300 hover:border-primary/40 hover:text-white")
              }
            >
              {tab.label}
            </button>
          );
        })}
      </nav>
      <div className="space-y-6">
        {tabs.map((tab) => (
          <div key={tab.id} className={tab.id === active ? "block" : "hidden"}>
            {tab.content}
          </div>
        ))}
      </div>
    </div>
  );
}
