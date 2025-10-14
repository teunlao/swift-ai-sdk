"use client";

import React from "react";
import type { AgentSummary, ValidationSummary } from "@/lib/transformers";

type DashboardState = {
	agents: AgentSummary[];
	validations: ValidationSummary[];
	loading: boolean;
	lastUpdated: number | null;
	refresh: () => Promise<void>;
};

const DashboardContext = React.createContext<DashboardState | undefined>(
	undefined,
);

async function fetchJson<T>(url: string): Promise<T> {
	const res = await fetch(url, { cache: "no-store" });
	if (!res.ok) {
		throw new Error(`Request failed: ${res.status} ${res.statusText}`);
	}
	return (await res.json()) as T;
}

type SnapshotPayload = {
	agents: AgentSummary[];
	validations: ValidationSummary[];
	timestamp: number;
};

export function DashboardProvider({ children }: { children: React.ReactNode }) {
	const [state, setState] = React.useState<DashboardState>({
		agents: [],
		validations: [],
		loading: true,
		lastUpdated: null,
		refresh: async () => undefined,
	});

	const refresh = React.useCallback(async () => {
		const [agentsResp, validationsResp] = await Promise.all([
			fetchJson<{ agents: AgentSummary[] }>("/api/agents"),
			fetchJson<{ validations: ValidationSummary[] }>("/api/validations"),
		]);

		setState((prev) => ({
			...prev,
			agents: agentsResp.agents,
			validations: validationsResp.validations,
			loading: false,
			lastUpdated: Date.now(),
		}));
	}, []);

	React.useEffect(() => {
		setState((prev) => ({ ...prev, refresh }));
		refresh().catch((error) => {
			console.error("Failed to load dashboard data", error);
			setState((prev) => ({ ...prev, loading: false }));
		});
	}, [refresh]);

	React.useEffect(() => {
		const source = new EventSource("/api/events");

		const onSnapshot = (event: MessageEvent<string>) => {
			try {
				const payload: SnapshotPayload = JSON.parse(event.data);
				setState((prev) => ({
					...prev,
					agents: payload.agents,
					validations: payload.validations,
					loading: false,
					lastUpdated: payload.timestamp,
				}));
			} catch (error) {
				console.error("Failed to parse dashboard snapshot", error);
			}
		};

		source.addEventListener("snapshot", onSnapshot as EventListener);

		source.onerror = (error) => {
			console.error("Dashboard events error", error);
		};

		return () => {
			source.removeEventListener("snapshot", onSnapshot as EventListener);
			source.close();
		};
	}, []);

	return (
		<DashboardContext.Provider value={state}>
			{children}
		</DashboardContext.Provider>
	);
}

export function useDashboard() {
	const ctx = React.useContext(DashboardContext);
	if (!ctx) {
		throw new Error("useDashboard must be used inside DashboardProvider");
	}
	return ctx;
}
