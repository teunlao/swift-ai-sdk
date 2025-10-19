# Native Background Tasks in Claude Code

**Purpose**: True background tasks vs subprocess execution

---

## ❌ Wrong: Using `&` Operator

```python
Bash(command="codex mcp-server ... &", run_in_background=True)
```

**Problems:**
- Shell ID: numeric (`872747`) not hex
- NOT visible in user's TUI
- BashOutput/KillShell don't work properly
- Process runs outside Claude Code control

---

## ✅ Correct: Native Background Task

### Basic Pattern

```python
Bash(
    command="codex mcp-server < /tmp/input.json > /tmp/output.json 2>&1",
    run_in_background=True,  # ✅ KEY!
    timeout=600000  # 10 min
)
# → Returns hex ID (e.g., "336ae0")
```

### Key Rules

1. ✅ **MUST** use `run_in_background: true`
2. ❌ **NEVER** use `&` at end of command
3. ✅ Use redirects: `< input > output 2>&1`
4. ✅ Set timeout for long ops (default 2min may be too short)

### Result

- **Shell ID**: hex format (`336ae0`)
- **Visible in TUI**: Yes
- **BashOutput**: Works
- **KillShell**: Works

---

## Quick Comparison

| Feature | `&` operator | `run_in_background` |
|---------|-------------|---------------------|
| ID format | Number | Hex |
| TUI visible | ❌ No | ✅ Yes |
| BashOutput | ⚠️ Broken | ✅ Works |
| KillShell | ❌ Broken | ✅ Works |

---

## Complete Example

### 1. Prepare Request

```bash
cat > /tmp/request.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Task here","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
```

⚠️ **CRITICAL**: Always include `approval-policy` and `sandbox` params!
See [codex-sandbox-permissions.md](./codex-sandbox-permissions.md)

### 2. Launch

```python
task_id = Bash(
    command="codex mcp-server < /tmp/request.json > /tmp/output.json 2>&1",
    run_in_background=True,
    timeout=600000
)
# → Returns: "336ae0"
```

### 3. Monitor

**Use parse script (saves tokens!):**
```python
Bash("python3 scripts/parse-codex-output.py /tmp/output.json --stuck")
Bash("python3 scripts/parse-codex-output.py /tmp/output.json --last 50 --reasoning")
```

**Check status:**
```python
BashOutput(bash_id="336ae0")
```

### 4. Stop

```python
KillShell(shell_id="336ae0")
```

---

## Common Mistakes

### Mistake 1: Using `&` with `run_in_background`

```python
# ❌ WRONG
Bash(command="task &", run_in_background=True)

# ✅ CORRECT
Bash(command="task", run_in_background=True)
```

### Mistake 2: No timeout for long ops

```python
# ❌ WRONG - default 2min may be too short
Bash(command="codex ...", run_in_background=True)

# ✅ CORRECT
Bash(command="codex ...", run_in_background=True, timeout=600000)
```

### Mistake 3: Missing redirects

```python
# ❌ WRONG - no input/output
command="codex mcp-server"

# ✅ CORRECT
command="codex mcp-server < input.json > output.json 2>&1"
```

---

## Technical Details

### Shell ID Formats

- **Subprocess** (`&`): Decimal (`872747`)
- **Native**: Hexadecimal (`336ae0`)

**If you see hex ID → native task (correct!)**

### Process Hierarchy

**Subprocess:**
```
Bash Tool → Shell → Process & (detached)
```

**Native:**
```
Bash Tool → Background Task (managed by Claude Code)
```

---

## Related Docs

- [interactive-mcp-sessions.md](./interactive-mcp-sessions.md) - Persistent sessions with `tail -f`
- [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) - Autonomous mode params
- [monitoring-codex-output.md](./monitoring-codex-output.md) - Output analysis

---

**Last updated**: 2025-10-14
