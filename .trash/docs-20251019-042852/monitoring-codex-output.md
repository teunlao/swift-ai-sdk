# Monitoring Codex MCP Output

**Purpose**: Analyzing Codex CLI MCP server output efficiently

---

## 🚨 CRITICAL: Always Use Parse Script

```bash
python3 scripts/parse-codex-output.py /tmp/codex-output.jsonl --last 100 --reasoning
```

**Why:**
- ✅ Saves 90%+ tokens (filters noise)
- ✅ Human-readable output
- ✅ Smart stuck detection
- ❌ Never `cat`/`tail` raw JSONL directly

**Rule**: Parse script FIRST, raw file ONLY if insufficient.

---

## Quick Commands

```bash
# Check if stuck (most important!)
python3 scripts/parse-codex-output.py FILE --stuck

# Recent thoughts
python3 scripts/parse-codex-output.py FILE --last 100 --reasoning

# Commands executed
python3 scripts/parse-codex-output.py FILE --commands

# Messages only
python3 scripts/parse-codex-output.py FILE --messages

# Statistics
python3 scripts/parse-codex-output.py FILE --summary
```

---

## Parse Script Options

| Flag | Description |
|------|-------------|
| `--stuck` | Detect if stuck in analysis loop |
| `--last N` | Show only last N events |
| `--reasoning` | Show only reasoning blocks |
| `--commands` | Show only commands executed |
| `--messages` | Show only final messages |
| `--summary` | Event statistics |
| `--timeline` | Timeline with timestamps |
| `--compact` | One-line format (quick scan) |
| `--no-color` | Disable colors (for piping) |

---

## Common Monitoring Patterns

### Quick Status Check

```bash
python3 scripts/parse-codex-output.py FILE --stuck
python3 scripts/parse-codex-output.py FILE --last 50 --reasoning | tail -5
python3 scripts/parse-codex-output.py FILE --commands | tail -10
```

### Debugging Failed Session

```bash
# Timeline
python3 scripts/parse-codex-output.py FILE --timeline > timeline.txt

# Errors
grep '"type":"error"' FILE

# Non-zero exits
grep '"exit_code"' FILE | grep -v '"exit_code":0'
```

---

## Reasoning Phases

1. **Exploration** - Reading files (`sed`, `rg`, `ls` commands)
2. **Planning** - Design ("Planning...", "Designing...")
3. **Implementation** - Creating files (`mkdir`, `Write`)
4. **Testing** - Running tests (`swift test`)
5. **Stuck** - Repeating analysis (use `--stuck` to detect)

---

## Token Usage Warning Signs

**Red flags:**
- Total tokens > 5M without files created → stuck
- Cache % < 80% → inefficient prompts
- Rapid growth (>500K/5min) → excessive exploration

**Good signs:**
- Steady growth with file creation
- High cache % (>90%)
- Token usage plateaus after implementation

---

## Integration with Claude Code

```python
# Launch native background
task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/output.json 2>&1",
    run_in_background=True,
    timeout=3600000
)

# Monitor via parse script
Bash("python3 scripts/parse-codex-output.py /tmp/output.json --stuck")
Bash("python3 scripts/parse-codex-output.py /tmp/output.json --last 100 --reasoning")

# Stop
KillShell(shell_id=task_id)
```

---

## Related Docs

- [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) - Autonomous mode
- [native-background-tasks.md](./native-background-tasks.md) - Background tasks
- [interactive-mcp-sessions.md](./interactive-mcp-sessions.md) - Persistent sessions

---

**Last updated**: 2025-10-14
