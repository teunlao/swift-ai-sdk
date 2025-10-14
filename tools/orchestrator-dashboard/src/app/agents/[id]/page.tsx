import { AgentDetailPage as AgentDetailPageContent } from "@/components/agent-detail-page";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type PageProps = {
	params: Promise<{
		id: string;
	}>;
};

export default async function AgentDetailPage({ params }: PageProps) {
	const { id } = await params;
	const agentId = decodeURIComponent(id);
	return (
		<main className="mx-auto flex min-h-screen max-w-5xl flex-col gap-8 px-6 py-12">
			<AgentDetailPageContent agentId={agentId} />
		</main>
	);
}
