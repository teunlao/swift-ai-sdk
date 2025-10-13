# Multi-Agent Coordination Guide

**Role**: Claude Code as Agent Coordinator/Dispatcher

---

## Overview

Claude Code coordinates multiple parallel Codex MCP agents:

```
Claude Code (Coordinator)
  ├─> executor-1 (Task 2.5)
  ├─> executor-2 (Task 2.2)
  └─> validator-1 (Validation)
```

---

## Critical Rule: Role-Based Naming

**Pattern**: `<role>-<number>`

### Roles

| Role | Purpose |
|------|---------|
| `executor-N` | Implementation agents |
| `validator-N` | Validation agents |
| `analyzer-N` | Analysis agents |

### File Naming

```bash
/tmp/codex-executor-1-commands.jsonl
/tmp/codex-executor-1-output.json
/tmp/codex-executor-2-commands.jsonl
/tmp/codex-executor-2-output.json
/tmp/codex-validator-1-commands.jsonl
/tmp/codex-validator-1-output.json
```

**Why role-based?**
- Clear purpose immediately visible
- Easy to scale (executor-1, 2, 3...)
- Simple documentation
- Agent reusability (same agent, multiple tasks)

---

## Quick Reference

### Launch Executor

```bash
touch /tmp/codex-executor-N-commands.jsonl

Bash(
    command="tail -f /tmp/codex-executor-N-commands.jsonl | codex mcp-server > /tmp/codex-executor-N-output.json 2>&1",
    run_in_background=True,
    timeout=7200000
)

# Send task (create temp file first!)
cat > /tmp/cmd.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"TASK","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
cat /tmp/cmd.json >> /tmp/codex-executor-N-commands.jsonl
```

### Monitor

```bash
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --stuck
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --last 50 --reasoning
```

---

## 🚨 CRITICAL: JSONL Format

**JSONL = ONE line per JSON object**

### ❌ WRONG (multiline heredoc)

```bash
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{
  "prompt":"TASK",
  "cwd":"/path"
}}}
EOF
```

**Breaks MCP server!** (multiple lines → incomplete JSON)

### ✅ CORRECT (temp file method)

```bash
# 1. Create JSON in temp file
cat > /tmp/cmd.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"TASK","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# 2. Append as SINGLE line
cat /tmp/cmd.json >> /tmp/codex-commands.jsonl

# 3. Verify
tail -1 /tmp/codex-commands.jsonl | python3 -m json.tool > /dev/null && echo "✅ Valid"
```

---

## Coordinator Workflow

### 1. Task Selection

```bash
# Find independent tasks
mcp__taskmaster__get_tasks --status=pending --withSubtasks=true

# Verify no file conflicts
mcp__taskmaster__get_task --id=X
```

**Criteria:**
- No dependencies OR all deps completed
- Different files from other agents
- Clear upstream reference

### 2. Launch Agents

Create buffer → Launch session → Send task (with autonomous params!)

### 3. Monitor Progress

```bash
python3 scripts/parse-codex-output.py FILE --stuck
python3 scripts/parse-codex-output.py FILE --last 50 --reasoning
```

**Warning signs:**
- 🔴 Stuck detection triggers
- 🔴 No commands for >10 min
- 🔴 Token usage > 2M
- 🔴 Repeated errors

### 4. Validate

Launch validator after executor completes:

```bash
# Validator task
cat > /tmp/val.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"VALIDATOR ROLE: Validate Task X\\n\\n1. Read Swift\\n2. Read TypeScript\\n3. Compare line-by-line\\n4. Run tests\\n5. Verdict: APPROVED/REJECTED","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
cat /tmp/val.json >> /tmp/codex-validator-1-commands.jsonl
```

---

## Best Practices

### DO ✅

1. **Use parse script** - saves 90%+ tokens
2. **Monitor every 30-60s** during active work
3. **Document shell IDs** in session file
4. **Use role-based naming**
5. **Kill completed agents**
6. **Validate before commit**

### DON'T ❌

1. **Never read raw JSON** - use parse script
2. **Never use task-based naming** (codex-task-X-Y)
3. **Never commit without validation**
4. **Never use `&` operator** - use `run_in_background: true`
5. **Never skip stuck detection**

---

## Common Patterns

### Parallel Implementation

```bash
# Launch 3 executors for independent tasks
for N in 1 2 3; do
  touch /tmp/codex-executor-$N-commands.jsonl
  # Launch each...
done
```

### Stuck Recovery

```bash
python3 scripts/parse-codex-output.py FILE --stuck
# → ⏸️  POSSIBLY STUCK

# Send clarification
cat > /tmp/clarify.json <<'EOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"STOP ANALYZING. Start implementing NOW.","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
cat /tmp/clarify.json >> /tmp/codex-executor-N-commands.jsonl

# If still stuck → Kill and restart
KillShell(shell_id="hex-id")
```

---

## Related Docs

- [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) - Autonomous params
- [interactive-mcp-sessions.md](./interactive-mcp-sessions.md) - Persistent sessions
- [monitoring-codex-output.md](./monitoring-codex-output.md) - Parse script
- [native-background-tasks.md](./native-background-tasks.md) - Background basics
- [worktree-workflow.md](./worktree-workflow.md) - Git isolation

---

**Last Updated**: 2025-10-14
