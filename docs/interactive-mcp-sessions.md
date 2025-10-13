# Interactive MCP Sessions in Claude Code

**Date**: 2025-10-13 (Updated)
**Discovery**: Persistent MCP sessions with multiple commands in single context

---

## 🚨 CRITICAL: Always Include Autonomous Parameters

For **EVERY** command sent to Codex MCP server, you **MUST** include these parameters in the JSON:

```json
{
  "arguments": {
    "prompt": "Your task",
    "cwd": "/path/to/workspace",
    "approval-policy": "never",
    "sandbox": "danger-full-access"
  }
}
```

**Without these parameters, Codex will prompt for approval and block execution!**

See [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) for detailed explanation.

---

## Overview

This guide extends [native-background-tasks.md](./native-background-tasks.md) by showing how to create **persistent, interactive MCP sessions** where you can send multiple commands to the same context without restarting the server.

---

## Problem

With standard MCP invocation:

```bash
codex mcp-server < input.json > output.json
```

**Limitations**:
1. ❌ STDIN reads file **once** and closes
2. ❌ MCP server **terminates** when STDIN closes
3. ❌ Cannot send second command to same session
4. ❌ Each invocation = new isolated context

**Result**: Every background task is a **one-shot operation**.

---

## Solution: `tail -f` for Persistent STDIN

**Key Insight**: Use `tail -f` to keep STDIN open indefinitely, allowing multiple commands to be appended to the input file.

### How It Works

```
┌─────────────────┐
│ Command Buffer  │ ← Append new commands here
│  (JSONL file)   │
└────────┬────────┘
         │ tail -f (keeps reading)
         ↓
┌─────────────────┐
│  MCP Server     │ ← Processes each command
│  (codex, etc.)  │    Maintains session state
└────────┬────────┘
         │ Results
         ↓
┌─────────────────┐
│  Output File    │ ← JSON-RPC events stream
│  (JSON lines)   │
└─────────────────┘
```

**`tail -f` behavior**:
- Continuously monitors file for new content
- Streams new lines to STDOUT as they're appended
- Never closes STDIN unless explicitly killed
- Perfect for persistent pipes!

---

## Step-by-Step Guide

### 1. Create Command Buffer

```python
# Initialize empty command buffer (JSONL format)
Bash("touch /tmp/codex-commands.jsonl")
```

### 2. Launch Persistent Session

**🚨 ALWAYS use Claude Code native background task:**

```python
# Use run_in_background parameter (NO & operator!)
task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/codex-session.json 2>&1",
    run_in_background=True,  # ✅ ALWAYS use this for Claude Code!
    timeout=3600000  # 1 hour for long sessions
)
# → Returns hex ID (e.g., "9de576") - visible in TUI!
```

**Result**:
- ✅ Native background task (visible in user's TUI)
- ✅ MCP server running and waiting
- ✅ STDIN kept open by `tail -f`
- ✅ Full control via BashOutput/KillShell

**Critical**: NEVER use `&` operator - only use `run_in_background: true` parameter!

### 3. Send Commands (Anytime!)

Append JSON-RPC commands to the buffer file:

```bash
# Command 1 (⚠️ ALWAYS include approval-policy and sandbox!)
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Calculate 10 + 10","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# Command 2 (same session!)
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Now calculate 20 + 20","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
```

**Important**: Use `>>` (append) not `>` (overwrite)!

### 4. Read Responses

**🚨 CRITICAL: Use parse script for token efficiency!**

```bash
# ✅ RECOMMENDED: Parse script (saves tokens!)
python3 scripts/parse-codex-output.py /tmp/codex-session.json --last 100 --reasoning
python3 scripts/parse-codex-output.py /tmp/codex-session.json --stuck

# ⚠️ LEGACY: Raw file (only if parse script insufficient)
tail -f /tmp/codex-session.json

# Extract specific responses
grep '"requestId":1' /tmp/codex-session.json | grep '"type":"agent_message"'
grep '"requestId":2' /tmp/codex-session.json | grep '"type":"agent_message"'
```

**Why parse script:**
- ✅ Saves massive tokens by filtering noise
- ✅ Human-readable output
- ✅ Smart stuck detection

### 5. Stop Session When Done

```bash
# Via KillShell (if native background task)
KillShell(shell_id: "9de576")

# Or find and kill process
pkill -f "tail -f /tmp/codex-commands.jsonl"
```

---

## Complete Working Example

### Setup and Launch

```python
# 1. Prepare environment
Bash("rm -f /tmp/codex-commands.jsonl /tmp/codex-session.json && touch /tmp/codex-commands.jsonl")

# 2. Launch persistent session
task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/codex-session.json 2>&1",
    description="Launch persistent Codex session",
    run_in_background=True,
    timeout=3600000  # 1 hour
)
# → Returns: "9de576" (hex ID)
```

### Send Multiple Commands

```python
# Command 1: Simple math (⚠️ approval-policy and sandbox REQUIRED!)
Bash("""
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Calculate 10 + 10. Answer with number only.","cwd":"/Users/user/project","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
""")

# Wait and check response
sleep(5)
# ✅ RECOMMENDED: Use parse script (saves tokens!)
Bash("python3 scripts/parse-codex-output.py /tmp/codex-session.json --last 50 --messages")
# Output: Human-readable messages only

# Command 2: Use same session
Bash("""
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Now calculate 20 + 20. Answer with number only.","cwd":"/Users/user/project","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
""")

# Check second response
sleep(5)
# ✅ RECOMMENDED: Use parse script
Bash("python3 scripts/parse-codex-output.py /tmp/codex-session.json --last 50 --messages")
# Output: {"type":"agent_message","message":"40"}
```

### Verify Session Persistence

```python
# Check session info in output
Bash("grep '\"type\":\"session_configured\"' /tmp/codex-session.json")
# Shows SAME session_id for both commands!
```

**Key Observation**: Both commands processed by **same session** (same `session_id`).

---

## Response Format

Each command generates JSON-RPC events:

```json
// Session start (first command only)
{"type":"session_configured","session_id":"0199de5f-...","model":"gpt-5-codex"}

// Task started
{"type":"task_started","model_context_window":272000}

// Reasoning (optional, word-by-word)
{"type":"agent_reasoning_delta","delta":"**Calculating"}
{"type":"agent_reasoning_delta","delta":" result"}
{"type":"agent_reasoning","text":"**Calculating result**"}

// Response (word-by-word)
{"type":"agent_message_delta","delta":"20"}
{"type":"agent_message","message":"20"}

// Token usage
{"type":"token_count","info":{"input_tokens":10840,"output_tokens":7,...}}

// Task complete
{"type":"task_complete","last_agent_message":"20"}

// Final result
{"id":1,"jsonrpc":"2.0","result":{"content":[{"text":"20","type":"text"}]}}
```

**Note**: Subsequent commands in same session show **same** `session_id` in `session_configured` events.

---

## Use Cases

### 1. Multi-Step Workflows

```bash
# Step 1: Create task (⚠️ ALWAYS include approval-policy and sandbox!)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Create task via mcp__taskmaster__add_task","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl

# Step 2: Update task (uses context from step 1)
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Update the task we just created","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl

# Step 3: Delete task
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Delete the task","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl
```

### 2. Iterative Problem Solving

```bash
# Initial attempt (⚠️ ALWAYS include approval-policy and sandbox!)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Implement feature X","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl

# Refinement (after seeing results)
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Fix the error in previous implementation","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl

# Verification
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Add tests for the implementation","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl
```

### 3. Interactive Debugging

```bash
# Run code (⚠️ ALWAYS include approval-policy and sandbox!)
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Run the test suite","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl

# Analyze failure
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Analyze why test X failed","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl

# Apply fix
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Fix the identified issue","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}' >> /tmp/codex-commands.jsonl
```

---

## Best Practices

### Command IDs

```bash
# ✅ Good: Sequential unique IDs
{"id":1,...}
{"id":2,...}
{"id":3,...}

# ❌ Bad: Reused IDs (confusing responses)
{"id":1,...}
{"id":1,...}  # Same ID!
```

### Append vs Overwrite

```bash
# ✅ Correct: Append to existing file
echo '...' >> /tmp/codex-commands.jsonl

# ❌ Wrong: Overwrites file, loses history
echo '...' > /tmp/codex-commands.jsonl
```

### Waiting for Responses

```bash
# ✅ Good: Wait between commands
echo '{"id":1,...}' >> /tmp/codex-commands.jsonl
sleep 5  # Let it process
echo '{"id":2,...}' >> /tmp/codex-commands.jsonl

# ⚠️ Acceptable: Send all at once (queued)
echo '{"id":1,...}' >> /tmp/codex-commands.jsonl
echo '{"id":2,...}' >> /tmp/codex-commands.jsonl
echo '{"id":3,...}' >> /tmp/codex-commands.jsonl
# MCP server processes sequentially
```

### Session Lifetime

```bash
# Set appropriate timeout for long sessions
timeout=3600000  # 1 hour (60 minutes)

# For very long sessions
timeout=7200000  # 2 hours

# Monitor active session
BashOutput(bash_id="9de576")  # Check if still running
```

---

## Limitations

### 1. No Bidirectional Streaming

- ❌ Cannot interrupt ongoing command
- ❌ Cannot modify command after sending
- ✅ Can queue multiple commands (processed sequentially)

### 2. Session State

- ✅ Same session ID across commands
- ✅ Shared context (history, tool state)
- ⚠️ Session history grows with each command (token usage increases)

### 3. Error Handling

```bash
# If command fails, session continues
echo '{"id":1,...}' >> /tmp/codex-commands.jsonl  # May fail
# Session still active, can send more commands
echo '{"id":2,...}' >> /tmp/codex-commands.jsonl  # Works

# To recover from errors, check output:
tail -f /tmp/codex-session.json | grep '"type":"error"'
```

### 4. Resource Management

```bash
# Long-running sessions consume resources
# Monitor token usage:
grep '"type":"token_count"' /tmp/codex-session.json | tail -1

# If context too large, restart session:
KillShell(shell_id="9de576")
# Start new session (fresh context)
```

---

## Comparison with Single-Shot

| Feature | Single-Shot | Interactive Session |
|---------|-------------|-------------------|
| Setup | Simple | Requires `tail -f` |
| Commands per session | 1 | Unlimited |
| Context preservation | ❌ No | ✅ Yes |
| Session ID | New each time | Same across commands |
| Token usage | Low per command | Grows with history |
| Use case | Simple tasks | Multi-step workflows |
| Cleanup | Automatic | Manual kill needed |

---

## Troubleshooting

### Session Won't Start

```bash
# Check if file exists
ls -lh /tmp/codex-commands.jsonl

# Verify tail -f works
tail -f /tmp/codex-commands.jsonl  # Should block, waiting for input

# Check MCP server available
which codex
codex --version
```

### Commands Not Processing

```bash
# Check session still running
BashOutput(bash_id="9de576")
# status: running (good) or completed (session died)

# Verify JSON format
cat /tmp/codex-commands.jsonl  # Check for syntax errors

# Monitor output for errors
tail -f /tmp/codex-session.json | grep '"type":"error"'
```

### Output File Growing Too Large

```bash
# Rotate output file (lose history)
KillShell(shell_id="9de576")
mv /tmp/codex-session.json /tmp/codex-session-old.json
# Restart session with fresh output file

# Or filter output
grep '"type":"agent_message"\|"type":"error"' /tmp/codex-session.json > /tmp/filtered.json
```

---

## Advanced Patterns

### Command Templates

```bash
# Helper function for sending commands (⚠️ ALWAYS includes approval-policy and sandbox!)
send_codex_command() {
  local id=$1
  local prompt=$2
  local cwd="${3:-$PWD}"
  cat >> /tmp/codex-commands.jsonl <<EOF
{"jsonrpc":"2.0","id":${id},"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"${prompt}","cwd":"${cwd}","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
}

# Usage
send_codex_command 1 "Create a test file" "/path/to/project"
send_codex_command 2 "Run the tests" "/path/to/project"
send_codex_command 3 "Fix any failures" "/path/to/project"
```

### Response Extraction

```bash
# Extract just the message for a specific request
get_response() {
  local request_id=$1
  grep "\"requestId\":${request_id}" /tmp/codex-session.json | \
    grep '"type":"agent_message"' | \
    jq -r '.params.msg.message'
}

# Usage
result=$(get_response 1)
echo "Response: $result"
```

### Auto-Cleanup

**For Claude Code** (use KillShell):

```python
# Clean stop when done
KillShell(shell_id=task_id)

# Optional: cleanup files
Bash("rm -f /tmp/codex-commands.jsonl /tmp/codex-session.json")
```

---

## Integration with Native Background Tasks

See [native-background-tasks.md](./native-background-tasks.md) for:
- How to launch as native background task (visible in TUI)
- Using `run_in_background: true` parameter
- Monitoring with `BashOutput`
- Stopping with `KillShell`

**Combined approach**:
```python
# 1. Native background task (visible in TUI)
session_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/codex-session.json 2>&1",
    run_in_background=True,  # Native background!
    timeout=3600000
)

# 2. Send commands interactively (⚠️ approval-policy and sandbox REQUIRED!)
for i in range(10):
    cmd = f'{{"jsonrpc":"2.0","id":{i},"method":"tools/call","params":{{"name":"codex","arguments":{{"prompt":"Task {i}","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}}}}'
    Bash(f"echo '{cmd}' >> /tmp/codex-commands.jsonl")
    sleep(5)

# 3. Monitor via BashOutput
status = BashOutput(bash_id=session_id)

# 4. Clean stop when done
KillShell(shell_id=session_id)
```

---

## Conclusion

**Interactive MCP sessions** enable:
- ✅ Multi-step workflows in single context
- ✅ Iterative problem solving with state preservation
- ✅ Dynamic command sending during execution
- ✅ Full visibility in TUI (when using native background)

**Key technique**: `tail -f` keeps STDIN open, allowing append-based command sending.

**Perfect for**:
- Complex multi-step tasks
- Debugging sessions
- Iterative development workflows
- Long-running agent interactions

---

**Author**: Claude Code AI
**Date**: 2025-10-13
**Tested with**: Codex CLI 0.46.0, Claude Code Sonnet 4.5
**See also**:
- [native-background-tasks.md](./native-background-tasks.md) — Native background tasks basics
- [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) — Sandbox modes and permissions
- [monitoring-codex-output.md](./monitoring-codex-output.md) — Monitoring and analyzing output
