import { DashboardPage } from "@/components/dashboard-page";

export const runtime = "nodejs";

export default function Page() {
  return (
    <main className="mx-auto flex min-h-screen max-w-6xl flex-col gap-10 px-6 py-12">
      <DashboardPage />
    </main>
  );
}
