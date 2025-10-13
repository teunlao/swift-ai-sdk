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
├── Package.swift                # SwiftPM manifest (3 targets)
├── Sources/
│   ├── AISDKProvider/          # Foundation package (78 files)
│   │   ├── LanguageModel/      # V2/V3 protocols & types
│   │   ├── EmbeddingModel/     # V2/V3 embedding types
│   │   ├── ImageModel/         # V2/V3 image types
│   │   ├── SpeechModel/        # V2/V3 speech types
│   │   ├── TranscriptionModel/ # V2/V3 transcription types
│   │   ├── Errors/             # Provider errors
│   │   ├── JSONValue/          # Universal JSON type
│   │   ├── Shared/             # Shared V2/V3 types
│   │   └── ProviderV2/V3.swift # Provider protocols
│   │
│   ├── AISDKProviderUtils/     # Utilities package (35 files)
│   │   ├── HTTP utilities      # GET/POST, headers, retries
│   │   ├── JSON utilities      # Parsing, validation
│   │   ├── Schema/             # Schema definitions
│   │   ├── Tool definitions    # Tool, DynamicTool
│   │   ├── Data handling       # DataContent, SplitDataUrl
│   │   └── Utility functions   # ID gen, delays, etc.
│   │
│   ├── SwiftAISDK/             # Main SDK package (105 files)
│   │   ├── GenerateText/       # High-level functions
│   │   ├── Prompt/             # Prompt conversion
│   │   ├── Tool/               # Tool execution, MCP
│   │   ├── Registry/           # Provider registry
│   │   ├── Middleware/         # Middleware implementations
│   │   ├── Telemetry/          # Logging & telemetry
│   │   ├── Gateway/            # Gateway integration
│   │   ├── Error/              # SDK-specific errors
│   │   ├── Model/              # Model resolution
│   │   ├── Types/              # SDK types
│   │   ├── Test/               # Mock models
│   │   └── Util/               # SDK utilities
│   │
│   └── EventSourceParser/      # SSE parser (2 files)
│
├── Tests/                       # Swift Testing tests
│   ├── AISDKProviderTests/     # Provider tests (~210)
│   ├── AISDKProviderUtilsTests/# Utils tests (~200)
│   ├── SwiftAISDKTests/        # SDK tests (~300)
│   └── EventSourceParserTests/ # SSE tests (30)
│
├── external/                    # ⚠️ UPSTREAM REFERENCE (read-only)
│   ├── vercel-ai-sdk/          # TypeScript source to port
│   │   └── packages/
│   │       ├── provider/       → AISDKProvider
│   │       ├── provider-utils/ → AISDKProviderUtils
│   │       └── ai/             → SwiftAISDK
│   └── eventsource-parser/     # SSE parser reference
│
└── plan/                        # Documentation & progress
```

### Package Dependency Graph
```
AISDKProvider (no dependencies)
    ↑
AISDKProviderUtils (depends on: AISDKProvider)
    ↑
SwiftAISDK (depends on: AISDKProvider, AISDKProviderUtils, EventSourceParser)
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
external/vercel-ai-sdk/packages/
├── provider/           → Sources/AISDKProvider/
│   ├── language-model/ → LanguageModel/V2/, LanguageModel/V3/
│   ├── errors/         → Errors/
│   └── ...
├── provider-utils/     → Sources/AISDKProviderUtils/
│   ├── delay.ts        → Delay.swift
│   ├── schema.ts       → Schema/Schema.swift
│   └── ...
└── ai/                 → Sources/SwiftAISDK/
    ├── generate-text/  → GenerateText/
    ├── prompt/         → Prompt/
    └── ...
```

**EventSource Parser**: `external/eventsource-parser/` → `Sources/EventSourceParser/`

---

## Roles & Workflow

### Executor Role
**Implement features, write tests, update docs.**

1. Find next task: `mcp__taskmaster__next_task`
2. **Mark task as in-progress**: `mcp__taskmaster__set_task_status --id=X --status=in-progress`
3. Find TypeScript code in `external/vercel-ai-sdk/packages/`
4. Determine package: `provider/`, `provider-utils/`, or `ai/`
5. Port to Swift in appropriate package: `Sources/AISDKProvider/`, `Sources/AISDKProviderUtils/`, or `Sources/SwiftAISDK/`
6. Port ALL upstream tests to corresponding test target
7. Run `swift build && swift test` (must pass 100%)
8. Create validation request in `.validation/requests/validate-TASK-YYYY-MM-DD.md`
9. **🤖 YOU MUST: Use Task tool to launch validator agent** (see command below)
10. Wait for validator agent approval (✅ APPROVED)
11. **Mark complete ONLY after approval**: `mcp__taskmaster__set_task_status --id=X --status=done`
12. **Commit ONLY when user requests**: Wait for explicit permission

**🚨 CRITICAL: Validation is YOUR responsibility**

You MUST launch the validator agent yourself using the Task tool:
```
Use Task tool with:
- subagent_type: "validator"
- prompt: "Review .validation/requests/validate-TASK-YYYY-MM-DD.md"
```

**DO NOT**:
- ❌ Wait for user to ask you to validate
- ❌ Ask user to launch validator
- ❌ Skip validation
- ❌ Mark task as done before validator approval

**Never**:
- ❌ **NEVER TOUCH OTHER AGENTS' WORK** — If you see compilation/test errors in files you didn't create, STOP and wait for that agent to fix them. DO NOT edit, fix, or modify any files outside your current task scope
- ❌ Commit/push without explicit user permission
- ❌ Mark task as `done` before validation approval
- ❌ Skip setting task status to `in-progress` at start
- ❌ Break parity or leave failing tests
- ❌ **NEVER skip automatic validator launch** — It's YOUR job, not user's

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

**Executor (YOU MUST DO THIS YOURSELF)**:
```bash
# 1. Complete implementation + tests
swift build && swift test

# 2. Create validation request
cat > .validation/requests/validate-feature-$(date +%Y-%m-%d).md <<EOF
# Validation Request — Feature Name
[see .validation/QUICKSTART.md for template]
EOF

# 3. 🤖 AUTOMATICALLY launch validator agent using Task tool:
# DO NOT wait for user - launch it immediately yourself!
```

**How to launch validator agent**:
```
Use Task tool with parameters:
- subagent_type: "validator"
- description: "Validate Task X implementation"
- prompt: "Review validation request at .validation/requests/validate-TASK-YYYY-MM-DD.md
and verify 100% upstream parity for all implemented features"
```

**Validator agent** automatically:
1. Reads validation request
2. Compares Swift vs TypeScript source
3. Runs tests, checks coverage
4. Generates report in `.validation/reports/`
5. Documents verdict: ✅ APPROVED / ⚠️ ISSUES / ❌ REJECTED

**🚨 IMPORTANT**: You launch the validator. User does NOT need to ask or remind you.

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

**File naming** (check upstream package location):
```
TypeScript: external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
Swift:      Sources/AISDKProviderUtils/Delay.swift
Tests:      Tests/AISDKProviderUtilsTests/DelayTests.swift

TypeScript: external/vercel-ai-sdk/packages/provider/src/language-model/v3/language-model-v3.ts
Swift:      Sources/AISDKProvider/LanguageModel/V3/LanguageModelV3.swift
Tests:      Tests/AISDKProviderTests/LanguageModelV3Tests.swift

TypeScript: external/vercel-ai-sdk/packages/ai/src/generate-text/generate-text.ts
Swift:      Sources/SwiftAISDK/GenerateText/GenerateText.swift
Tests:      Tests/SwiftAISDKTests/GenerateText/GenerateTextTests.swift
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
**Packages**:
- `provider` → `Sources/AISDKProvider/`
- `provider-utils` → `Sources/AISDKProviderUtils/`
- `ai` → `Sources/SwiftAISDK/`

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

**✅ Completed** (763/763 tests passing):
- **AISDKProvider Package** (78 files, ~210 tests):
  - LanguageModelV2/V3 protocols & types
  - EmbeddingModel, ImageModel, SpeechModel, TranscriptionModel V2/V3
  - Provider errors (26 types)
  - JSONValue universal JSON type
  - Middleware protocols

- **AISDKProviderUtils Package** (35 files, ~200 tests):
  - HTTP utilities (GET/POST, headers, retries)
  - JSON parsing, schema validation
  - Tool definitions
  - Data handling, utilities

- **SwiftAISDK Package** (105 files, ~300 tests):
  - Prompt conversion & standardization
  - Tool execution framework
  - Provider registry, middleware
  - Mock models for testing

- **EventSourceParser** (2 files, 30 tests)

**🚧 Next Priorities** (see Task Master):
- Block E: Generate/Stream Text core functionality
- Block F: Text/UI streams
- Provider implementations (OpenAI, Anthropic, etc.)

**Stats**: ~14,300 lines, 220 files, 3 packages, 100% upstream parity maintained

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
5. **🤖 YOU launch validator agent** — After creating validation request, immediately use Task tool to launch validator agent. DO NOT wait for user to ask. This is YOUR responsibility, not user's
6. **Mark done ONLY after validation** — Never mark complete before validator approval
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
- 🚨 **NEVER commit `.sessions/` or `.validation/` to git** — These are temporary artifacts, fully gitignored
- 🚨 **🤖 YOU LAUNCH VALIDATOR** — After creating validation request, immediately use Task tool to launch validator agent. DO NOT wait for user. DO NOT ask user. This is YOUR automatic responsibility!
- ✅ **Set task status to `in-progress` at start**
- ✅ Port ALL upstream tests, not just some
- ✅ **Automatically launch validator agent after creating validation request** — Use Task tool, don't wait
- ✅ **Mark task `done` ONLY after validation approval**
- ✅ **Commit ONLY when user explicitly requests**
- ✅ Add upstream references to every file
- ✅ Document adaptations with rationale
- ✅ Save session context for multi-session tasks ("Зафиксируй контекст")
- ❌ Don't skip edge case tests
- ❌ Don't commit without explicit user permission
- ❌ Don't mark task complete before validation
- ❌ Don't wait for user to remind you to validate
- ❌ Don't ask user to launch validator agent
- ❌ Don't leave old session contexts after completion
- ❌ **NEVER fix compilation errors in other agents' files**
- ❌ **NEVER git add/commit temporary directories** (`.sessions/`, `.validation/`)

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

*Last updated: 2025-10-13*
