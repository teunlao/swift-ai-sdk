# Swift AI SDK - Agent Guide

## Project Mission

Port **Vercel AI SDK** from TypeScript to Swift with **100% upstream parity**.

**Goal**: 1:1 feature-complete implementation matching TypeScript API, behavior, types, and tests.

---

## Quick Start

**📋 Task Management:**
```bash
mcp__taskmaster__next_task                              # Find next task
mcp__taskmaster__get_task --id=4.3                      # Get details
mcp__taskmaster__get_tasks --status=pending             # List pending
mcp__taskmaster__set_task_status --id=4.3 --status=done # Mark done
```

**📚 Read first:**
```bash
.taskmaster/CLAUDE.md           # Task Master guide
plan/executor-guide.md          # Executor workflow
plan/validation-workflow.md     # Validation process
plan/orchestrator-automation.md # Flow files, naming, automation rules
plan/principles.md              # Porting rules
```

---

## Project Structure

```
swift-ai-sdk/
├── .claude/agents/validator.md  # Custom validator agent definition
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

## Roles & Workflow

### Executor Role (Codex Agent)
**Implement features, write tests, maintain automation flow artifacts.**

Executor agents launch with a system prompt that enforces `.orchestrator/` discipline:
1. Receive task via orchestrator prompt.
2. Port TypeScript sources (`external/vercel-ai-sdk/...`) to the matching Swift target.
3. Port ALL upstream tests.
4. Run `swift build && swift test` (must pass 100%).
5. Write Markdown request in `.orchestrator/requests/validate-<task>-<iteration>-<timestamp>.md` summarising the change set.
6. Update `.orchestrator/flow/<executor-id>.json`:
   - `status = "ready_for_validation"`
   - `request.ready = true`
   - `request.path` references the new file.
7. If blocked, set `status = "needs_input"` and add `blockers` describing the issue instead of creating a request.
8. **Stop.** Automation triggers validation automatically.

**🚨 CRITICAL Rules for Executor Agents**:
- ❌ **NEVER TOUCH OTHER AGENTS' WORK** — stay within task scope.
- ✅ Keep flow JSON valid, minified, and up to date after every meaningful change.
- ❌ Do NOT invoke MCP tools yourself; the orchestrator drives the loop.
- ❌ Do NOT launch validators manually.

### Validator Role (Codex Agent)
**Review implementation, create automation-compliant report.**

Validator agents also receive a system prompt:
1. Launches in executor worktree (manual mode) with request path provided via flow file.
2. Read executor flow + request, inspect implementation, compare to upstream.
3. Run `swift build && swift test` if needed.
4. Produce report in `.orchestrator/reports/validate-<task>-<iteration>-<timestamp>-report.md`.
5. Update `.orchestrator/flow/<validator-id>.json` with `report.path`, `report.result` (`approved`/`rejected`), `summary`, optional `blockers`.
6. **Stop.** Automation finalizes the session.

**🚨 CRITICAL Rules for Validator Agents**:
- ✅ Always operate in the executor's worktree; never create new branches/worktrees.
- ✅ Document outcome via flow JSON and report file; use severity labels inside the report.
- ❌ Do NOT call MCP tools; automation handles status updates.
- ❌ Approve only when parity is 100%.

### Orchestrator Workflow (Your Role)
**Automation-first orchestration: monitor, assist, fall back only when required.**

**Validation mandate remains:** every task must reach an approved validation unless the user explicitly says `skip validation` or `no validation needed`.

1. **Launch executors with named worktrees (required).**
   ```
   launch_agent(role="executor", worktree="auto", worktree_name="task-4-3", prompt="...")
   ```
   The system prompt instructs the agent to manage `.orchestrator/flow` and request files.

2. **Monitor automation instead of driving every step manually.**
   - Executors publish Markdown requests under `.orchestrator/requests/` and set `status="ready_for_validation"` in their flow JSON.
   - The automation engine (inside MCP) observes flow updates, creates validation sessions, and launches validators in the same worktree (`worktree="manual"`, `cwd=<executor worktree>`).
   - Validators analyse code, write reports to `.orchestrator/reports/`, update their flow JSON; automation finalizes the session (`approved` or `rejected`).
   - On rejection, automation issues `continue_agent` with a fix-it prompt so the executor re-enters the loop for the next iteration.

3. **Keep an eye on flow state and agent health.**
   - Use `status()` or read `.orchestrator/flow/*.json` to confirm progress.
   - `needs_input` means the agent is blocked waiting for us (provide information or follow-up prompt).
   - Continue to log `sleep <N> && status(...)` checks while automation is running to verify agents stay alive.

4. **Use MCP tools as overrides when automation needs help.**
   - `request_validation`, `assign_validator`, `submit_validation`, `continue_agent` are still available for manual repair or if automation is paused.
   - When overriding, ensure flow JSON/requests/reports stay consistent so the watcher can resume.

5. **After approval** merge or archive executor worktrees per usual. Automation leaves executors in `validated`; close out tasks in Task Master.

**Worktree defaults (unchanged):** executors → `worktree="auto"`; validators → `worktree="manual"` + `cwd=executor_worktree`. Only override if the user insists.

**Documentation:**
- 📘 `plan/validation-workflow.md` — Automation and fallback details
- 🤖 `.claude/agents/validator.md` — Validator prompt template
- 🗂️ `plan/orchestrator-automation.md` — Flow schemas and naming conventions

---

## Implementation Workflow

### 1. Find Upstream Code
```bash
cat external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
cat external/vercel-ai-sdk/packages/provider-utils/src/delay.test.ts
```

### 2. Implement in Swift

**File naming** (match upstream package):
```
TS:   external/.../packages/provider-utils/src/delay.ts
Swift: Sources/AISDKProviderUtils/Delay.swift
Test:  Tests/AISDKProviderUtilsTests/DelayTests.swift
```

**⚠️ Header required**:
```swift
/**
 Brief description.

 Port of `@ai-sdk/provider-utils/src/delay.ts`.
 */
```

### 3. Port ALL Tests

Port every test case from `.test.ts` to Swift Testing:
- Same test names (camelCase)
- Same test data and edge cases
- **100% coverage required**

### 4. Verify & Validate

```bash
swift build && swift test           # Must pass
# Update .orchestrator/requests + flow JSON (status=ready_for_validation)
# Automation will launch validator and handle the cycle
```
See `plan/orchestrator-automation.md` for request/report templates.

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

1. **Automation leads the loop** — Executors/validators follow system prompts; maintain `.orchestrator/` artifacts so the watcher can respond.
2. **Agents still cannot call MCP tools** — Only you may invoke overrides when automation stalls (`request_validation`, `assign_validator`, `submit_validation`, `continue_agent`).
3. **Flow files are the contract** — Keep JSON valid/minified; statuses (`working`, `ready_for_validation`, `needs_input`, etc.) drive orchestration.
4. **`needs_input` stops automation** — When you see it, respond with the required information/prompt before expecting progress.
5. **100% parity required** — Validators reject until implementation matches upstream exactly.
6. **Worktree isolation remains mandatory** — Executors on `auto`, validators on `manual` pointing to executor worktree.
7. **Never commit without permission** — Only after explicit user instruction.

---

## Documentation Files

### Core
- `README.md` — Project overview
- `CLAUDE.md` — This file
- `Package.swift` — SwiftPM manifest

### Plan Directory
- `principles.md` — Porting guidelines
- `executor-guide.md` — Executor workflow
- `validation-workflow.md` — Validation process
- `validator-guide.md` — Manual checklist (legacy)
- `design-decisions.md` — Documented deviations
- `tests.md` — Testing approach

### Validation Automation
- `plan/orchestrator-automation.md` — Flow schema, naming conventions
- `plan/validation-workflow.md` — Automation + fallback playbook
- `.claude/agents/validator.md` — Validator agent definition
- `.orchestrator/` (gitignored) — Runtime artifacts (flow, requests, reports)

### Session Contexts
- `.sessions/README.md` — Context guide
- `.sessions/EXAMPLE-*.md` — Templates

---

## Quick Tips

### For Executors
- 🚨 **Only edit your task files** — If other files fail, STOP and report
- 🚨 **Never commit temp dirs** — `.sessions/`, `.orchestrator/` are gitignored
- 🤖 **Respect automation** — Maintain flow JSON/request; no manual MCP calls unless recovering
- ✅ Mark `in-progress` at start, `done` only after approval
- ✅ Port ALL tests, add upstream references
- ✅ Save session context for multi-session work
- ❌ Don't skip tests or commit without permission

### For Validators
- ✅ Use validator agent (`.claude/agents/validator.md`)
- ✅ Check line-by-line parity, verify all tests ported
- ❌ Don't accept "close enough"

---

## Task Management (Optional)

**Task Master AI** available as optional tracker.

### Manual Tools
- `get_tasks`, `get_task`, `next_task` — view tasks
- `set_task_status` — change status
- `add_task`, `add_subtask` — with explicit fields
- `remove_task`, `remove_subtask`
- `add_dependency`, `remove_dependency`, `validate_dependencies`

### AI Tools
- `update_task`, `update_subtask` — require `prompt` parameter
- `expand_task`, `parse-prd` — AI generation
- Tools with `--research` flag

**Basic Usage**:
```bash
mcp__taskmaster__next_task
mcp__taskmaster__add_task title: "..." description: "..." details: "..."
mcp__taskmaster__set_task_status id: "1.2" status: "done"
```

**Integration**: Task Master for management, `.sessions/` for contexts, `.orchestrator/` for automation artifacts.

**Files**: `.taskmaster/` gitignored, `.claude/commands/tm/` committed.

---

**Remember**: Every line must match upstream. Use validator agent for 100% parity.

*Last updated: 2025-10-14*
