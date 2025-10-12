# Swift AI SDK - Agent Guide

## Project Mission

Port **Vercel AI SDK** from TypeScript to Swift with **100% upstream parity**.

**Goal**: 1:1 feature-complete implementation matching TypeScript API, behavior, types, and tests.

---

## Quick Start

**📋 Task Management:**
```bash
# Task Master commands
mcp__taskmaster__next_task                              # Find next task
mcp__taskmaster__get_task --id=4.3                      # Get task details
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

1. Find next task: `mcp__taskmaster__next_task`
2. **Mark task as in-progress**: `mcp__taskmaster__set_task_status --id=X --status=in-progress`
3. Find TypeScript code in `external/vercel-ai-sdk/`
4. Port to Swift in `Sources/SwiftAISDK/`
5. Port ALL upstream tests to `Tests/SwiftAISDKTests/`
6. Run `swift build && swift test` (must pass 100%)
7. Request validation review (create request in `.validation/requests/`)
8. Wait for validation approval
9. **Mark complete ONLY after approval**: `mcp__taskmaster__set_task_status --id=X --status=done`
10. **Commit ONLY when user requests**: Wait for explicit permission

**Never**:
- ❌ **NEVER TOUCH OTHER AGENTS' WORK** — If you see compilation/test errors in files you didn't create, STOP and wait for that agent to fix them. DO NOT edit, fix, or modify any files outside your current task scope
- ❌ Commit/push without explicit user permission
- ❌ Mark task as `done` before validation approval
- ❌ Skip setting task status to `in-progress` at start
- ❌ Break parity or leave failing tests

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
mcp__taskmaster__next_task                  # Find next task
mcp__taskmaster__get_task --id=4.3          # Check task details
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

**🚧 Next Priorities** (see Task Master):
- Block D: PrepareTools, ConvertToLanguageModelPrompt
- Block E: Generate/Stream Text core functionality
- Block F: Text/UI streams

**Stats**: ~14,300 lines, 137 files, 100% upstream parity maintained

---

## Key Commands

```bash
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

1. **🚨 NEVER TOUCH OTHER AGENTS' WORK** — Only edit files within your assigned task. If other files have errors, STOP and report to user. Multiple agents work in parallel — editing other agents' files causes conflicts and data loss
2. **Read first, code second** — Always check upstream and plan
3. **Update task status at start** — Mark `in-progress` before coding
4. **Test everything** — No code without tests (100% coverage)
5. **Validate early** — Use validator agent proactively
6. **Mark done ONLY after validation** — Never mark complete before approval
7. **Never commit without permission** — Wait for explicit user request
8. **100% parity** — Match TypeScript behavior exactly

---

## Documentation Files

### Core
- `README.md` — Project overview, stats
- `CLAUDE.md` — This file (agent guide)
- `Package.swift` — SwiftPM manifest

### Plan Directory
- `principles.md` — Porting guidelines with examples
- `executor-guide.md` — Detailed executor workflow
- `validation-workflow.md` — ⭐ Validation process & agent usage
- `validator-guide.md` — Manual validation checklist (legacy)
- `design-decisions.md` — Documented deviations
- `tests.md` — Testing approach
- `taskmaster-usage.md` — Task Master usage (optional, manual mode)

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
- 🚨 **NEVER edit files outside your task** — If `swift test` fails on other agents' files, STOP work and report to user. Wait for them to fix it
- ✅ **Set task status to `in-progress` at start**
- ✅ Port ALL upstream tests, not just some
- ✅ Use validator agent after implementation
- ✅ **Mark task `done` ONLY after validation approval**
- ✅ **Commit ONLY when user explicitly requests**
- ✅ Add upstream references to every file
- ✅ Document adaptations with rationale
- ✅ Save session context for multi-session tasks ("Зафиксируй контекст")
- ❌ Don't skip edge case tests
- ❌ Don't commit without explicit user permission
- ❌ Don't mark task complete before validation
- ❌ Don't leave old session contexts after completion
- ❌ **NEVER fix compilation errors in other agents' files**

### For Validators
- ✅ Use the custom validator agent (`.claude/agents/validator.md`)
- ✅ Check line-by-line API/behavior parity
- ✅ Verify ALL upstream tests ported
- ✅ Run tests yourself
- ❌ Don't accept "close enough"
- ❌ Don't skip checking edge cases

---

## Task Management (Optional)

This project has **Task Master AI** available as an **optional structured task tracker**.

### ⚠️ Important: Manual Mode Only

**We do NOT use Task Master's AI features.** No API keys required.

### ❌ FORBIDDEN (Always Use AI):
- `update_task` — requires `prompt` parameter (AI-only)
- `update_subtask` — requires `prompt` parameter (AI-only)
- `expand_task` — AI generation
- `parse-prd` — AI generation
- `--research` flag
- Any tool with required `prompt` parameter

### ✅ ALLOWED Tools (Manual Only):
- `get_tasks` — view tasks
- `get_task` — get specific task details
- `next_task` — find next available task
- `set_task_status` — change status (use this for updates!)
- `add_task` — with explicit `title`, `description`, `details`
- `add_subtask` — with explicit fields
- `remove_task` / `remove_subtask`
- `add_dependency` / `remove_dependency`
- `validate_dependencies` / `fix_dependencies`

**Rule**: `update_task` is AI-only. Use `set_task_status` for status changes, or edit JSON directly for other fields.

### Basic Usage (Manual Mode)

```bash
# View tasks (via MCP)
mcp__taskmaster__get_tasks

# Find next task
mcp__taskmaster__next_task

# Add task manually (explicit text, no AI)
mcp__taskmaster__add_task
  title: "Implement PrepareTools function"
  description: "Port prepareTools from @ai-sdk/ai/src/..."
  details: "Detailed implementation notes here"

# Update task status
mcp__taskmaster__set_task_status
  id: "1.2"
  status: "done"

# Add dependencies
mcp__taskmaster__add_dependency
  id: "2.1"
  dependsOn: "1.2"
```

### Integration with Existing Workflow

Task Master provides structured task tracking:

- **Primary source**: Task Master for task management
- **Session contexts**: Still used in `.sessions/`
- **Validation**: Still uses `.validation/` workflow

### When to Use

- ✅ Complex multi-block projects with dependencies
- ✅ Tracking parallel work across multiple agents
- ✅ Need structured view of task hierarchy
- ✅ All project task management

### Files

- `.taskmaster/` — Fully gitignored (each dev installs if needed)
- `.claude/commands/tm/` — Task Master slash commands (committed)
- Task Master MCP server configured globally (no local config needed)

---

**Remember**: Every line of code must match upstream behavior. Use validator agent to ensure 100% parity.

*Last updated: 2025-10-12*
