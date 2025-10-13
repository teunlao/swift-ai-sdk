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
plan/principles.md              # Porting rules
```

---

## Project Structure

```
swift-ai-sdk/
├── .claude/agents/validator.md  # Custom validator agent
├── .sessions/                   # Session contexts (gitignored)
├── .validation/                 # Validation artifacts (gitignored)
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

### Executor Role
**Implement features, write tests, validate, commit only when approved.**

1. Find next task: `mcp__taskmaster__next_task`
2. **Mark in-progress**: `mcp__taskmaster__set_task_status --id=X --status=in-progress`
3. Find TypeScript in `external/vercel-ai-sdk/packages/`
4. Port to appropriate Swift package
5. Port ALL upstream tests
6. Run `swift build && swift test` (must pass 100%)
7. Create validation request in `.validation/requests/validate-TASK-YYYY-MM-DD.md`
8. **🤖 Launch validator agent yourself** using Task tool (see below)
9. Wait for validator approval (✅ APPROVED)
10. **Mark done ONLY after approval**: `set_task_status --status=done`
11. **Commit ONLY when user requests explicitly**

**🚨 CRITICAL Rules**:
- ❌ **NEVER TOUCH OTHER AGENTS' WORK** — Only edit files in your task scope
- ❌ Never commit without explicit user permission
- ❌ Never mark `done` before validator approval
- 🤖 **YOU launch validator** (not user) — automatic after creating request

### Validator Agent Launch

**After creating validation request, YOU MUST immediately launch validator**:

```
Use Task tool with:
- subagent_type: "validator"
- description: "Validate Task X"
- prompt: "Review .validation/requests/validate-TASK-YYYY-MM-DD.md
          and verify 100% upstream parity"
```

**Validator** compares Swift vs TypeScript, runs tests, generates report with verdict.

**Documentation**:
- 📘 `plan/validation-workflow.md` — Complete process
- 🚀 `.validation/QUICKSTART.md` — Quick start
- 🤖 `.claude/agents/validator.md` — Agent definition

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
# Create validation request
# Launch validator agent yourself
```

See `.validation/QUICKSTART.md` for template.

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
cat .validation/QUICKSTART.md

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
- [ ] Validation request created
- [ ] Validator agent launched

---

## Key Principles

1. **🚨 NEVER TOUCH OTHER AGENTS' WORK** — Only edit your task files. Multiple agents work in parallel.
2. **Read first, code second** — Check upstream, then plan
3. **Mark in-progress at start** — Update status before coding
4. **Test everything** — 100% coverage required
5. **🤖 YOU launch validator** — Automatic after request, don't wait for user
6. **Mark done ONLY after validation** — Wait for approval
7. **Never commit without permission** — Explicit user request required
8. **100% parity** — Match TypeScript exactly

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

### Validation
- `.claude/agents/validator.md` — Validator agent
- `.validation/QUICKSTART.md` — Usage guide
- `.validation/requests/EXAMPLE-*.md` — Templates
- `.validation/reports/EXAMPLE-*.md` — Examples

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
- 🚨 **Never commit temp dirs** — `.sessions/`, `.validation/` are gitignored
- 🤖 **Launch validator yourself** — After creating request, use Task tool immediately
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

**Task Master AI** available as optional tracker (manual mode only, no API keys).

### Allowed Tools (Manual)
- `get_tasks`, `get_task`, `next_task` — view tasks
- `set_task_status` — change status
- `add_task`, `add_subtask` — with explicit fields
- `remove_task`, `remove_subtask`
- `add_dependency`, `remove_dependency`, `validate_dependencies`

### Forbidden Tools (AI-only)
- `update_task`, `update_subtask` (require `prompt` parameter)
- `expand_task`, `parse-prd`, `--research` flag

**Basic Usage**:
```bash
mcp__taskmaster__next_task
mcp__taskmaster__add_task title: "..." description: "..." details: "..."
mcp__taskmaster__set_task_status id: "1.2" status: "done"
```

**Integration**: Task Master for management, `.sessions/` for contexts, `.validation/` for validation.

**Files**: `.taskmaster/` gitignored, `.claude/commands/tm/` committed.

---

**Remember**: Every line must match upstream. Use validator agent for 100% parity.

*Last updated: 2025-10-13*
