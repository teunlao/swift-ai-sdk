import { ArrowRightIcon } from "@radix-ui/react-icons";

const quickLinks = [
  {
    title: "Agents",
    description: "Overview of all executors and validators with live status.",
    href: "/agents",
  },
  {
    title: "Validations",
    description: "Track pending reviews, verdicts, and rework requirements.",
    href: "/validations",
  },
  {
    title: "Logs",
    description: "Stream reasoning, commands, and errors from active agents.",
    href: "/logs",
  },
];

export default function LandingPage() {
  return (
    <main className="mx-auto flex min-h-screen max-w-5xl flex-col gap-10 px-6 py-16">
      <section className="flex flex-col gap-6">
        <span className="inline-flex w-fit items-center rounded-full bg-muted px-3 py-1 text-sm text-neutral-400">
          Orchestrator Monitor
        </span>
        <h1 className="text-4xl font-semibold text-white sm:text-5xl">
          Real-time visibility for every Codex agent
        </h1>
        <p className="max-w-2xl text-lg text-neutral-400">
          Inspect executors, validators, validation sessions, and logs without
          leaving the browser. The dashboard connects directly to the
          orchestrator database and stays in sync via live updates.
        </p>
      </section>

      <section className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {quickLinks.map((link) => (
          <a
            key={link.title}
            href={link.href}
            className="group flex flex-col gap-3 rounded-xl border border-white/5 bg-muted/60 p-6 transition-colors hover:border-primary/60"
          >
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-semibold text-white">{link.title}</h2>
              <ArrowRightIcon className="h-5 w-5 text-neutral-500 transition-transform group-hover:translate-x-0.5 group-hover:text-primary" />
            </div>
            <p className="text-sm text-neutral-400">{link.description}</p>
          </a>
        ))}
      </section>

      <section className="rounded-xl border border-white/5 bg-muted/50 p-6">
        <h3 className="text-lg font-semibold text-white">Next steps</h3>
        <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm text-neutral-400">
          <li>Expose API routes for agents, validations, and logs.</li>
          <li>Stream events over SSE for real-time updates.</li>
          <li>Design detail views with filters, search, and log playback.</li>
        </ol>
      </section>
    </main>
  );
}
