# ⚠️ Ответы пользователю всегда на русском языке.

<!-- Please write all AGENTS.md updates in English. -->
# Swift AI SDK - Agent Guide

## Project Mission

Port **Vercel AI SDK** from TypeScript to Swift with **100% upstream parity**.

**Goal**: 1:1 feature-complete implementation matching TypeScript API, behavior, types, and tests.

## Documentation Porting Workflow (Starlight site in `apps/docs`)

1. **Source of truth** — every page originates from the upstream Markdown/MDX under `external/vercel-ai-sdk/content/**`. Copy a single file at a time; never author pages from scratch.
2. **Placement** — paste the copied file into `apps/docs/src/content/docs/...`, matching the upstream path semantics. Keep the original frontmatter (title/description/slug).
3. **Initial build fix‑ups** — remove or replace upstream‑specific React components (`<PreviewSwitchProviders/>`, bespoke imports, etc.) with Starlight/MDX constructs (e.g., `Tabs`, blockquotes). The page must compile with `pnpm run docs:check` and `pnpm run docs:build` before moving on.
4. **Swift adaptation** — translate code samples and narrative details to Swift parity while preserving ~80% of the original text flow. Replace TypeScript examples with Swift snippets using the new provider facades (e.g., `import OpenAIProvider` + `openai("gpt-5")`). Document any Swift-specific differences via short notes or callouts when necessary.
5. **Sidebar wiring** — update `apps/docs/astro.config.mjs` whenever a new page is copied so navigation mirrors the upstream structure.
6. **One page at a time** — complete copy → adapt → build cycle for a single document before starting the next. Store any temporary upstream dumps in `.staging/` if needed; keep `apps/docs/src/content/docs` clean and buildable.
7. **Validation** — run `pnpm run docs:check` and `pnpm run docs:build` after adapting each page. Do not commit documentation changes until both commands are green.

## Code Audit & Parity Verification Workflow

1. **Enumerate and read** — iterate through every upstream `.ts`/`.tsx` source (excluding tests) under the target package, and immediately inspect the matching Swift implementation. No summaries or mappings; check and understand the real code.
2. **Logic parity** — confirm all branches, loops, error paths, and side effects mirror upstream behavior. If Swift uses different idioms, ensure observable output stays identical and note the rationale in code comments if necessary.
3. **Schema & types** — verify request/response schemas, option objects, enums, defaults, and metadata fields (usage, tool calls, annotations, logprobs, etc.) match upstream semantics.
4. **Utilities & config** — validate helper modules (error mappers, config loaders, version constants, tool registries) align with TypeScript originals.
5. **Tests** — ensure each upstream test scenario is represented in Swift tests (or add coverage). Re-run relevant tests after changes.
6. **Immediate fixes** — upon finding any discrepancy, fix the Swift code (or document an intentional deviation) before proceeding. Never defer unresolved differences.
7. **Final validation** — run `swift test` (and any package-specific checks) plus parity smoke tests if applicable to confirm runtime behavior.

---

**📚 Read first:**
```bash
plan/executor-guide.md          # Executor workflow
plan/validation-workflow.md     # Validation process
plan/orchestrator-automation.md # Flow files & automation rules
plan/principles.md              # Porting rules
```

---

## Project Structure

```
swift-ai-sdk/
├── .sessions/                   # Session contexts (gitignored)
├── .orchestrator/               # Automation artifacts (gitignored)
├── Package.swift                # SwiftPM manifest (3 targets)
├── Sources/
│   ├── AISDKProvider/          # Foundation (78 files, ~210 tests)
│   ├── AISDKProviderUtils/     # Utilities (35 files, ~200 tests)
│   ├── SwiftAISDK/             # Main SDK (105 files, ~300 tests)
│   └── EventSourceParser/      # SSE parser (2 files, 30 tests)
├── Tests/                       # Swift Testing tests
├── external/                    # ⚠️ UPSTREAM REFERENCE (read-only)
│   ├── vercel-ai-sdk/packages/ # TypeScript source
│   │   ├── provider/           → AISDKProvider
│   │   ├── provider-utils/     → AISDKProviderUtils
│   │   └── ai/                 → SwiftAISDK
│   └── eventsource-parser/     # SSE parser reference
└── plan/                        # Documentation
```

### Package Dependencies
```
AISDKProvider (no dependencies)
    ↑
AISDKProviderUtils (depends on: AISDKProvider)
    ↑
SwiftAISDK (depends on: AISDKProvider, AISDKProviderUtils, EventSourceParser)
```

### Session Contexts

**Usage**: `.sessions/` files preserve state between parallel agent sessions.

- 💬 Capture: `"Зафиксируй контекст текущей работы"`
- 📂 Resume: `"Загрузи контекст из .sessions/session-*.md"`
- 🗑️ Cleanup: Delete after task completion

**Use for**: Multi-session tasks, interrupted work, complex checkpoints
**See**: `.sessions/README.md`

---

## Upstream References

**Vercel AI SDK** (6.0.0-beta.42, commit `77db222ee`):
```
external/vercel-ai-sdk/packages/
├── provider/        → Sources/AISDKProvider/
├── provider-utils/  → Sources/AISDKProviderUtils/
└── ai/              → Sources/SwiftAISDK/
```

**EventSource Parser**: `external/eventsource-parser/` → `Sources/EventSourceParser/`

---

## ⚠️ Git Worktree Usage (IMPORTANT)

- Always switch into the dedicated worktree directory (`cd ../swift-ai-sdk-task-<id>`) **before** editing anything.  
- Keep both repositories clean: the main tree must stay untouched (`git status` clean), and every change should appear only inside the worktree.  
- **Never run `apply_patch` inside a worktree.** It writes directly into the main repository and will leak changes to `main`. Use other editing methods (`python`, `cat > file`, dedicated formatters) instead.
- Temporary scratch files belong only inside the worktree and must be removed before finishing the task.  
- Before starting a new task, sync the worktree to the correct commit (e.g., `b40920d4…`) and re-clone `external/` references—fresh worktrees do not include them automatically.  
- Any stray change in the main repo blocks other agents and violates the “leave others’ work alone” rule—avoid it at all costs.
- Double-check `git status` in both the root repo and your worktree after every set of edits. If `main` is dirty, stop and fix it immediately before continuing.
- Worktree branches are **completely isolated** from `main`; you cannot damage the primary branch from inside a task worktree. Treat it as a sandbox and push through every change without hesitation, even when the implementation is invasive.
- Executors must deliver **100% upstream parity** for their task. Partial ports, temporary shortcuts, or abandoning work midway are never acceptable—finish the job no matter how long it takes or how complex it becomes. Validators will block incomplete work, so finish the port before asking for review.

---

## Parity Standards

### Must Match
- ✅ Public API (names, parameters, types)
- ✅ Behavior (edge cases, errors)
- ✅ Error messages (same text)
- ✅ Test scenarios (all ported)

### Allowed Adaptations
- ✅ `Promise<T>` → `async throws -> T`
- ✅ `AbortSignal` → `@Sendable () -> Bool`
- ✅ Union types → `enum` with associated values
- ✅ `undefined` → `nil`
- ✅ `Record<K, V>` → `[K: V]`

**Document adaptations** with rationale. See `plan/principles.md`.

---

## TypeScript → Swift Patterns

| TypeScript | Swift |
|------------|-------|
| `Promise<T>` | `async throws -> T` |
| `value?: T \| undefined` | `value: T? = nil` |
| `type A \| B` | `enum Result { case a(A), case b(B) }` |
| `Record<K, V>` | `[K: V]` |
| `AbortSignal` | `@Sendable () -> Bool` |

---

## Current Status

**✅ Completed** (763/763 tests passing):
- **AISDKProvider** (78 files, ~210 tests): LanguageModelV2/V3, EmbeddingModel, ImageModel, SpeechModel, TranscriptionModel, Errors, JSONValue
- **AISDKProviderUtils** (35 files, ~200 tests): HTTP/JSON utilities, Schema, Tools, Data handling
- **SwiftAISDK** (105 files, ~300 tests): Prompt conversion, Tool execution, Registry, Middleware, Telemetry
- **EventSourceParser** (2 files, 30 tests)

**🚧 Next**: Block E/F (Generate/Stream Text), Provider implementations

**Stats**: ~14,300 lines, 220 files, 3 packages

---

## Key Commands

```bash
# Find upstream
ls external/vercel-ai-sdk/packages/*/src/

# Build & test
swift build && swift test

# Session contexts
cat .sessions/README.md

# Validation
cat plan/orchestrator-automation.md

# UTC timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

---


**Output Analysis**:
```
🎯 Smart Mode Analysis (3 runs)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Run 1: ⏱️  TIMEOUT after 5000ms
Run 2: ⏱️  TIMEOUT after 5000ms
Run 3: ✅ PASSED (763 tests)

⚠️ Culprits Found: 2 tests/groups causing timeouts
  - SwiftAISDKTests.CreateUIMessageStreamTests/*
  - SwiftAISDKTests.HandleUIMessageStreamFinishTests/*
```

#### Standard Modes

**Exclude mode** (default):
```bash
# Run all tests EXCEPT listed patterns
node tools/test-runner.js --config test-runner.default.config.json
```

**Include mode**:
```bash
# Run ONLY specific tests
node tools/test-runner.js --config test-suspicious.config.json
```

**Options**:
- `--list` — Show all available tests
- `--dry-run` — Preview what will run without executing
- `--cache` — Use cached test list (faster, use only if tests haven't changed)
- `--timeout <ms>` — Timeout per run (default: 15000)
- `--runs <n>` — Number of iterations for smart mode (default: 3)

#### Configuration

Config files in `tools/`:
- `test-runner.default.config.json` — Run all tests (exclude mode)
- See `tools/README.md` for full documentation

**When to Use**:
- 🔍 **After adding async/concurrent code** — Verify no race conditions introduced
- 🐛 **Flaky test debugging** — Use `--smart` to reproduce intermittent failures
- ⏱️ **Timeout investigation** — Smart mode identifies which tests hang
- ✅ **Pre-commit validation** — Quick sanity check with default config

**See**: `tools/README.md` for detailed documentation and examples.

---

## Pre-Completion Checklist

- [ ] Public API matches upstream
- [ ] Behavior matches exactly
- [ ] ALL upstream tests ported
- [ ] All tests pass
- [ ] Upstream reference in file header
- [ ] Adaptations documented
- [ ] `swift build` succeeds
- [ ] `.orchestrator/requests/...` created with summary
- [ ] `.orchestrator/flow/<executor-id>.json` updated (status=ready_for_validation)

---

## Key Principles

1. **🚨 NEVER TOUCH OTHER AGENTS' WORK** — Only edit your task files. Multiple agents work in parallel.
2. **Automation owns the loop** — Executors/validators must maintain `.orchestrator/` artifacts; the watcher handles validation.
3. **Flow JSON is authoritative** — Keep it valid/minified; use `status` (`working`, `ready_for_validation`, `needs_input`, etc.) accurately.
4. **Test everything** — 100% upstream parity and test coverage are mandatory.
5. **Mark done ONLY after validation** — Wait for automation to approve or explicitly document blockers.
6. **Never commit without permission** — Explicit user request required.
7. **Worktree defaults** — Executors on `auto`, validators on `manual` within executor worktree.

### Working in Git Worktrees

- ⚠️ apply_patch is forbidden inside worktrees: it edits files in the main repository and bypasses the task branch. Use shell commands with explicit cd/paths instead.
- Fresh worktrees do **not** include the upstream reference under `external/`. After creating a worktree, recreate the reference with:
  ```bash
  git clone https://github.com/vercel/ai external/vercel-ai-sdk
  cd external/vercel-ai-sdk
  git checkout 77db222ee  # upstream reference commit
  ```
- Keep the worktree on the correct Swift AI SDK commit (`b40920d4876a213194e0d16d9899abbb61ad9cab` as of 2025-10-16). Use `git status` regularly to ensure you stay aligned.
- Avoid editing shared upstream files inside the cloned reference; treat it as read-only.
- When a worktree is no longer needed, remove it with Git to keep metadata clean: `git worktree remove <path>` (do not `rm -rf` manually).
- As soon as you switch into a task-specific worktree branch, immediately update the corresponding Taskmaster task status to `in-progress`.

---

## Documentation Files

### Core
- `README.md` — Project overview
- `AGENTS.md` — This file
- `Package.swift` — SwiftPM manifest

### Plan Directory
- `principles.md` — Porting guidelines
- `executor-guide.md` — Executor workflow
- `validation-workflow.md` — Validation process
- `validator-guide.md` — Manual checklist
- `design-decisions.md` — Documented deviations
- `tests.md` — Testing approach

### Validation Automation
- `plan/orchestrator-automation.md` — Flow schema & naming
- `plan/validation-workflow.md` — Automation + fallback process
- `.claude/agents/validator.md` — Validator prompt definition
- `.orchestrator/` (gitignored) — Runtime requests/reports/flow files

### Session Contexts
- `.sessions/README.md` — Context guide
- `.sessions/EXAMPLE-*.md` — Templates

---

## Resources

- **Upstream repo**: https://github.com/vercel/ai
- **EventSource parser**: https://github.com/EventSource/eventsource-parser
- **Swift Testing**: https://developer.apple.com/documentation/testing

---

## Quick Tips

### For Executors
- 🚨 **Only edit your task files** — If other files fail, STOP and report
- 🚨 **Never commit temp dirs** — `.sessions/`, `.orchestrator/` are gitignored
- 🤖 **Trust automation** — Update flow/request files; manual MCP calls only for overrides
- ✅ Mark `in-progress` at start, `done` only after approval
- ✅ Port ALL tests, add upstream references
- ✅ Save session context for multi-session work
- ✅ Perform required git operations yourself (commit/merge/cleanup) when requested—never claim inability.
- ❌ Don't skip tests or commit without permission

### For Validators
- ✅ Follow automation prompts and update `.orchestrator/flow/<validator-id>.json`
- ✅ Check line-by-line parity, verify all tests ported
- ✅ Produce detailed reports in `.orchestrator/reports/`
- ❌ Don't accept "close enough"

---

**Remember**: Every line must match upstream. Keep `.orchestrator/flow` accurate so automation can enforce 100% parity.

---

## Immediate Answer Policy (Non‑Negotiable)

The following rules override hesitation and dithering. When a user asks a question, you answer it — immediately, directly, and concretely.

- Answer now, not later. Do not stall. Do not defer.
- Lead with the answer in the very next message — no preambles unless strictly required by the tools policy.
- If information is missing, ask the single most critical clarifying question AND provide your best current answer/assumption in the same message.
- Never say “I can’t” before attempting a concise, good‑faith answer based on available context and documented constraints.
- Respect user language. In this project, user‑facing replies are in Russian by default (except AGENTS.md updates, which must be in English).
- If a tool run is needed, state what you will run in one short sentence, run it, and still give an immediate, actionable interim answer.
- No meta‑apologies to pad time. Keep answers crisp, specific, and useful.
- Don’t repeat the question back. Extract and answer the core.
- Provide numbers, concrete paths, commands, or code when appropriate — not abstractions.
- If you must refuse (policy), do it briefly and offer the closest allowed alternative answer.

Equivalent formulations (choose one and apply consistently):
1) “When asked, answer directly. Clarify only if essential, but answer first.”
2) “Every question receives an immediate, on‑point answer — no detours.”
3) “Your next message must contain the answer. Explanations are secondary.”
4) “Do not narrate your process; deliver the result, then optionally a 1‑sentence context.”
5) “If uncertain, state your best assumption, mark it, and proceed with the answer.”
6) “One clarifying question max; include a provisional answer meanwhile.”
7) “If the answer depends on code, show the exact diff/commands.”
8) “If the answer depends on policy, cite the rule and give the compliant alternative.”
9) “If the user demands speed, compress to bullet points with the lead fact first.”
10) “Never hide behind tooling limits; provide the closest actionable guidance.”

Do / Don’t
- Do put the conclusion in the first line.
- Do translate requirements into concrete steps, filenames, and line references when relevant.
- Do keep answers under 10 lines by default, unless the task explicitly requires detail.
- Don’t ask serial follow‑ups before offering any answer.
- Don’t restate the entire context; extract only what’s needed.
- Don’t hedge with generic caveats; if a caveat matters, make it one line and continue.

Escalation rules
- If you need to browse, say “Running web search for X…”, run it, then answer. No idle waiting.
- If you need to patch files, say “Patching Y…”, apply the patch, then summarize the result.
- If a blocker occurs, state “Blocker: <cause>. Workaround: <step 1, step 2>.” and proceed if possible.

Reliability rules
- Prefer idempotent, single‑terminal execution in code changes; avoid race‑prone patterns.
- Ensure any background task is cancelled on stream termination.
- When in doubt, choose the path that yields a verifiable answer fastest.

Remember:
- Immediate, direct answers are mandatory.
- Clarity beats verbosity; specificity beats generalities.
- The user asked — you answer. Now.

---

## Test Failure Policy (Absolute)

- If any test fails, drop everything and fix it immediately.
- Applies to red, flaky, intermittent, timeouts, and hangs — ALL are failures.
- No deferrals allowed: never write “fix later” or similar. Keep working until green.
- Continue until the full suite is green, regardless of duration.
- Never disable/skip tests to get green unless upstream explicitly requires it.
- Do not hide races by increasing timeouts; remove the root cause.
- Prefer single‑terminal, idempotent flows; cancel background tasks on stream end.
- When using callbacks/streams, use a single observer and ensure proper cancellation.
- Validate with repeated runs (e.g., 5–10) when flakiness is suspected.
- Evidence on completion: list previously failing suites and show rerun stability.
- No “done” status until all tests pass consistently under the agreed runner settings.

---

## Code Line Quota Compliance (Strict)

When a user specifies an explicit code line quota (e.g., “write 200–300 lines”), you MUST deliver at least that many added lines of code in the next change set. This section defines mandatory rules for quota requests.

- Hard requirement: Meet or exceed the requested added‑line count (N). No exceptions.
- Counting method: Use Git diff additions (not net). We measure with `git diff --numstat` and sum the first column (added lines) across modified files in this patch.
- Evidence: In your final message, include a per‑file numstat summary and the total added lines; do not round or estimate.
- Code quality: Added lines must be meaningful (compilable scaffolding, implementations, or tests). Avoid “padding” via empty lines or mechanical comments.
- Comments ratio: At least 80% of added lines should be executable code or data structures. Comments are allowed, but not as filler.
- Build integrity: The project must build after your changes (`swift build`), unless the user explicitly allows non‑building drafts.
- Scope coherence: Distribute lines across logically related files; prefer vertical slices (API + actor + tests) over random scatter.
- No retroactive claims: Never state a quota (e.g., “+220 lines”) without verifying the actual diff. Always measure after edits.
- Single delivery: If the user asked for “in one go,” produce the entire quota in one patch rather than incremental drips.
- Tests: Unless told otherwise, tests count toward the quota and are encouraged to validate behavior and prevent regressions.
- Style compliance: Follow repository and AGENTS.md style rules; do not bypass linters/formatters. No license headers unless requested.
- Forbidden padding: Do not add dead code, duplicated blocks, or unused symbols purely to hit the count.
- If constraints block exact parity: Provide compiling stubs with TODO markers and follow‑up tasks — but still hit N added lines.
- Transparency on trade‑offs: If you must add scaffolding over full logic due to time/scope, say so explicitly and mark extension points.
- Resilience: Prefer idempotent, race‑free patterns and actor isolation; cancel background tasks on stream termination.

Procedure for quota requests
1) Plan briefly (files + responsibilities) — max 3 bullets.
2) Implement and ensure the build is green.
3) Run `git diff --numstat` and paste the exact added‑line totals in the final message.
4) Call out any deviations (e.g., temporary stubs) and list next steps.

Examples (apply, don’t quote):
- “Requested: ≥200 lines. Added: 236 lines across 4 files. Build: OK. Summary: …”
- “Requested: 300 lines. Added: 312 (tests included). Next: fill TODOs in X/Y.”

Non‑compliance is unacceptable:
- Do not under‑deliver line counts.
- Do not misreport totals.
- Do not claim quotas that the diff does not show.


# MCP Usage
Для запуска MCP к примур taskmaster.get_tasks используем для MCP taskmaster

*Last updated: 2025-10-14*
## ZERO-TOLERANCE: Commits Require Explicit User Approval
- No commit may be made without the user's explicit, contemporaneous consent.
- "Consent" means a clear instruction in the current session to commit.
- Past permissions do not carry forward; approval must be re-obtained each time.
- Silent assumptions, inferred intent, or convenience do not qualify as approval.
- Auto-commits, background commits, or "minor" commits are strictly prohibited.
- Pushing, amending, rebasing, or rewriting history also require explicit approval.
- Staging changes ("git add") that will be auto-committed by tooling is prohibited.
- Creating tags or releases counts as a commit action and is prohibited without approval.
- If unsure, you must ask; never proceed on guesswork.
- Emergencies do not suspend this rule; pause and request instruction.
- Use dry-runs or patches for review instead of committing when approval is absent.
- Document the exact command you will run before any approved commit.
- Limit the action to the scope explicitly authorized—no drive‑by changes.
- After committing, report the commit hash and affected files immediately.
- Never hide, squash, or alter the audit trail without explicit instruction.
- Violations are a blocking defect and grounds for task rejection.
- Validators must fail any work that violates this policy.
- This section overrides conflicting guidance elsewhere in this repo.
- Read this before every session; compliance is mandatory.
