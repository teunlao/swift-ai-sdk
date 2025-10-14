## Orchestrator Dashboard UI — Task Breakdown

- [ ] **Overall Goal:** Build real-time web dashboard for orchestrator agents (Next.js + SSE).

### Phase 0 · Foundations
- [x] Convert repo to pnpm workspace and share lockfile.
- [x] Extract reusable DB package (`@orchestrator/db`) with event emitter hooks.
- [ ] Update docs with UI/SSE plan.

### Phase 1 · Shared Services
- [x] Implement realtime data stream (SSE polling of agents/validations snapshot).
- [x] Expose SSE helper in dashboard API (`/api/events`).

### Phase 2 · Dashboard Backend (Next.js)
- [x] Scaffold Next.js app in `tools/orchestrator-dashboard` with workspace alias.
- [x] API routes: `/api/agents`, `/api/agents/[id]`, `/api/agents/[id]/logs`, `/api/validations`.
- [ ] POST action routes: request/assign/submit validation (bridge to MCP).
- [x] SSE endpoint `/api/events` streaming realtime updates.
- [x] Configuration loader + CLI entry (`npx orchestrator-dashboard`).

### Phase 3 · Dashboard UI
- [x] Global layout with navigation and status header.
- [x] Agents tab (filters, metrics, live updates).
- [ ] Agent detail view
  - [x] Overview, validation history, per-agent logs
  - [ ] Worktree browser, validation actions
- [x] Validation tab with queue overview.
- [x] Logs tab with per-agent stream.
- [ ] Settings panel (DB path, SSE status, auth toggles).

### Phase 4 · Tooling & Distribution
- [x] Root scripts (`pnpm dashboard`) and CLI shim.
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
