# Codex MCP Server: Autonomous Mode Guide

**Date**: 2025-10-13 (Updated)
**Purpose**: How to bypass approvals in Codex MCP server for autonomous operation

---

## 🚨 CRITICAL: Always Pass These Parameters

When working with `codex mcp-server` in autonomous mode, you **MUST** pass these parameters in **EVERY** JSON request:

```json
{
  "arguments": {
    "prompt": "Your task here",
    "cwd": "/path/to/workspace",
    "approval-policy": "never",
    "sandbox": "danger-full-access"
  }
}
```

**Key points:**
- ✅ `"approval-policy": "never"` - No approval prompts
- ✅ `"sandbox": "danger-full-access"` - Full file system access
- ✅ **Both parameters required together** - one without the other won't work
- ✅ **kebab-case format** - use dashes, not underscores
- ✅ **Inside `arguments` object** - not at top level

**Without these parameters, Codex will prompt for approval and block autonomous execution!**

---

## Overview

Codex CLI MCP server by default asks for approval before executing commands or modifying files. For autonomous operation (e.g., in CI/CD, containerized environments, or trusted workflows), you need to bypass these approvals.

This guide shows the **ONLY WORKING METHOD** for autonomous Codex MCP operation.

---

## ✅ THE CORRECT METHOD: JSON Parameters

### Single-Shot Request

**File: `request.json`**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create hello.py with print('Hello World')",
      "cwd": "/tmp",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
```

**Execute:**
```bash
codex mcp-server < request.json > output.json 2>&1
```

**Result:** ✅ File created without approval prompts!

---

### Interactive Session (Multiple Commands)

**Step 1: Launch persistent session**
```bash
touch /tmp/codex-commands.jsonl
tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/codex-output.jsonl 2>&1 &
```

**Step 2: Send commands with parameters**
```bash
cat >> /tmp/codex-commands.jsonl <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create test.py",
      "cwd": "/tmp",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
EOF
```

**Step 3: Send more commands (same session)**
```bash
cat >> /tmp/codex-commands.jsonl <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Run test.py",
      "cwd": "/tmp",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
EOF
```

---

### Claude Code Native Background Task

For use with Claude Code's Bash tool with `run_in_background: true`:

```python
# 1. Prepare command buffer
Bash("touch /tmp/codex-commands.jsonl")

# 2. Launch as native background task (NO & operator!)
task_id = Bash(
    command="tail -f /tmp/codex-commands.jsonl | codex mcp-server > /tmp/codex-output.jsonl 2>&1",
    run_in_background=True,  # Native task - visible in TUI!
    timeout=3600000  # 1 hour
)
# → Returns hex ID (e.g., "9de576")

# 3. Send commands with required parameters
Bash("""
cat >> /tmp/codex-commands.jsonl <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Implement feature X",
      "cwd": "/Users/user/project",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
EOF
""")

# 4. Monitor via BashOutput
BashOutput(bash_id=task_id)

# 5. Stop when done
KillShell(shell_id=task_id)
```

---

## ❌ METHODS THAT DON'T WORK

### ❌ Method 1: `-c` Config Flags (DOES NOT WORK)

```bash
# ❌ WRONG - These flags are IGNORED in MCP mode!
codex mcp-server -c 'sandbox_mode="danger-full-access"' \
                 -c 'approval_policy="never"' \
  < input.json > output.json
```

**Why it fails:**
- `-c` flags write to **config file** (startup configuration)
- MCP server reads parameters from **JSON arguments** (runtime)
- Two different sources → parameters never reach the code that checks them

**Verified:** Tested live - files NOT created, approval prompts still appear.

---

### ❌ Method 2: `--dangerously-bypass-approvals-and-sandbox` Flag (DOES NOT EXIST)

```bash
# ❌ WRONG - Flag does not exist for mcp-server!
codex mcp-server --dangerously-bypass-approvals-and-sandbox < input.json > output.json
```

**Error:**
```
error: unexpected argument '--dangerously-bypass-approvals-and-sandbox' found
```

**Why it fails:**
- This flag exists ONLY for `codex` CLI command
- It does NOT exist for `codex mcp-server` subcommand
- Different argument parsers

**Verified:** Tested live - command fails immediately.

---

### ❌ Method 3: Environment Variables (NOT SUPPORTED)

```bash
# ❌ WRONG - Environment variables ignored
export CODEX_SANDBOX_MODE=danger-full-access
export CODEX_APPROVAL_POLICY=never
codex mcp-server < input.json > output.json
```

**Why it fails:**
- MCP server does not read these environment variables
- Parameters must be in JSON arguments

---

## Why JSON Parameters Work

### Architecture Explanation

**Codex MCP Server code structure** (`codex-rs/mcp-server/src/codex_tool_config.rs`):

```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, Default)]
#[serde(rename_all = "kebab-case")]  // ⚠️ kebab-case required!
pub struct CodexToolCallParam {
    pub prompt: String,

    /// Approval policy: `untrusted`, `on-failure`, `on-request`, `never`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval_policy: Option<CodexToolCallApprovalPolicy>,

    /// Sandbox mode: `read-only`, `workspace-write`, `danger-full-access`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sandbox: Option<CodexToolCallSandboxMode>,
}
```

**Key observations:**
1. Structure deserializes **from JSON arguments** (not config file!)
2. `#[serde(rename_all = "kebab-case")]` - parameters use kebab-case
3. `Option<...>` - parameters are optional
4. If `None` → uses DEFAULT (read-only + approval required)

**Safety check** (`codex-rs/core/src/safety.rs`):

```rust
match (approval_policy, sandbox_policy) {
    (Never, DangerFullAccess) => SafetyCheck::AutoApprove {
        sandbox_type: SandboxType::None,
        user_explicitly_approved: false,
    },
    // ... other combinations
}
```

**Auto-approve conditions:**
- `approval_policy == Never` **AND** `sandbox == DangerFullAccess`
- → `AutoApprove` without user prompt

**This is why BOTH parameters are required together!**

---

## Parameter Reference

### `approval-policy` Values

| Value | Behavior |
|-------|----------|
| `"never"` | ✅ Auto-approve all actions (autonomous mode) |
| `"on-failure"` | Ask only if command fails |
| `"on-request"` | Ask before every command (default) |
| `"untrusted"` | Enhanced security prompts |

**For autonomous mode:** Always use `"never"`

---

### `sandbox` Values

| Value | Behavior |
|-------|----------|
| `"read-only"` | Can read files, cannot modify (default) |
| `"workspace-write"` | Can write within workspace only |
| `"danger-full-access"` | ✅ Full system access (autonomous mode) |

**For autonomous mode:** Always use `"danger-full-access"`

---

## Security Considerations

### ⚠️ Use Autonomous Mode Only In:

1. **Docker containers** with mounted volumes
   ```bash
   docker run -v $(pwd):/workspace codex-image
   ```

2. **Virtual machines** with snapshots
   ```bash
   # Take snapshot before running
   vagrant snapshot save before-codex
   ```

3. **CI/CD pipelines** with isolation
   ```yaml
   # GitHub Actions with restricted runner
   runs-on: ubuntu-latest
   ```

4. **Trusted development environments** with version control
   ```bash
   # Ensure git clean state before running
   git status --short  # Should be empty
   ```

### ❌ NEVER Use Autonomous Mode:

1. On production servers
2. With untrusted prompts
3. On host machine with important data
4. Without backups or version control
5. In shared environments

---

## Complete Examples

### Example 1: Create and Run Python Script

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create hello.py with 'print(\"Hello World\")' and run it",
      "cwd": "/tmp",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
```

```bash
echo '<JSON above>' | codex mcp-server > output.json 2>&1
```

---

### Example 2: Multi-File Project

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create a Python project: main.py, utils.py, test_main.py. Run tests.",
      "cwd": "/tmp/myproject",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
```

---

### Example 3: Read-Write-Execute Workflow

**Interactive session:**

```bash
# Launch session
touch /tmp/cmds.jsonl
tail -f /tmp/cmds.jsonl | codex mcp-server > /tmp/out.jsonl 2>&1 &

# Command 1: Analyze
cat >> /tmp/cmds.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Analyze Sources/SwiftAISDK/Core/ structure","cwd":"/Users/user/swift-ai-sdk","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# Command 2: Implement
cat >> /tmp/cmds.jsonl <<'EOF'
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Create GenerateText.swift based on upstream","cwd":"/Users/user/swift-ai-sdk","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF

# Command 3: Test
cat >> /tmp/cmds.jsonl <<'EOF'
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Run swift test for GenerateText","cwd":"/Users/user/swift-ai-sdk","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
```

---

## Helper Functions

### Bash Function

```bash
#!/bin/bash
# autonomous-codex.sh

CMDS=/tmp/codex-commands.jsonl
OUT=/tmp/codex-output.jsonl

# Send autonomous command
send_codex() {
  local prompt="$1"
  local id="${2:-1}"
  local cwd="${3:-$PWD}"

  cat >> "$CMDS" <<EOF
{"jsonrpc":"2.0","id":$id,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"$prompt","cwd":"$cwd","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
  echo "✅ Sent command ID $id"
}

# Usage
touch "$CMDS"
tail -f "$CMDS" | codex mcp-server > "$OUT" 2>&1 &
echo "Session PID: $!"

send_codex "Create hello.py" 1 "/tmp"
sleep 10
send_codex "Run hello.py" 2 "/tmp"
```

---

### Python Class

```python
#!/usr/bin/env python3
"""
Autonomous Codex MCP Client
"""

import json
import subprocess
import time
from pathlib import Path

class AutonomousCodex:
    def __init__(self, commands_file="/tmp/codex-commands.jsonl",
                 output_file="/tmp/codex-output.jsonl"):
        self.commands_file = Path(commands_file)
        self.output_file = Path(output_file)
        self.process = None
        self.request_id = 1

    def start(self):
        """Start persistent MCP session"""
        self.commands_file.touch()
        self.output_file.touch()

        cmd = f"tail -f {self.commands_file} | codex mcp-server > {self.output_file} 2>&1"
        self.process = subprocess.Popen(cmd, shell=True)
        print(f"✅ Session started (PID: {self.process.pid})")
        time.sleep(2)

    def send(self, prompt, cwd=None, **kwargs):
        """Send autonomous command"""
        cwd = cwd or str(Path.cwd())

        request = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": "tools/call",
            "params": {
                "name": "codex",
                "arguments": {
                    "prompt": prompt,
                    "cwd": cwd,
                    "approval-policy": "never",        # 🔥 Auto-approve
                    "sandbox": "danger-full-access",   # 🔥 Full access
                    **kwargs
                }
            }
        }

        with open(self.commands_file, "a") as f:
            f.write(json.dumps(request) + "\n")

        print(f"📤 Command {self.request_id}: {prompt[:50]}...")
        self.request_id += 1

    def stop(self):
        """Stop session"""
        if self.process:
            self.process.terminate()
            self.process.wait()
            print("🛑 Session stopped")

# Usage
if __name__ == "__main__":
    codex = AutonomousCodex()
    codex.start()

    codex.send("Create hello.py with 'print(Hello!)'", cwd="/tmp")
    time.sleep(10)

    codex.send("Run hello.py", cwd="/tmp")
    time.sleep(5)

    codex.stop()
```

---

## Troubleshooting

### Problem: Codex still asks for approval

**Symptoms:**
- Output contains `"codex_elicitation": "exec-approval"`
- Files not created

**Check:**
```bash
# 1. Verify parameters are in JSON
grep approval-policy /tmp/codex-commands.jsonl
# Should show: "approval-policy":"never"

# 2. Check kebab-case (not snake_case)
grep approval_policy /tmp/codex-commands.jsonl
# Should be EMPTY (kebab-case required!)

# 3. Verify both parameters present
grep sandbox /tmp/codex-commands.jsonl
# Should show: "sandbox":"danger-full-access"
```

**Solutions:**
- ✅ Use `"approval-policy"` (kebab-case) not `"approval_policy"`
- ✅ Include BOTH parameters together
- ✅ Place parameters inside `arguments` object

---

### Problem: Commands execute but fail with "permission denied"

**Cause:** Using `"sandbox": "read-only"` or `"workspace-write"`

**Solution:** Use `"danger-full-access"`:
```json
"sandbox": "danger-full-access"
```

---

### Problem: Session dies after first command

**Cause:** Using single-shot mode (direct STDIN) instead of `tail -f`

**Solution:** Use interactive session pattern:
```bash
tail -f commands.jsonl | codex mcp-server > output.jsonl 2>&1 &
```

Not:
```bash
codex mcp-server < commands.jsonl > output.jsonl  # Dies after first command!
```

---

## Verification

### Test if autonomous mode works:

```bash
# 1. Create request
cat > /tmp/test-autonomous.json <<'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create /tmp/test-success.txt with text 'Autonomous mode works!'",
      "cwd": "/tmp",
      "approval-policy": "never",
      "sandbox": "danger-full-access"
    }
  }
}
EOF

# 2. Execute
codex mcp-server < /tmp/test-autonomous.json > /tmp/test-output.json 2>&1

# 3. Verify NO approval requests
grep 'elicitation' /tmp/test-output.json
# Should be EMPTY (no elicitation events)

# 4. Verify file created
cat /tmp/test-success.txt
# Should show: Autonomous mode works!
```

**If file exists and no elicitation found:** ✅ **Autonomous mode WORKS!**

---

## Related Documentation

- **[interactive-mcp-sessions.md](./interactive-mcp-sessions.md)** — Persistent MCP sessions with multiple commands
- **[native-background-tasks.md](./native-background-tasks.md)** — Running Codex as native background task in Claude Code
- **[monitoring-codex-output.md](./monitoring-codex-output.md)** — Monitoring and analyzing Codex MCP output

---

## Quick Reference Card

**For every Codex MCP request, ALWAYS include:**

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

**Remember:**
- ✅ kebab-case (dashes)
- ✅ Both parameters together
- ✅ Inside `arguments`
- ❌ No `-c` flags (don't work)
- ❌ No `--dangerously-bypass...` flag (doesn't exist)

---

**Author**: Claude Code AI
**Date**: 2025-10-13 (Updated based on live testing)
**Tested with**: Codex CLI 0.46.0
**Source**: `.sessions/session-2025-10-13-codex-mcp-discovery.md`
**Last updated**: 2025-10-13
