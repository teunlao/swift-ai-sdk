import * as fs from "node:fs";
import * as path from "node:path";
import { NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import {
  type AgentFlow,
  type FlowState,
  toAgentSummary,
  toLogDto,
  toValidationSummary,
} from "@/lib/transformers";

export const runtime = "nodejs";

export async function GET(
	_request: Request,
	context: { params: Promise<{ id: string }> },
) {
	const db = getDb();
	const { id } = await context.params;
	const agentId = decodeURIComponent(id);
	const agent = db.getAgent(agentId);

	if (!agent) {
		return NextResponse.json(
			{ error: `Agent ${agentId} not found` },
			{ status: 404 },
		);
	}

	const currentValidation = agent.current_validation_id
		? db.getValidationSession(agent.current_validation_id)
		: undefined;

	const validationHistory = db
		.listValidationSessions()
		.filter(
			(session) =>
				session.executor_id === agent.id || session.validator_id === agent.id,
		)
		.map(toValidationSummary);

	const summary = toAgentSummary(agent, currentValidation ?? null);
	const logs = db.getLogs(agent.id, "all", 200).map(toLogDto).reverse();
	const flow = readAgentFlow(agent.worktree, agent.id);

	return NextResponse.json({
		agent: {
			...summary,
			prompt: agent.prompt ?? null,
			flow,
		},
		validation: currentValidation
			? toValidationSummary(currentValidation)
			: null,
		validationHistory,
		logs,
	});
}

function readAgentFlow(
	worktree: string | null,
	agentId: string,
): AgentFlow | null {
	if (!worktree) {
		return null;
	}

	const flowPath = path.join(
		worktree,
		".orchestrator",
		"flow",
		`${agentId}.json`,
	);

	if (!fs.existsSync(flowPath)) {
		return null;
	}

	try {
		const raw = fs.readFileSync(flowPath, "utf-8");
		let parsed: FlowState | null = null;
		try {
			parsed = JSON.parse(raw) as FlowState;
		} catch (error) {
			console.warn(
				`[dashboard] Failed to parse flow JSON for ${agentId} at ${flowPath}:`,
				error,
			);
		}

		return {
			raw,
			parsed,
			path: flowPath,
		};
	} catch (error) {
		console.warn(
			`[dashboard] Unable to read flow JSON for ${agentId} at ${flowPath}:`,
			error,
		);
		return null;
	}
}
