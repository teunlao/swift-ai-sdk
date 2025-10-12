# Swift AI SDK - Agent Guide

## Project Mission

Port **Vercel AI SDK** from TypeScript to Swift with **100% upstream parity**.

**Goal**: 1:1 feature-complete implementation matching TypeScript API, behavior, types, and tests.

---

## Quick Start

**Read these files first every session**:
```bash
plan/todo.md                    # Task list
plan/progress.md                # Current status & history
plan/executor-guide.md          # Executor workflow
plan/validation-workflow.md     # Validation process
plan/principles.md              # Porting rules
```

---

## Project Structure

```
swift-ai-sdk/
├── .claude/
│   └── agents/
│       └── validator.md        # Custom validator agent
├── .sessions/                   # Session contexts (gitignored)
│   ├── README.md               # Session context guide
│   └── EXAMPLE-*.md            # Context template
├── .validation/                 # Temp validation artifacts (gitignored)
│   ├── requests/               # Validation requests
│   ├── reports/                # Validation reports
│   └── QUICKSTART.md           # How to use validator
├── Sources/
│   ├── EventSourceParser/      # SSE parser
│   └── SwiftAISDK/
│       ├── Provider/           # V2/V3 types, errors, JSONValue
│       ├── ProviderUtils/      # HTTP, JSON, delays, headers
│       └── Core/               # Generate-text, streams, tools
├── Tests/                       # Swift Testing tests
├── external/                    # ⚠️ UPSTREAM REFERENCE (read-only)
│   ├── vercel-ai-sdk/          # TypeScript source to port
│   └── eventsource-parser/     # SSE parser reference
└── plan/                        # Documentation & progress
```

### Session Contexts

**Problem**: Multiple agents can work in parallel, losing context between sessions.

**Solution**: Session context files (`.sessions/`) fix state between sessions.

**Usage**:
- 💬 **Capture context**: `"Зафиксируй контекст текущей работы"`
- 📂 **Resume work**: `"Загрузи контекст из .sessions/session-YYYY-MM-DD-HH-MM-feature.md"`
- 🗑️ **Cleanup**: Delete context after task completion

**When to use**:
- ✅ Multi-session tasks
- ✅ Interrupted work (need to continue later)
- ✅ Blocked work (waiting for clarification)
- ✅ Complex tasks (need checkpoint)
- ❌ Simple one-session tasks

**See**: `.sessions/README.md` for complete guide

---

## Upstream References

**Vercel AI SDK** (current: 6.0.0-beta.42, commit `77db222ee`):
```
external/vercel-ai-sdk/
├── packages/provider/           # Language model types (V2/V3)
├── packages/provider-utils/     # Utilities (HTTP, JSON, SSE)
└── packages/ai/                 # Core SDK (generate-text, streams, tools)
```

**EventSource Parser**: `external/eventsource-parser/`

---

## Roles & Workflow

### Executor Role
**Implement features, write tests, update docs.**

1. Read plan docs (`plan/*.md`)
2. Find TypeScript code in `external/vercel-ai-sdk/`
3. Port to Swift in `Sources/SwiftAISDK/`
4. Port ALL upstream tests to `Tests/SwiftAISDKTests/`
5. Run `swift build && swift test` (must pass 100%)
6. Request validation review
7. Update `plan/progress.md` with timestamped entry

**Never**: Commit/push without permission, break parity, leave failing tests.

### Validator Role
**Review executor work for 100% upstream parity.**

**Automated validation** via custom validator agent:
- Agent: `.claude/agents/validator.md`
- Compares Swift vs TypeScript line-by-line
- Verifies API/behavior parity, test coverage
- Generates detailed validation reports
- **See**: `plan/validation-workflow.md` for complete process

**Manual validation** (legacy):
- See `plan/validator-guide.md` for checklist

### Validation Workflow (Quick)

**Executor**:
```bash
# 1. Complete implementation + tests
swift build && swift test

# 2. Create validation request
cat > .validation/requests/validate-feature-$(date +%Y-%m-%d).md <<EOF
# Validation Request — Feature Name
[see .validation/QUICKSTART.md for template]
EOF

# 3. Trigger validator agent in chat:
# "Use the validator agent to review .validation/requests/validate-feature-YYYY-MM-DD.md"
```

**Validator agent** automatically:
1. Reads validation request
2. Compares Swift vs TypeScript source
3. Runs tests, checks coverage
4. Generates report in `.validation/reports/`
5. Documents verdict: ✅ APPROVED / ⚠️ ISSUES / ❌ REJECTED

**Documentation**:
- 📘 `plan/validation-workflow.md` — Complete workflow guide
- 🚀 `.validation/QUICKSTART.md` — Quick start for executors
- 🤖 `.claude/agents/validator.md` — Validator agent definition

---

## Standard Implementation Workflow

### 1. Planning
```bash
cat plan/todo.md              # Check tasks
cat plan/progress.md | tail   # Check status
```

### 2. Find Upstream Code
```bash
# Example: delay function
cat external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
cat external/vercel-ai-sdk/packages/provider-utils/src/delay.test.ts
```

### 3. Implement in Swift

**File naming**:
```
TypeScript: external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
Swift:      Sources/SwiftAISDK/ProviderUtils/Delay.swift
Tests:      Tests/SwiftAISDKTests/ProviderUtils/DelayTests.swift
```

**⚠️ REQUIRED: Upstream Reference**

Every ported file MUST include header:

```swift
/**
 Brief description of the module.

 Port of `@ai-sdk/provider-utils/src/delay.ts`.

 Additional details if needed.
 */
```

**Format**: `Port of '@ai-sdk/PACKAGE/src/PATH.ts'` in backticks
**Packages**: `provider`, `provider-utils`, `ai`

### 4. Port ALL Tests

Port every test case from `.test.ts` to Swift Testing:
- Same test names (camelCase)
- Same test data
- Same edge cases
- **100% coverage required**

See `plan/tests.md` for details.

### 5. Verify
```bash
swift build              # Must succeed
swift test               # All tests must pass
```

### 6. Request Validation

See **Validation Workflow** above or `.validation/QUICKSTART.md`

### 7. Document Progress
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"  # Get timestamp
```

Update `plan/progress.md`:
```markdown
## [executor][agent-name] Session YYYY-MM-DDTHH:MM:SSZ: Feature Name

**Implemented:**
- ✅ File.swift — description (X tests, 100% parity)

**Tests:** X/X passed (+Y new)

— agent-executor/model-name, YYYY-MM-DDTHH:MM:SSZ
```

---

## Parity Standards

### Must Match Exactly
- ✅ Public API (names, parameters, return types)
- ✅ Behavior (edge cases, errors, null handling)
- ✅ Error messages (same text when possible)
- ✅ Test scenarios (all upstream tests ported)

### Allowed Swift Adaptations
- ✅ `Promise<T>` → `async throws -> T`
- ✅ `AbortSignal` → `@Sendable () -> Bool` or Task cancellation
- ✅ Union types → `enum` with associated values
- ✅ `undefined` → `nil` (optional types)
- ✅ `Record<K, V>` → `[K: V]`

**Document all adaptations** with upstream reference and rationale.

See `plan/principles.md` for complete guidelines.

---

## Common TypeScript → Swift Patterns

**Quick reference** (see `plan/principles.md` for full list):

| TypeScript | Swift |
|------------|-------|
| `Promise<T>` | `async throws -> T` |
| `value?: T \| undefined` | `value: T? = nil` |
| `type A \| B` | `enum Result { case a(A), case b(B) }` |
| `Record<K, V>` | `[K: V]` |
| `AbortSignal` | `@Sendable () -> Bool` |

---

## Current Status

**✅ Completed** (341/341 tests passing):
- EventSourceParser (30 tests)
- LanguageModelV2 (50 tests)
- LanguageModelV3 (39 tests)
- Provider Errors (26 tests)
- ProviderUtils (185 tests): ID gen, delays, headers, HTTP, schema, validation, parsing
- JSONValue (universal JSON type)
- Block D Foundation (8 tests): Prompt, CallSettings, DataContent

**🚧 Next Priorities** (see `plan/todo.md`):
- Block D: PrepareTools, ConvertToLanguageModelPrompt
- Block E: Generate/Stream Text core functionality
- Block F: Text/UI streams

**Stats**: ~14,300 lines, 137 files, 100% upstream parity maintained

---

## Key Commands

```bash
# Planning
cat plan/todo.md plan/progress.md

# Find upstream
ls external/vercel-ai-sdk/packages/*/src/

# Build & test
swift build && swift test

# Session contexts
cat .sessions/README.md          # How to use contexts
ls .sessions/session-*.md        # List active contexts

# Validation
cat .validation/QUICKSTART.md

# UTC timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

---

## Pre-Completion Checklist

Before requesting validation:

- [ ] Public API matches upstream TypeScript
- [ ] Behavior matches exactly (same inputs → outputs/errors)
- [ ] ALL upstream tests ported
- [ ] All tests pass (including existing tests)
- [ ] Every file has upstream reference in header comment
- [ ] Adaptations documented with rationale
- [ ] `swift build` succeeds without warnings
- [ ] Ready for validation review

---

## Key Principles

1. **Read first, code second** — Always check upstream and plan
2. **Test everything** — No code without tests (100% coverage)
3. **Validate early** — Use validator agent proactively
4. **Document progress** — Every session logged in progress.md
5. **100% parity** — Match TypeScript behavior exactly
6. **Never commit** — Wait for approval

---

## Documentation Files

### Core
- `README.md` — Project overview, stats
- `CLAUDE.md` — This file (agent guide)
- `Package.swift` — SwiftPM manifest

### Plan Directory
- `todo.md` — Master task list (blocks A-O)
- `progress.md` — Session history with timestamps
- `principles.md` — Porting guidelines with examples
- `executor-guide.md` — Detailed executor workflow
- `validation-workflow.md` — ⭐ Validation process & agent usage
- `validator-guide.md` — Manual validation checklist (legacy)
- `design-decisions.md` — Documented deviations
- `tests.md` — Testing approach

### Validation
- `.claude/agents/validator.md` — Custom validator agent
- `.validation/QUICKSTART.md` — How to use validator
- `.validation/requests/EXAMPLE-*.md` — Request template
- `.validation/reports/EXAMPLE-*.md` — Report example

### Session Contexts
- `.sessions/README.md` — Session context guide
- `.sessions/EXAMPLE-session-context.md` — Context template

---

## Resources

- **Upstream repo**: https://github.com/vercel/ai
- **EventSource parser**: https://github.com/EventSource/eventsource-parser
- **Swift Testing**: https://developer.apple.com/documentation/testing

---

## Quick Tips

### For Executors
- ✅ Port ALL upstream tests, not just some
- ✅ Use validator agent after implementation
- ✅ Add upstream references to every file
- ✅ Document adaptations with rationale
- ✅ Save session context for multi-session tasks ("Зафиксируй контекст")
- ❌ Don't skip edge case tests
- ❌ Don't commit without validation approval
- ❌ Don't leave old session contexts after completion

### For Validators
- ✅ Use the custom validator agent (`.claude/agents/validator.md`)
- ✅ Check line-by-line API/behavior parity
- ✅ Verify ALL upstream tests ported
- ✅ Run tests yourself
- ❌ Don't accept "close enough"
- ❌ Don't skip checking edge cases

---

**Remember**: Every line of code must match upstream behavior. Use validator agent to ensure 100% parity.

*Last updated: 2025-10-12*
