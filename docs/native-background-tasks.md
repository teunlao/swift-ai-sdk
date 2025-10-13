# Native Background Tasks in Claude Code

**Date**: 2025-10-13
**Discovery**: True native background tasks vs. subprocess execution

---

## Problem Statement

When attempting to run MCP servers (like Codex CLI) in the background, tasks may not appear in the user's TUI, even though Claude Code sees them in system reminders. This guide explains the difference between **native background tasks** and **subprocess execution**, and how to use them correctly.

---

## ❌ Wrong: Subprocess Background (Fake Background)

### What Developers Often Do

```python
Bash(
    command="cat input.json | codex mcp-server > output.json 2>&1 &",
    run_in_background=True
)
```

### Result

- **Shell ID**: `872747` (numeric format)
- **Status**: `completed` immediately
- **Process PID**: `37373` (separate process)
- ❌ **NOT visible in user's TUI**
- ✅ Only visible in Claude Code system reminders

### Why This Doesn't Work

The `&` operator inside the command creates a **subprocess in the shell**, not a native Claude Code background task:

```
Bash tool
  └─> Shell (ID: 872747)
       └─> codex mcp-server & (PID: 37373)
            └─> runs separately
```

The shell completes immediately, but Codex continues running **outside Claude Code's control**.

---

## ✅ Correct: Native Background Task

### Proper Command

```python
Bash(
    command="codex mcp-server < /tmp/input.json > /tmp/output.json 2>&1",
    run_in_background=True,
    timeout=600000  # 10 minutes
)
```

### Key Differences

1. ❌ **NO `&`** at the end of the command
2. ✅ `run_in_background: true` — Bash tool parameter
3. ✅ Redirect via `<` and `>`
4. ✅ Timeout for long operations

### Result

```json
{
  "result": "Command running in background with ID: 336ae0"
}
```

**Characteristics**:
- **Shell ID**: `336ae0` (**hex format!**)
- **Status**: `running` while executing
- ✅ **Visible in user's TUI**
- ✅ Full control via `BashOutput`/`KillShell`

---

## Comparison

| Characteristic | Subprocess (with `&`) | Native (without `&`) |
|----------------|----------------------|---------------------|
| Shell ID format | Number (`872747`) | Hex (`336ae0`) |
| Visible in TUI | ❌ No | ✅ Yes |
| Control | ⚠️ Limited | ✅ Full |
| BashOutput | ⚠️ Doesn't work correctly | ✅ Works |
| KillShell | ❌ Won't stop process | ✅ Stops process |
| System reminders | ✅ Yes | ✅ Yes |

---

## How to Use with MCP Servers

### Step 1: Prepare JSON Request

**⚠️ IMPORTANT**: For autonomous mode (no approval prompts), **ALWAYS** include these parameters:
- `"approval-policy": "never"`
- `"sandbox": "danger-full-access"`

See [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) for complete details.

```bash
cat > /tmp/mcp-request.json <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Your task here",
      "cwd": "/path/to/project",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
EOF
```

### Step 2: Launch in Native Background (CORRECT)

```python
Bash(
    command="codex mcp-server < /tmp/mcp-request.json > /tmp/mcp-output.json 2>&1",
    description="Run MCP server in native background",
    run_in_background=True,
    timeout=600000  # 10 minutes for long operations
)
```

✅ **Result**:
```
Command running in background with ID: 336ae0
```

### Step 3: Monitor Progress

**Via BashOutput** (for AI):
```python
BashOutput(bash_id="336ae0")
```

**Via file** (for detailed output):
```bash
tail -f /tmp/mcp-output.json
```

**Via TUI** (for user):
- Background task is visible in the interface
- Can be stopped through UI
- Status updates in real-time

### Step 4: Stop if Needed

```python
KillShell(shell_id="336ae0")
```

---

## Practical Example: Codex MCP

### Creating/Updating/Deleting a Task

```python
# 1. Create JSON request (⚠️ approval-policy and sandbox required!)
Bash("""
cat > /tmp/codex-request.json <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create a test task in Taskmaster, update and delete it",
      "cwd": "/Users/user/projects/swift-ai-sdk",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
EOF
""")

# 2. Launch Codex in native background
task_id = Bash(
    command="codex mcp-server < /tmp/codex-request.json > /tmp/codex-output.json 2>&1",
    run_in_background=True,
    timeout=600000
)
# → ID: 336ae0

# 3. Check status
BashOutput(bash_id="336ae0")
# → status: running

# 4. Wait and check result
sleep(5)
output = BashOutput(bash_id="336ae0")
# → status: running (or completed if quick operation)

# 5. Read detailed output from file
Bash("tail -100 /tmp/codex-output.json")
# → See all JSON-RPC events in real-time
```

---

## What You See in Output

### MCP Events (JSON-RPC)

**Session configured**:
```json
{"type":"session_configured","session_id":"0199de23...","model":"gpt-5-codex"}
```

**Reasoning (word by word)**:
```json
{"type":"agent_reasoning_delta","delta":"Planning"}
{"type":"agent_reasoning_delta","delta":" taskmaster"}
{"type":"agent_reasoning_delta","delta":" tool"}
...
```

**Tool calls**:
```json
{
  "type":"mcp_tool_call_begin",
  "call_id":"call_GN6TIkG2...",
  "invocation":{
    "server":"taskmaster",
    "tool":"add_task",
    "arguments":{"projectRoot":"/path","title":"Test"}
  }
}
```

**Results**:
```json
{
  "type":"mcp_tool_call_end",
  "duration":{"secs":0,"nanos":12996708},
  "result":{"Ok":{"content":[{"text":"{\"taskId\":25,...}"}]}}
}
```

**Tokens**:
```json
{
  "type":"token_count",
  "info":{
    "input_tokens":10848,
    "cached_input_tokens":0,
    "output_tokens":572,
    "reasoning_output_tokens":512
  }
}
```

**Final message**:
```json
{"type":"task_complete","last_agent_message":"Task 25 ... successfully."}
```

---

## Benefits of Native Background

### For User
- ✅ **Sees task in TUI** — transparency
- ✅ **Can stop it** — control
- ✅ **Sees status** — monitoring

### For AI
- ✅ **BashOutput works** — can check progress
- ✅ **KillShell works** — can stop
- ✅ **Proper lifecycle** — task managed by Claude Code

### For Debugging
- ✅ **Full output file** — can analyze after
- ✅ **JSON-RPC events** — see every Codex step
- ✅ **System reminders** — AI gets notifications

---

## Important Notes

### 1. Don't Use `&` with `run_in_background`

❌ **Wrong**:
```python
Bash(
    command="long-task &",
    run_in_background=True
)
```

✅ **Correct**:
```python
Bash(
    command="long-task",
    run_in_background=True
)
```

### 2. Timeout is Required for Long Operations

```python
Bash(
    command="codex mcp-server < input > output 2>&1",
    run_in_background=True,
    timeout=600000  # 10 minutes, not default 2!
)
```

### 3. Redirect is Required

**Why**: MCP server's STDIN expects JSON, STDOUT/STDERR need to be saved

```python
# ✅ Correct
command="codex mcp-server < input.json > output.json 2>&1"

# ❌ Wrong (no input data)
command="codex mcp-server"
```

### 4. BashOutput May Be Empty

Native background tasks stream output **gradually**. The file may update, but BashOutput only shows `status: running`.

**Solution**: Read the file directly for detailed output:
```bash
tail -50 /tmp/codex-output.json
```

---

## Technical Details

### Shell ID Formats

**Subprocess** (fake background):
- Format: Decimal number (e.g., `872747`)
- Created by: `&` operator in shell
- Managed by: Shell process (not Claude Code)

**Native** (true background):
- Format: Hexadecimal (e.g., `336ae0`, `bf4c12`)
- Created by: `run_in_background: true` parameter
- Managed by: Claude Code directly

### Process Hierarchy

**Subprocess**:
```
Claude Code Bash Tool
  └─> Shell (ID: 872747) [completes immediately]
       └─> Process & (PID: 37373) [detached, runs independently]
```

**Native**:
```
Claude Code Bash Tool
  └─> Background Task (ID: 336ae0) [managed, visible in TUI]
       └─> Process [controlled by Claude Code]
```

---

## Documentation

### Official Sources

1. **Bash tool docs**: https://docs.claude.com/en/docs/agents-and-tools/tool-use/bash-tool
2. **Background commands**: Mentioned in changelog v1.0.71 (Ctrl+B)
3. **GitHub issues**:
   - https://github.com/anthropics/claude-code/issues/2550
   - https://github.com/anthropics/claude-code/issues/5709

### Key Information

- Background tasks appeared in Claude Code v1.0.71 (October 2025)
- ID format: hex (`336ae0`, `bf4c12`, etc.)
- Separate shells for each background task
- Incremental output via BashOutput
- Keyboard shortcut: **Ctrl+B** to run command in background

---

## Conclusions

1. **Native background tasks** are different from subprocess with `&`
2. **`run_in_background: true` parameter** creates native task
3. **Hex ID** (`336ae0`) = native, number (`872747`) = subprocess
4. **Visibility in TUI** = important indicator of correct usage
5. **MCP + native background** = ideal combination for long tasks

### Rule of Thumb

> If you need **control and visibility** → use native background (without `&`)
> If you just need **fire and forget** → can use subprocess (with `&`)

---

## See Also

- **[interactive-mcp-sessions.md](./interactive-mcp-sessions.md)** — Advanced: Persistent MCP sessions with multiple commands in same context using `tail -f`
- **[codex-sandbox-permissions.md](./codex-sandbox-permissions.md)** — How to bypass approvals for autonomous operation (required parameters)

---

**Author**: Claude Code AI
**Date**: 2025-10-13
**Tested with**: Codex CLI 0.46.0, Claude Code Sonnet 4.5
