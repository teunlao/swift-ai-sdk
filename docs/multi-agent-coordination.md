# Multi-Agent Coordination Guide

**Date**: 2025-10-13
**Version**: 1.0
**Role**: Claude Code as Agent Coordinator/Dispatcher

---

## Overview

This document describes how **Claude Code (Sonnet 4.5)** acts as a **coordinator/dispatcher** for managing multiple parallel Codex MCP agents for complex development tasks.

**Architecture**:
```
┌─────────────────────────────────────────────────────────────┐
│              Claude Code (Coordinator/Dispatcher)            │
│  - Analyzes tasks and dependencies                          │
│  - Launches parallel agents with proper naming              │
│  - Monitors progress via parse scripts                      │
│  - Validates results before commit                          │
│  - Updates Task Master                                      │
└──────────┬──────────────┬──────────────┬────────────────────┘
           │              │              │
    ┌──────▼──────┐ ┌────▼─────┐ ┌─────▼──────┐
    │ executor-1  │ │executor-2│ │ executor-3 │
    │  Task 2.5   │ │ Task 2.2 │ │  Task 3.1  │
    └─────────────┘ └──────────┘ └────────────┘
```

---

## Critical Rule: Role-Based Naming

**ALWAYS** use role-based naming for agents, **NEVER** task-based naming.

---

## Naming Pattern

```
<role>-<number>
```

### Components

- **role**: Type of agent (executor, validator, analyzer)
- **number**: Sequential number (1, 2, 3, etc.)

---

## Role Types

| Role | Purpose | Examples |
|------|---------|----------|
| **executor** | Implementation agents | executor-1, executor-2, executor-3 |
| **validator** | Validation agents | validator-1, validator-2 |
| **analyzer** | Analysis agents | analyzer-1 |

---

## File Naming Convention

### Command Buffers

```bash
/tmp/codex-executor-1-commands.jsonl
/tmp/codex-executor-2-commands.jsonl
/tmp/codex-executor-3-commands.jsonl
/tmp/codex-validator-1-commands.jsonl
```

### Output Files

```bash
/tmp/codex-executor-1-output.json
/tmp/codex-executor-2-output.json
/tmp/codex-executor-3-output.json
/tmp/codex-validator-1-output.json
```

### Shell IDs

Native background tasks return hex IDs (e.g., `9f865e`, `14e03a`).

Store mapping in session docs:
```markdown
- executor-1: Shell ID 9f865e
- executor-2: Shell ID 14e03a
- validator-1: Shell ID 134866
```

---

## Examples

### ✅ CORRECT

```bash
# Launch executor-1
touch /tmp/codex-executor-1-commands.jsonl
tail -f /tmp/codex-executor-1-commands.jsonl | \
  codex mcp-server > /tmp/codex-executor-1-output.json 2>&1

# Launch executor-2
touch /tmp/codex-executor-2-commands.jsonl
tail -f /tmp/codex-executor-2-commands.jsonl | \
  codex mcp-server > /tmp/codex-executor-2-output.json 2>&1

# Launch validator-1
touch /tmp/codex-validator-1-commands.jsonl
tail -f /tmp/codex-validator-1-commands.jsonl | \
  codex mcp-server > /tmp/codex-validator-1-output.json 2>&1
```

### ❌ WRONG

```bash
# DON'T use task-specific names
/tmp/codex-task-1-11-commands.jsonl  # ❌
/tmp/codex-task-6-1-output.json      # ❌

# DON'T use ambiguous names
/tmp/codex-agent-2-commands.jsonl    # ❌ (no role)
/tmp/codex-session-3-output.json     # ❌ (no role)
```

---

## Why Role-Based Naming?

### 1. Clarity

Immediately understand agent's purpose:
- `executor-1` → Implementation agent #1
- `validator-1` → Validation agent #1

### 2. Scalability

Easy to add more agents:
```bash
executor-1, executor-2, executor-3, executor-4...
validator-1, validator-2...
```

### 3. Documentation

Logs reference clear roles:
```markdown
## Active Agents
- executor-1: Working on Task 2.3
- executor-2: Working on Task 5.1
- validator-1: Validating Task 6.1
```

### 4. Reusability

Same agent can work on multiple tasks sequentially:
```markdown
executor-1:
  - Task 1.11 ✅ (completed)
  - Task 2.5 🔄 (in progress)
```

### 5. Session Management

Easy to track and kill agents:
```bash
# Check all executors
python3 scripts/parse-codex-output.py /tmp/codex-executor-*.json --stuck

# Kill specific agent
pkill -f "tail -f /tmp/codex-executor-2-commands.jsonl"
```

---

## Session Documentation

### Template

```markdown
## Active Agents

### executor-1
- **Shell ID**: 9f865e
- **Started**: 2025-10-13 22:49
- **Task**: Task 2.5 - Provider tool factory
- **Files**: `/tmp/codex-executor-1-*.json*`
- **Status**: 🔄 In progress

### executor-2
- **Shell ID**: 14e03a
- **Started**: 2025-10-13 22:54
- **Task**: Task 2.2 - Convert stream utilities
- **Files**: `/tmp/codex-executor-2-*.json*`
- **Status**: 🔄 In progress

### validator-1
- **Shell ID**: 134866
- **Started**: 2025-10-13 22:59
- **Task**: Validating Task 6.1
- **Files**: `/tmp/codex-validator-1-*.json*`
- **Status**: ✅ Completed
```

---

## Migration from Old Naming

If you have old task-based names, document the mapping:

```markdown
## Legacy Name Mapping

Old naming (deprecated):
- codex-task-1-11-* → executor-1
- codex-task-6-1-* → executor-2
- codex-validator-* → validator-1
```

---

## Quick Reference

**Launch executor:**
```bash
touch /tmp/codex-executor-N-commands.jsonl
tail -f /tmp/codex-executor-N-commands.jsonl | \
  codex mcp-server > /tmp/codex-executor-N-output.json 2>&1
# (run_in_background: true)
```

**Launch validator:**
```bash
touch /tmp/codex-validator-N-commands.jsonl
tail -f /tmp/codex-validator-N-commands.jsonl | \
  codex mcp-server > /tmp/codex-validator-N-output.json 2>&1
# (run_in_background: true)
```

**Monitor:**
```bash
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --last 50 --reasoning
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --stuck
```

---

## Coordinator Responsibilities

### 1. Task Analysis & Assignment

**Goal**: Find independent tasks that can run in parallel without conflicts.

**Process**:
```bash
# Check Task Master for pending tasks
mcp__taskmaster__get_tasks --status=pending --withSubtasks=true

# Analyze dependencies
mcp__taskmaster__get_task --id=X

# Verify no file conflicts with active agents
```

**Selection Criteria**:
- ✅ No dependencies OR all dependencies completed
- ✅ Clear upstream reference
- ✅ Different files from other agents
- ✅ Testable outcome

---

### 2. Agent Launch

**Pattern - Interactive Session**:
```python
# 1. Create command buffer
Bash("touch /tmp/codex-executor-N-commands.jsonl")

# 2. Launch as native background task
task_id = Bash(
    command="tail -f /tmp/codex-executor-N-commands.jsonl | codex mcp-server > /tmp/codex-executor-N-output.json 2>&1",
    run_in_background=True,  # ✅ ALWAYS use this!
    timeout=7200000  # 2 hours
)
# → Returns hex ID (e.g., "9f865e")

# 3. Send task (🚨 CRITICAL: Proper JSONL format!)
Bash("""
cat > /tmp/executor-task.json <<'JSONEOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"YOUR TASK HERE","cwd":"/path/to/project","approval-policy":"never","sandbox":"danger-full-access"}}}
JSONEOF
cat /tmp/executor-task.json >> /tmp/codex-executor-N-commands.jsonl
""")
```

**Critical Parameters** (ALWAYS required):
- `"approval-policy": "never"` - Autonomous execution
- `"sandbox": "danger-full-access"` - Full file system access
- `"cwd"` - Absolute path to project

---

### 2.1. 🚨 CRITICAL: JSONL Format Requirements

**JSONL = JSON Lines = ONE LINE per JSON object**

**❌ WRONG - Multiline heredoc (BREAKS MCP server!):**

```bash
# ❌ DON'T DO THIS - JSON splits into multiple lines!
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{
  "prompt":"YOUR TASK HERE",
  "cwd":"/path",
  "approval-policy":"never",
  "sandbox":"danger-full-access"
}}}
EOF
```

**Why this BREAKS:**
- JSONL requires **ONE line = ONE JSON object**
- Heredoc creates **MULTIPLE lines** in file
- `tail -f` sends incomplete JSON → **MCP server IGNORES or CRASHES**

**✅ CORRECT - Single line JSON:**

**Method 1: Create JSON file first, then append as ONE line (RECOMMENDED)**

```bash
# 1. Create valid JSON in temp file
cat > /tmp/command.json <<'JSONEOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"YOUR TASK HERE","cwd":"/path/to/project","approval-policy":"never","sandbox":"danger-full-access"}}}
JSONEOF

# 2. Append as SINGLE LINE
cat /tmp/command.json >> /tmp/codex-executor-N-commands.jsonl
```

**Verification:**

```bash
# Check last command is valid JSON
tail -1 /tmp/codex-commands.jsonl | python3 -m json.tool > /dev/null && echo "✅ Valid" || echo "❌ Invalid"
```

**Key Rules:**
1. 🔴 **NEVER use heredoc for appending** to JSONL files
2. ✅ **Always create temp file first**, then append
3. ✅ **Test with json.tool** before sending
4. 🔴 **ONE line = ONE command** (no exceptions!)

---

### 3. Progress Monitoring

**🚨 ALWAYS use parse script for token efficiency!**

```bash
# Check if stuck (most important!)
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --stuck

# Recent reasoning
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --last 50 --reasoning

# Commands executed
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --commands | tail -20

# Final messages
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --messages | tail -10
```

**Warning Signs**:
- 🔴 Stuck detection triggers → Send clarification or restart
- 🔴 No commands executing → Agent only thinking
- 🔴 Token usage > 2M → Consider restarting with fresh context
- 🔴 Repeated errors → Wrong approach, need intervention

---

### 4. Validation Workflow

**When to Validate**: After executor completes implementation and creates validation request.

**Launch Validator**:
```python
# Launch validator-1
Bash("touch /tmp/codex-validator-1-commands.jsonl")
task_id = Bash(
    command="tail -f /tmp/codex-validator-1-commands.jsonl | codex mcp-server > /tmp/codex-validator-1-output.json 2>&1",
    run_in_background=True,
    timeout=3600000
)

# Send validation task (🚨 CRITICAL: Use proper JSONL format!)
Bash("""
cat > /tmp/validator-cmd.json <<'JSONEOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"VALIDATOR ROLE: Validate Task X.Y\\n\\nREAD validation request: .validation/requests/validate-task-X.Y-*.md\\n\\nEXECUTE these steps (don't just describe!):\\n1. Read Swift implementation\\n2. Read TypeScript upstream\\n3. Compare line-by-line (all functions? all edge cases?)\\n4. Read tests (all test cases ported?)\\n5. Run: swift build && swift test --filter Tests\\n6. Create report: /tmp/validation-task-X-Y.md\\n7. Verdict: APPROVED or REJECTED\\n\\nBe critical. 100% parity required.","cwd":"/path/to/project","approval-policy":"never","sandbox":"danger-full-access"}}}
JSONEOF
cat /tmp/validator-cmd.json >> /tmp/codex-validator-1-commands.jsonl
""")
```

---

### 5. Session Documentation

**Create session file** (e.g., `.sessions/session-2025-10-13-multi-agent.md`):

```markdown
# Multi-Agent Session

**Date**: 2025-10-13
**Coordinator**: Claude Code

## Active Agents

### executor-1
- **Shell ID**: 9f865e
- **Task**: Task 2.5 - Provider tool factory
- **Files**: Sources/AISDKProviderUtils/Tool.swift
- **Status**: 🔄 In progress
- **Started**: 22:49

### executor-2
- **Shell ID**: 14e03a
- **Task**: Task 2.2 - Convert stream utilities
- **Files**: Sources/SwiftAISDK/Util/ConvertStream.swift
- **Status**: 🔄 In progress
- **Started**: 22:54

### validator-1
- **Shell ID**: 134866
- **Task**: Validating Task 6.1
- **Status**: ✅ Completed - APPROVED
- **Started**: 22:59
- **Completed**: 23:15
```

---

## Common Patterns

### Pattern 1: Parallel Implementation

```bash
# Identify 3 independent tasks
Task 2.5: Provider tool factory (no deps)
Task 2.2: Convert stream utils (no deps)
Task 3.1: Async helpers (no deps)

# Launch 3 executors in parallel
for N in 1 2 3; do
  # Launch executor-N
  # Send task-specific prompt
  # Monitor via parse script
done

# Result: 3x faster implementation!
```

### Pattern 2: Sequential Validation

```bash
# After executors complete
executor-1: ✅ Implementation done → Launch validator-1
executor-2: ✅ Implementation done → Launch validator-2

# Wait for approvals
validator-1: ✅ APPROVED → Commit files
validator-2: ❌ REJECTED → Send fixes to executor-2
```

### Pattern 3: Stuck Agent Recovery

```bash
# Detect stuck agent
python3 scripts/parse-codex-output.py /tmp/codex-executor-2-output.json --stuck
# → ⏸️  POSSIBLY STUCK

# Send clarification (🚨 Use proper JSONL format!)
cat > /tmp/clarify.json <<'JSONEOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"STOP ANALYZING. Start implementing NOW. Create the Swift file.","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
JSONEOF
cat /tmp/clarify.json >> /tmp/codex-executor-2-commands.jsonl

# If still stuck after 2 attempts → Kill and restart
KillShell(shell_id="14e03a")
```

---

## Best Practices

### DO ✅

1. **Use parse script FIRST** - saves massive tokens
   ```bash
   python3 scripts/parse-codex-output.py FILE --stuck
   python3 scripts/parse-codex-output.py FILE --last 50 --reasoning
   ```

2. **Monitor every 30-60 seconds** during active work
3. **Document shell IDs** in session file immediately
4. **Use role-based naming** (executor-N, validator-N)
5. **Kill completed agents** to free resources
6. **Validate before commit** - no exceptions
7. **Send explicit commands** to validators ("EXECUTE, don't describe!")

### DON'T ❌

1. **Never read raw JSON directly** - always use parse script
2. **Never use task-based naming** (codex-task-X-Y)
3. **Never commit without validation** approval
4. **Never touch files** from other agents' tasks
5. **Never use `&` operator** - use `run_in_background: true`
6. **Never skip stuck detection** - check regularly

---

## Token Efficiency

**Parse Script Benefits**:
- ✅ Filters noise (delta events, metadata)
- ✅ Human-readable output
- ✅ Smart stuck detection
- ✅ **Saves 90%+ tokens** vs raw JSON

**Example**:
```bash
# ❌ BAD: Raw file (wastes ~50K tokens)
tail -1000 /tmp/codex-executor-1-output.json

# ✅ GOOD: Parse script (~2K tokens)
python3 scripts/parse-codex-output.py /tmp/codex-executor-1-output.json --last 100 --reasoning
```

---

## Quick Reference Card

```bash
# Launch executor
touch /tmp/codex-executor-N-commands.jsonl
tail -f /tmp/codex-executor-N-commands.jsonl | codex mcp-server > /tmp/codex-executor-N-output.json 2>&1
# (run_in_background: true, timeout: 7200000)

# Send task (🚨 CRITICAL: Use temp file method for JSONL!)
cat > /tmp/cmd.json <<'JSONEOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"TASK","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
JSONEOF
cat /tmp/cmd.json >> /tmp/codex-executor-N-commands.jsonl

# Verify command is valid
tail -1 /tmp/codex-executor-N-commands.jsonl | python3 -m json.tool > /dev/null && echo "✅ Valid"

# Monitor (USE PARSE SCRIPT!)
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --stuck
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --last 50 --reasoning

# Kill when done
KillShell(shell_id="hex-id")
```

---

## Related Documentation

- `docs/codex-sandbox-permissions.md` - Autonomous mode parameters
- `docs/interactive-mcp-sessions.md` - Persistent sessions
- `docs/monitoring-codex-output.md` - Parse script details
- `docs/native-background-tasks.md` - Background task basics
- `.sessions/session-*.md` - Session examples

---

**Author**: Claude Code (Sonnet 4.5)
**Role**: Multi-Agent Coordinator/Dispatcher
**Last Updated**: 2025-10-13
