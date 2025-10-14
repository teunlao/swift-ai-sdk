import { notFound } from "next/navigation";
import { AgentDetailPage as AgentDetailPageContent } from "@/components/agent-detail-page";
import { getDb } from "@/lib/db";
import {
	type AgentDetailPayload,
	toAgentSummary,
	toLogDto,
	toValidationSummary,
} from "@/lib/transformers";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type PageProps = {
	params: Promise<{
		id: string;
	}>;
};

export default async function AgentDetailPage({ params }: PageProps) {
	const db = getDb();
	const { id } = await params;
	const agentId = decodeURIComponent(id);
	const agent = db.getAgent(agentId);

	if (!agent) {
		notFound();
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

	const payload: AgentDetailPayload = {
		agent: {
			...summary,
			prompt: agent.prompt ?? null,
		},
		validation: currentValidation
			? toValidationSummary(currentValidation)
			: null,
		validationHistory,
		logs,
	};

	return (
		<main className="mx-auto flex min-h-screen max-w-5xl flex-col gap-8 px-6 py-12">
			<AgentDetailPageContent initialData={payload} />
		</main>
	);
}
