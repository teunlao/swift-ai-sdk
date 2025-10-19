# Interactive MCP Sessions

**Purpose**: Persistent MCP sessions with multiple commands in single context

---

## 🚨 CRITICAL: Autonomous Parameters Required

For **EVERY** command:

```json
{
  "arguments": {
    "prompt": "Your task",
    "cwd": "/path",
    "approval-policy": "never",
    "sandbox": "danger-full-access"
  }
}
```

See [codex-sandbox-permissions.md](./codex-sandbox-permissions.md)

---

## How It Works

**Problem**: Single-shot MCP closes after one command

**Solution**: `tail -f` keeps STDIN open for multiple commands

```
Command Buffer (JSONL) → tail -f → MCP Server → Output File
```

---

## Step-by-Step

### 1. Create Buffer

```bash
touch /tmp/codex-commands.jsonl
```

### 2. Launch Session

```python
task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/output.json 2>&1",
    run_in_background=True,
    timeout=3600000
)
# → Returns hex ID (e.g., "9de576")
```

### 3. Send Commands

```bash
# Command 1
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Calculate 10+10","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# Command 2 (same session!)
cat >> /tmp/codex-commands.jsonl <<'EOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Now 20+20","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
```

**Important**: Use `>>` (append) not `>` (overwrite)!

### 4. Read Responses

```bash
# ✅ RECOMMENDED: Parse script (saves tokens!)
python3 scripts/parse-codex-output.py /tmp/output.json --last 100 --reasoning
python3 scripts/parse-codex-output.py /tmp/output.json --stuck

# Extract specific responses
grep '"requestId":1' /tmp/output.json | grep '"type":"agent_message"'
```

### 5. Stop Session

```python
KillShell(shell_id="9de576")
```

---

## Use Cases

### Multi-Step Workflow

```bash
# Step 1: Create
echo '{"id":1,..."prompt":"Create task",...}' >> /tmp/codex-commands.jsonl

# Step 2: Update (uses context from step 1)
echo '{"id":2,..."prompt":"Update the task",...}' >> /tmp/codex-commands.jsonl

# Step 3: Delete
echo '{"id":3,..."prompt":"Delete the task",...}' >> /tmp/codex-commands.jsonl
```

### Iterative Debugging

```bash
# Run tests
echo '{"id":1,..."prompt":"Run test suite",...}' >> /tmp/codex-commands.jsonl

# Analyze failure
echo '{"id":2,..."prompt":"Analyze why test X failed",...}' >> /tmp/codex-commands.jsonl

# Fix
echo '{"id":3,..."prompt":"Fix the issue",...}' >> /tmp/codex-commands.jsonl
```

---

## Best Practices

### DO ✅

- Use sequential unique IDs (`{"id":1...}`, `{"id":2...}`)
- Append with `>>` not overwrite with `>`
- Wait between commands or queue all at once
- Monitor with parse script for token efficiency

### DON'T ❌

- Reuse same IDs (confusing responses)
- Let context grow too large (restart if tokens > 5M)
- Skip monitoring (check `--stuck` regularly)

---

## Limitations

- ❌ Cannot interrupt ongoing command
- ❌ Cannot modify command after sending
- ✅ Can queue multiple commands (sequential processing)
- ⚠️ Session history grows (token usage increases)

---

## Comparison

| Feature | Single-Shot | Interactive |
|---------|------------|-------------|
| Commands | 1 | Unlimited |
| Context | ❌ Lost | ✅ Preserved |
| Session ID | New each time | Same |
| Token usage | Low | Grows |
| Use case | Simple | Multi-step |

---

## Related Docs

- [native-background-tasks.md](./native-background-tasks.md) - Background basics
- [codex-sandbox-permissions.md](./codex-sandbox-permissions.md) - Autonomous params
- [monitoring-codex-output.md](./monitoring-codex-output.md) - Output analysis

---

**Last updated**: 2025-10-14
