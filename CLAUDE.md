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

## Git Worktree Workflow (Multi-Agent Isolation)

**🚨 CRITICAL for Parallel Agents**: Use Git worktrees to isolate agents working simultaneously.

**Concept**: Each agent works in **separate directory** with **own branch** - no file conflicts!

```
/Users/teunlao/projects/public/
├── swift-ai-sdk/              # Main (main branch)
├── swift-ai-sdk-executor-1/   # Agent 1 (executor-1 branch)
└── swift-ai-sdk-executor-2/   # Agent 2 (executor-2 branch)
```

**Benefits:**
- ✅ Full isolation - agents can't touch each other's files
- ✅ Independent builds - `swift build` doesn't conflict
- ✅ Parallel testing - `swift test` runs simultaneously
- ✅ Easy merge - `git merge executor-1` after validation

**Quick Start:**
```bash
# Create worktree for agent
git worktree add ../swift-ai-sdk-executor-1 -b executor-1-task-X

# Launch agent with cwd in worktree
"cwd": "/Users/teunlao/projects/public/swift-ai-sdk-executor-1"

# After validation - merge to main
git merge executor-1-task-X

# Cleanup
git worktree remove ../swift-ai-sdk-executor-1
```

**📖 Full Guide**: `docs/worktree-workflow.md` - complete rules, scenarios, troubleshooting

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

## MCP Background Execution

**When to use**: Long-running MCP operations (e.g., Codex with complex prompts, research tasks).

**🚨 CRITICAL for Codex MCP**: Always include these parameters in JSON:
```json
{
  "arguments": {
    "prompt": "...",
    "cwd": "/path",
    "approval-policy": "never",
    "sandbox": "danger-full-access"
  }
}
```

**Without these, Codex will prompt for approval and block!** See `docs/codex-sandbox-permissions.md` for details.

### ✅ Correct: Native Background Task

**Visible in TUI**, full control via BashOutput/KillShell.

```bash
# 1. Create JSON request file (⚠️ must include approval-policy and sandbox!)
cat > /tmp/mcp-request.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"...","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# 2. Launch via STDIN redirect (NO & in command!)
Bash(
  command: "codex mcp-server < /tmp/mcp-request.json > /tmp/mcp-output.json 2>&1",
  run_in_background: true,
  timeout: 600000  # 10 min for long ops
)
# → Returns hex ID (e.g., "81728d") - visible in TUI!

# 3. Check status
BashOutput(bash_id: "81728d")

# 4. Read detailed output (🚨 USE PARSE SCRIPT for token efficiency!)
python3 scripts/parse-codex-output.py /tmp/mcp-output.json --last 100 --reasoning
# ✅ ALWAYS use parse script FIRST - saves massive tokens!

# Alternative: Raw file (only if parse script insufficient)
# tail -f /tmp/mcp-output.json  # ⚠️ Wastes tokens!
```

**Key indicators of native task**:
- ✅ Hex ID format (`81728d`, not `872747`)
- ✅ Visible in user's TUI
- ✅ BashOutput shows status/output
- ✅ KillShell can terminate

### ❌ NEVER Use & Operator

**NOT compatible with Claude Code!**

```bash
# ❌ NEVER DO THIS - & operator doesn't work in Claude Code!
Bash(
  command: "codex mcp-server < input.json > output.json 2>&1 &",
  run_in_background: true
)
```

**Why it's wrong**:
- ❌ NOT compatible with Claude Code
- ❌ NOT visible in user's TUI
- ❌ BashOutput/KillShell don't work
- ❌ No proper lifecycle management

### Rules

1. **🚨 ALWAYS use `run_in_background: true`** — ONLY method for Claude Code
2. **NEVER use `&` operator** — not compatible with Claude Code
3. **Always use file + redirect** — `< input.json > output.json 2>&1`
4. **Set timeout for long ops** — default 2 min may be too short
5. **Verify hex ID format** — confirms native task (e.g., "9de576")

### Interactive Sessions (Advanced)

For **persistent MCP sessions** with multiple commands:

**🚨 ALWAYS use Claude Code native background task:**

```python
# 1. Launch (ALWAYS use run_in_background parameter!)
Bash("touch /tmp/commands.jsonl")
task_id = Bash(
    command="tail -f /tmp/commands.jsonl | codex mcp-server > /tmp/output.json 2>&1",
    run_in_background=True,  # ✅ ALWAYS use this!
    timeout=3600000  # 1 hour
)
# → Hex ID (e.g., "9de576") - visible in TUI!

# 2. Send commands
Bash("echo '{...id:1...}' >> /tmp/commands.jsonl")
Bash("echo '{...id:2...}' >> /tmp/commands.jsonl")
```

**NEVER use `&` operator** - only `run_in_background: true` is compatible with Claude Code!

**Use cases**: Multi-step workflows, iterative debugging, stateful interactions.

**🚨 Token Efficiency**: ALWAYS read Codex output via `scripts/parse-codex-output.py` - dramatically reduces token usage by filtering noise. See `docs/monitoring-codex-output.md`.

**See**: `docs/interactive-mcp-sessions.md` for complete guide, `docs/native-background-tasks.md` for basics.

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

### Multi-Agent Development
- `docs/worktree-workflow.md` — Git worktrees for agent isolation
- `docs/multi-agent-coordination.md` — Agent coordination patterns
- `docs/native-background-tasks.md` — Background task basics
- `docs/interactive-mcp-sessions.md` — Persistent MCP sessions
- `docs/monitoring-codex-output.md` — Output analysis
- `docs/codex-sandbox-permissions.md` — Autonomous mode

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
