# Monitoring Codex MCP Output

**Date**: 2025-10-13
**Purpose**: Guide for monitoring and analyzing Codex CLI MCP server output

---

## Overview

When running Codex via MCP server (especially in background), it outputs JSON-RPC events in JSONL format. This guide shows how to effectively monitor and analyze this output.

---

## Output Format

Codex MCP server produces **JSON Lines (JSONL)** - one JSON object per line:

```jsonl
{"jsonrpc":"2.0","method":"codex/event","params":{"_meta":{"requestId":1},"id":"1","msg":{"type":"task_started"}}}
{"jsonrpc":"2.0","method":"codex/event","params":{"_meta":{"requestId":1},"id":"1","msg":{"type":"agent_reasoning_delta","delta":"**Planning"}}}
{"jsonrpc":"2.0","method":"codex/event","params":{"_meta":{"requestId":1},"id":"1","msg":{"type":"agent_reasoning","text":"**Planning Swift implementation**"}}}
```

### Common Event Types

| Type | Description |
|------|-------------|
| `session_configured` | Session started, includes session_id |
| `task_started` | Request processing began |
| `agent_reasoning_delta` | Word-by-word reasoning (streaming) |
| `agent_reasoning` | Complete reasoning block |
| `agent_message_delta` | Word-by-word response (streaming) |
| `agent_message` | Complete response message |
| `exec_command_begin` | Command execution started |
| `exec_command_output_delta` | Command output (base64 encoded) |
| `exec_command_end` | Command finished with exit code |
| `token_count` | Token usage statistics |
| `task_complete` | Request processing finished |

---

## Quick Monitoring

### 1. Real-time Tail (Raw)

```bash
tail -f /tmp/codex-output.jsonl
```

**Pros:** Immediate updates
**Cons:** Hard to read (JSONL format, word-by-word deltas)

### 2. Grep for Reasoning

```bash
grep '"type":"agent_reasoning"' /tmp/codex-output.jsonl | tail -10 | jq -r '.params.msg.text'
```

Shows last 10 complete reasoning blocks.

### 3. Check Latest Commands

```bash
grep '"type":"exec_command_begin"' /tmp/codex-output.jsonl | tail -5 | jq -r '.params.msg.command | join(" ")'
```

Shows last 5 commands executed.

### 4. Token Usage

```bash
grep '"type":"token_count"' /tmp/codex-output.jsonl | tail -1 | jq '.params.msg.info.total_token_usage'
```

Current total token count.

---

## Parse Script (Recommended)

Located at: `scripts/parse-codex-output.py`

This Python script provides human-readable output with colors, filtering, and analysis.

### Installation

No installation needed - uses standard Python 3 libraries.

### Basic Usage

```bash
# Show last 100 events (all types)
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 100

# Show only reasoning (Codex thoughts)
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --reasoning

# Show only commands executed
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --commands

# Show only final messages
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --messages

# Statistics summary
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --summary
```

### Advanced Features

#### Compact Mode

One line per event (quick scanning):

```bash
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 50 --compact
```

Output:
```
🧠 Planning Swift implementation for generateText() function...
⚡ $ sed -n '1,200p' Sources/SwiftAISDK/Core/GenerateText.swift
📊 Tokens: 2,500,000 (cached: 2,400,000)
🧠 Analyzing type conversions for response processing...
```

#### Stuck Detection

Detects if Codex is stuck in analysis loop:

```bash
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --stuck
```

Output:
```
⏸️  POSSIBLY STUCK
   Reason: Extended analysis phase without coding
   Suggestion: Consider sending feedback to start coding
```

Or:
```
✅ Status: OK (making progress)
```

#### Timeline View

Shows events with relative timestamps:

```bash
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --timeline
```

Output:
```
  +0.0s 🚀 Task started
 +12.5s 🧠 Planning Swift implementation
 +45.2s ⚡ $ rg "generateText" -n
 +48.1s 🧠 Analyzing upstream TypeScript
 +89.3s 📊 Tokens: 1,200,000
```

#### Disable Colors

For copying text or piping to files:

```bash
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --no-color > report.txt
```

### Filtering Options

| Flag | Description |
|------|-------------|
| `--last N` | Show only last N events |
| `--reasoning` | Show only reasoning blocks |
| `--commands` | Show only commands executed |
| `--messages` | Show only final messages |
| `--summary` | Show event statistics |
| `--timeline` | Timeline view with timestamps |
| `--stuck` | Detect if Codex is stuck |
| `--compact` | One-line format |
| `--no-color` | Disable ANSI colors |

---

## Common Monitoring Patterns

### Pattern 1: Quick Status Check

```bash
# What's Codex thinking about?
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 100 --reasoning | tail -5

# What's it doing?
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --commands | tail -10

# Is it stuck?
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --stuck
```

### Pattern 2: Monitor Progress

Check every 5 minutes:

```bash
while true; do
  clear
  echo "=== Codex Status at $(date) ==="
  python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --stuck
  python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 50 --reasoning --compact | tail -10
  sleep 300  # 5 minutes
done
```

### Pattern 3: Debugging Failed Session

```bash
# Full timeline to see what happened
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --timeline > timeline.txt

# Look for errors
grep '"type":"error"' /tmp/codex-output.jsonl

# Check exit codes
grep '"exit_code"' /tmp/codex-output.jsonl | grep -v '"exit_code":0'

# Last reasoning before failure
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --reasoning | tail -20
```

### Pattern 4: Verify File Creation

```bash
# Check if Codex created any files
grep '"exec_command_begin"' /tmp/codex-output.jsonl | grep -E "mkdir|touch|Write" | tail -10

# Or check directly
ls -lht Sources/SwiftAISDK/Core/GenerateText/ 2>/dev/null || echo "Not created yet"
```

---

## Interpreting Output

### Reasoning Phases

**Common reasoning patterns:**

1. **Exploration** - Reading files, searching codebase
   - "Checking for...", "Examining...", "Investigating..."
   - Many `sed`, `rg`, `ls` commands

2. **Planning** - Designing architecture
   - "Planning...", "Designing...", "Sketching..."
   - Reading upstream TypeScript, analyzing types

3. **Implementation** - Writing code
   - "Implementing...", "Creating...", "Writing..."
   - File creation commands (mkdir, Write)

4. **Testing** - Running tests
   - "Running tests...", "Verifying..."
   - `swift test`, `swift build` commands

5. **Stuck** - Repeating analysis
   - Same reasoning patterns repeating
   - No file creation for >10 minutes
   - Use `--stuck` flag to detect

### Token Usage Warning Signs

```bash
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 500 | grep Tokens | tail -5
```

**Red flags:**
- Total tokens > 5M without file creation → possibly stuck
- Cache % dropping below 80% → inefficient prompts
- Rapid token growth (>500K/5min) → excessive exploration

**Good signs:**
- Steady token growth with file creation
- High cache % (>90%)
- Token usage plateaus after implementation

---

## Integration with Native Background Tasks

When using Codex as native background task in Claude Code:

```python
# Launch (plain mcp-server - parameters go in JSON!)
task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/codex-output.jsonl 2>&1",
    run_in_background=True,
    timeout=3600000
)
# → Returns hex ID (e.g., "37a2f1")

# ⚠️ IMPORTANT: Send commands with required parameters!
# Every command must include:
# "approval-policy": "never"
# "sandbox": "danger-full-access"
# See codex-sandbox-permissions.md for details

# Monitor via parse script
Bash("python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 100 --reasoning")

# Check if stuck
Bash("python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --stuck")

# Stop when done
KillShell(shell_id=task_id)
```

---

## Best Practices

### DO ✅

1. **Check stuck detection every 10 minutes** during long runs
2. **Monitor token usage** - stop if exceeding budget
3. **Use compact mode** for quick scans during active work
4. **Save timeline** for post-mortem analysis
5. **Check commands** to verify Codex is actually doing work

### DON'T ❌

1. **Don't rely only on tail -f** - use parse script for clarity
2. **Don't ignore "possibly stuck"** warnings - usually accurate
3. **Don't let token usage grow unbounded** - set limits
4. **Don't assume progress** without checking file creation
5. **Don't skip monitoring** during critical long-running tasks

---

## Troubleshooting

### Problem: No reasoning visible

**Check:**
```bash
wc -l /tmp/codex-output.jsonl
# Should be growing
```

**Solution:** Verify background task is running via `BashOutput`.

### Problem: Parse script errors

**Common cause:** JSONL corruption (incomplete lines)

**Solution:**
```bash
# Fix by taking only complete lines
grep '^{' /tmp/codex-output.jsonl > /tmp/codex-output-clean.jsonl
python3 scripts/parse-codex-output.py /tmp/codex-output-clean.jsonl
```

### Problem: Stuck detection false positive

**Cause:** Complex planning tasks may seem stuck

**Verify manually:**
```bash
# Check if commands are still running
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --commands | tail -20
```

If varied commands are executing → not stuck
If same commands repeating → likely stuck

---

## Performance Notes

- **JSONL size:** Can grow to 100MB+ for long sessions
- **Parse time:** ~1-2 seconds per 10,000 events
- **Memory:** Script uses <50MB even for large files
- **Recommendation:** Archive old output files after completion

```bash
# Archive completed session
mv /tmp/codex-output.jsonl ~/.codex/sessions/task-5.8-$(date +%Y%m%d).jsonl
gzip ~/.codex/sessions/task-5.8-*.jsonl
```

---

## Related Documentation

- **[codex-sandbox-permissions.md](./codex-sandbox-permissions.md)** — Codex sandbox modes and MCP integration
- **[native-background-tasks.md](./native-background-tasks.md)** — Running Codex as background task
- **[interactive-mcp-sessions.md](./interactive-mcp-sessions.md)** — Persistent MCP sessions

---

## Quick Reference

```bash
# Most useful commands
python3 scripts/parse-codex-output.py FILE --stuck                    # Check status
python3 scripts/parse-codex-output.py FILE --last 100 --reasoning     # Recent thoughts
python3 scripts/parse-codex-output.py FILE --commands                 # What it's doing
python3 scripts/parse-codex-output.py FILE --summary                  # Statistics
python3 scripts/parse-codex-output.py FILE --last 50 --compact        # Quick scan
```

---

**Author**: Claude Code AI
**Date**: 2025-10-13
**Script location**: `scripts/parse-codex-output.py`
**Last updated**: 2025-10-13
