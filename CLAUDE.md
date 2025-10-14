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

### Executor Role (Codex Agent)
**Implement features, write tests, create validation request.**

Executor agent workflow:
1. Receive task via prompt from orchestrator
2. Find TypeScript in `external/vercel-ai-sdk/packages/`
3. Port to appropriate Swift package
4. Port ALL upstream tests
5. Run `swift build && swift test` (must pass 100%)
6. Create validation request in `.validation/requests/validate-TASK-YYYY-MM-DD.md`
7. **Stop and wait** - orchestrator will handle validation workflow

**🚨 CRITICAL Rules for Executor Agents**:
- ❌ **NEVER TOUCH OTHER AGENTS' WORK** — Only edit files in your task scope
- ✅ Create `.validation/requests/*.md` file and stop
- ❌ Do NOT call MCP tools (agents can't - only orchestrator can)
- ❌ Do NOT launch validator (orchestrator does this)

### Validator Role (Codex Agent)
**Review implementation, compare with upstream, generate report.**

Validator agent workflow:
1. Receive validation request path via prompt
2. Read `.validation/requests/*.md` file
3. Examine implementation files
4. Compare with upstream TypeScript (line-by-line)
5. Verify ALL tests ported
6. Create `.validation/reports/report-*.md` with verdict (APPROVED/REJECTED)
7. **Stop and wait** - orchestrator will handle status updates

**🚨 CRITICAL Rules for Validator Agents**:
- ✅ Work in executor's worktree (same directory)
- ✅ Check EVERY requirement from validation scope
- ✅ Be thorough - reject if ANY issue found
- ❌ Do NOT call MCP tools (agents can't - only orchestrator can)

### Orchestrator Workflow (Your Role)
**🚨 YOU MUST ACTIVELY MONITOR AND EXECUTE THIS WORKFLOW - NOT PASSIVE!**

**NON-NEGOTIABLE VALIDATION RULE:** Execute the full validation workflow for 100% of tasks—every single one. The ONLY time you may skip validation is when the user explicitly says exactly `skip validation` or `no validation needed`. Any other wording still requires full validation, regardless of urgency or perceived scope.

**STEP 1: Launch Executor**
```
launch_agent(role='executor', worktree='auto', prompt='...')
```
→ Returns `agent_id` (e.g., executor-1760461163346)
→ Agent starts working

**STEP 2: MONITOR Executor Until Completion**

**STEP 3: IMMEDIATELY Call request_validation() - DON'T WAIT FOR USER!**
```
request_validation(executor_id=executor_id, summary='...')
```
→ Returns `validation_id`
→ Executor status → 'blocked'
→ **DO THIS AS SOON AS EXECUTOR FINISHES, NOT WHEN USER ASKS!**

**STEP 4: Launch Validator in Executor's Worktree**
```
# Get executor's worktree from status() or validation session
launch_agent(
  role='validator',
  worktree='manual',
  cwd='/path/to/executor-worktree',
  prompt='Validate executor work...'
)
```
→ Returns `validator_id`

**STEP 5: Assign Validator to Validation Session**
```
assign_validator(validation_id=validation_id, validator_id=validator_id)
```
→ Links validator to session
→ Session status → 'in_progress'

**STEP 6: MONITOR Validator Until Completion**
→ Periodically check status() and get_logs() until validator completes
→ When `idle_minutes > 1` and validation report created, proceed to STEP 7

**STEP 7: IMMEDIATELY Call submit_validation() - DON'T WAIT FOR USER!**
```
submit_validation(
  validation_id=validation_id,
  result='approved' or 'rejected',
  report_path='.validation/reports/...'
)
```
→ If approved: executor status → 'validated', ready to merge
→ If rejected: executor status → 'needs_fix', must fix bugs
→ **DO THIS AS SOON AS VALIDATOR FINISHES, NOT WHEN USER ASKS!**

**STEP 8: If Approved - Merge; If Rejected - Continue Executor**

**If APPROVED:**
```bash
# 1. Commit changes in executor's worktree
cd /path/to/executor-worktree
git add .
git commit -m "feat: descriptive message

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

# 2. Merge executor branch to main
cd /main/repo/path
git merge agent/executor-TIMESTAMP --no-edit

# 3. Cleanup worktree
kill_agent(executor_id, cleanup_worktree=true)
```

**If REJECTED:**
```
continue_agent(executor_id, 'Fix bugs from validation report at .validation/reports/...')
# Then GO BACK TO STEP 2 and repeat cycle!
```

**🚨 CRITICAL RULES:**
1. **YOU ACTIVELY DRIVE THE WORKFLOW** - don't wait for user commands after each step
2. **MONITOR agents continuously** - check status/logs every 30-180s until completion
3. **IMMEDIATELY call MCP tools** when agent finishes (request_validation, submit_validation)
4. **DON'T ASK USER "what next?"** - you know the workflow, execute it!
5. **Validation is iterative** - rejected → fix → re-validate → repeat until approved
6. **Validation never skipped** - follow the mandate above unless the user literally says `skip validation` or `no validation needed`

**⏱️ SLEEP BEFORE MONITORING (MANDATORY):**
- **ALWAYS use sleep && before monitoring commands**
- Write as ONE Bash command: `sleep N && monitoring_command`
- Start with 30s, increase to 60s for complex tasks, up to 180s for very long tasks
- Examples:
  ```bash
  Bash: sleep 30 && status(agent_id="executor-123")
  Bash: sleep 60 && get_logs(agent_id="executor-123")
  Bash: sleep 120 && status(agent_id="executor-123")
  ```

**⚠️ WORKTREE MODE - MANDATORY DEFAULTS:**

**ALWAYS use these modes unless user EXPLICITLY requests otherwise:**

- **Executors:** `worktree="auto"` (creates isolated Git worktree + unique branch)
  - ✅ Use for: ALL executor tasks (Swift porting, bug fixes, features, tooling, docs, ANY code changes)
  - ✅ Isolation prevents conflicts between parallel agents
  - ❌ NEVER use `manual` unless user explicitly says "use manual mode"

- **Validators:** `worktree="manual"` + `cwd=executor_worktree` (works in executor's directory)
  - ✅ Use for: ALL validator tasks (must access executor's files)
  - ✅ Validator needs same directory to review executor's work
  - ❌ NEVER use `auto` for validators (creates separate worktree, can't access executor files)

**Examples of user requests that DO NOT override defaults:**
- "fix the CSS" → executor with `worktree="auto"` ✅
- "update the dashboard" → executor with `worktree="auto"` ✅
- "make this change" → executor with `worktree="auto"` ✅
- "попроси агента сделать X" → executor with `worktree="auto"` ✅

**Only override if user says:**
- "use manual mode" → executor with `worktree="manual"` ✅
- "work in main directory" → executor with `worktree="manual"` ✅
- "don't create worktree" → executor with `worktree="manual"` ✅

**Key point**: Agents create files, YOU orchestrate workflow with MCP commands.

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

1. **🚨 YOU orchestrate everything** — Agents create files, YOU call MCP commands for workflow
2. **Agents can't call MCP tools** — Only YOU can use orchestrator commands
3. **Validation is 3-step process** — request_validation → assign_validator → submit_validation
4. **Executor creates request file** — Then YOU call request_validation(executor_id)
5. **Validator creates report file** — Then YOU call submit_validation(validation_id, result)
6. **100% parity required** — Match TypeScript exactly, reject if ANY issue
7. **Never commit without permission** — Explicit user request required
8. **Worktree isolation** — Each executor gets own directory, validator shares it

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

**Integration**: Task Master for management, `.sessions/` for contexts, `.validation/` for validation.

**Files**: `.taskmaster/` gitignored, `.claude/commands/tm/` committed.

---

**Remember**: Every line must match upstream. Use validator agent for 100% parity.

*Last updated: 2025-10-14*
