import { DashboardPage } from "@/components/dashboard-page";

export const runtime = "nodejs";

export default function Page() {
	return (
		<main className="mx-auto flex h-screen max-w-8xl flex-col gap-10 overflow-y-auto px-6 py-12">
			<DashboardPage />
		</main>
	);
}
