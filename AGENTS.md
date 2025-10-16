# ⚠️ Ответы пользователю всегда на русском языке.

<!-- Please write all AGENTS.md updates in English. -->
# Swift AI SDK - Agent Guide

## Project Mission

Port **Vercel AI SDK** from TypeScript to Swift with **100% upstream parity**.

**Goal**: 1:1 feature-complete implementation matching TypeScript API, behavior, types, and tests.

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

## Testing & Race Condition Detection

### Smart Test Runner

**Location**: `tools/test-runner.js`

**Purpose**: Detect hanging tests, race conditions, and flaky test behavior through multi-run analysis.

#### Smart Mode (`--smart`)

Runs tests multiple times to identify race conditions and unstable tests:

```bash
# Run smart mode with 3 iterations and 5s timeout
node tools/test-runner.js --smart --runs 3 --timeout 5000

# Analyze specific config
node tools/test-runner.js --smart --config test-runner.default.config.json --runs 5
```

**Smart Mode Features**:
- ✅ **Multi-run analysis**: Runs test suite N times to catch intermittent failures
- ✅ **Timeout detection**: Identifies tests that hang (race conditions)
- ✅ **Culprit identification**: Binary search to isolate problematic tests
- ✅ **Stability analysis**: Shows which tests fail sometimes vs always
- ✅ **Clean reporting**: Groups by suite, shows patterns

> 💡 **Tip**: Run `swift build` once before invoking `node tools/test-runner.js ...`. A warm build keeps the first iteration fast and prevents false timeouts from cold compilation.

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


# MCP Usage
Для запуска MCP к примур taskmaster.get_tasks используем для MCP taskmaster

*Last updated: 2025-10-14*
