# Codex MCP Server: Autonomous Mode

**Purpose**: Bypass approvals for autonomous Codex MCP operation

---

## 🚨 CRITICAL: Required Parameters

**MUST include in EVERY JSON request:**

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

**Key points:**
- Both parameters **required together**
- kebab-case format (dashes, not underscores)
- Inside `arguments` object
- Without these → Codex prompts for approval and blocks!

---

## Quick Start

### Single Request

```bash
cat > request.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Create hello.py","cwd":"/tmp","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

codex mcp-server < request.json > output.json 2>&1
```

### Claude Code Background Task

```python
Bash("touch /tmp/codex-commands.jsonl")

task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/output.json 2>&1",
    run_in_background=True,
    timeout=3600000
)

# Send command (one line!)
Bash("""
cat > /tmp/cmd.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Implement X","cwd":"/path","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
cat /tmp/cmd.json >> /tmp/codex-commands.jsonl
""")
```

---

## Why JSON Parameters Work

**Code structure** (`codex-rs/mcp-server/src/codex_tool_config.rs`):

```rust
#[serde(rename_all = "kebab-case")]  // ← kebab-case required!
pub struct CodexToolCallParam {
    pub approval_policy: Option<CodexToolCallApprovalPolicy>,
    pub sandbox: Option<CodexToolCallSandboxMode>,
}
```

**Auto-approve logic** (`codex-rs/core/src/safety.rs`):
```rust
match (approval_policy, sandbox_policy) {
    (Never, DangerFullAccess) => AutoApprove,  // ← Both required!
    _ => RequireApproval
}
```

---

## Parameter Values

### approval-policy

| Value | Use |
|-------|-----|
| `"never"` | ✅ Autonomous mode |
| `"on-failure"` | Ask only on errors |
| `"on-request"` | Ask always (default) |

### sandbox

| Value | Use |
|-------|-----|
| `"danger-full-access"` | ✅ Autonomous mode |
| `"workspace-write"` | Write in workspace only |
| `"read-only"` | No writes (default) |

---

## ❌ What DOESN'T Work

### Config Flags

```bash
# ❌ WRONG - ignored in MCP mode
codex mcp-server -c 'approval_policy="never"' < input.json
```

### CLI Flag

```bash
# ❌ WRONG - doesn't exist for mcp-server
codex mcp-server --dangerously-bypass-approvals-and-sandbox
```

### Environment Variables

```bash
# ❌ WRONG - not supported
export CODEX_APPROVAL_POLICY=never
```

---

## Troubleshooting

### Still asks for approval?

```bash
# Check parameters present
grep approval-policy /tmp/codex-commands.jsonl
# → Should show: "approval-policy":"never"

# Check kebab-case (not snake_case!)
grep approval_policy /tmp/codex-commands.jsonl
# → Should be EMPTY
```

**Fix:**
- Use kebab-case: `"approval-policy"` not `"approval_policy"`
- Include BOTH parameters
- Place inside `arguments` object

### Permission denied?

Using wrong sandbox value.

**Fix:** `"sandbox": "danger-full-access"`

### Session dies after first command?

Using single-shot instead of persistent session.

**Fix:** Use `tail -f` pattern (see Quick Start)

---

## Security

### ⚠️ Use Only In:
- Docker containers
- Virtual machines with snapshots
- CI/CD pipelines with isolation
- Trusted dev environments with git

### ❌ NEVER Use:
- Production servers
- With untrusted prompts
- Without backups/version control
- Shared environments

---

## Verification Test

```bash
# Create test request
cat > /tmp/test.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Create /tmp/test-success.txt with text 'Works!'","cwd":"/tmp","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# Execute
codex mcp-server < /tmp/test.json > /tmp/out.json 2>&1

# Verify NO approval requests
grep 'elicitation' /tmp/out.json
# → Should be EMPTY

# Verify file created
cat /tmp/test-success.txt
# → Should show: Works!
```

✅ If file exists and no elicitation → **autonomous mode works!**

---

## Related Docs

- [interactive-mcp-sessions.md](./interactive-mcp-sessions.md) - Persistent sessions
- [native-background-tasks.md](./native-background-tasks.md) - Background tasks in Claude Code
- [monitoring-codex-output.md](./monitoring-codex-output.md) - Output analysis

---

**Last updated**: 2025-10-14
