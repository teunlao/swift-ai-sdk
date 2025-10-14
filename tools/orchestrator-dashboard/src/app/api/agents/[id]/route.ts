import { NextResponse } from "next/server";
import { getDb } from "@/lib/db";
import {
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

	return NextResponse.json({
		agent: {
			...summary,
			prompt: agent.prompt ?? null,
		},
		validation: currentValidation
			? toValidationSummary(currentValidation)
			: null,
		validationHistory,
		logs,
	});
}
