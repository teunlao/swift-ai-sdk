## Orchestrator Dashboard UI — Task Breakdown

- [ ] **Overall Goal:** Build real-time web dashboard for orchestrator agents (Next.js + SSE).

### Phase 0 · Foundations
- [x] Convert repo to pnpm workspace and share lockfile.
- [x] Extract reusable DB package (`@orchestrator/db`) with event emitter hooks.
- [ ] Update docs with UI/SSE plan.

### Phase 1 · Shared Services
- [ ] Implement realtime bus (publish on agent/validation/log updates).
- [ ] Expose SSE helper in MCP layer and smoke-test.

### Phase 2 · Dashboard Backend (Next.js)
- [ ] Scaffold Next.js app in `tools/orchestrator-dashboard` with workspace alias.
- [ ] API routes: `/api/agents`, `/api/agents/[id]`, `/api/agents/[id]/logs`, `/api/validations`.
- [ ] POST action routes: request/assign/submit validation (bridge to MCP).
- [ ] SSE endpoint `/api/events` streaming realtime updates.
- [ ] Configuration loader + CLI entry (`npx orchestrator-dashboard`).

### Phase 3 · Dashboard UI
- [ ] Global layout with navigation + status bar.
- [ ] Agents overview page (filters, sorting, live metrics).
- [ ] Agent detail view (overview, live logs, worktree browser, validation info).
- [ ] Validation center page with actions.
- [ ] Settings panel (DB path, SSE status, auth toggles).

### Phase 4 · Tooling & Distribution
- [ ] Root scripts (`npm run dashboard`, build/start equivalents).
- [ ] Package & publish CLI shim for `npx orchestrator-dashboard`.
- [ ] Update orchestrator README with dashboard section.

### Phase 5 · Quality & Docs
- [ ] Add unit/integration/e2e tests (RTL/Playwright) for dashboard.
- [ ] CI jobs for lint/test/e2e dashboard package.
- [ ] Create `docs/orchestrator-dashboard.md` with setup and feature tour.
- [ ] Capture screenshots / GIF for documentation.

### Phase 6 · Rollout
- [ ] Internal alpha (team feedback, perf checks).
- [ ] Beta release (publish package, announce usage).
- [ ] GA sign-off and changelog entry.

### Optional Research
- [ ] Explore reusable executor flow (carry-over context between tasks without closing session).
