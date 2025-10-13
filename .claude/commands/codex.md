---
description: Query Codex CLI for complex architectural/design decisions
argument-hint: <question> [--model=MODEL] [--reasoning=LEVEL]
---

# Codex Query Command

Use OpenAI Codex CLI to get expert advice on complex architectural decisions, Swift patterns, and design choices.

**User query:** $ARGUMENTS

---

## When to Use Codex

✅ **USE CODEX FOR:**
- Complex architectural decisions (e.g., how to port TypeScript union types to Swift)
- Evaluating multiple implementation approaches
- Swift-specific patterns and best practices
- Performance optimization strategies
- Design pattern recommendations
- Edge case analysis

❌ **DON'T USE CODEX FOR:**
- Simple lookups (use regular tools)
- Code generation (you handle that)
- Basic syntax questions

---

## Available Models

### 1. `gpt-5` (Default)
- General-purpose reasoning model
- Best for: Broad architectural questions, cross-language design patterns
- Default reasoning: medium

### 2. `gpt-5-codex`
- Code-specialized reasoning model
- Best for: Swift-specific patterns, implementation details, code optimization
- Default reasoning: high (in our config)
- **Recommended for this project**

---

## Reasoning Effort Levels

| Level | Use Case | Token Cost | Speed |
|-------|----------|------------|-------|
| **low** | Quick answers, straightforward questions | Lowest | Fastest |
| **medium** | Balanced analysis, moderate complexity | Medium | Moderate |
| **high** | Deep analysis, complex architectural decisions | Highest | Slowest |

**Note:** Higher reasoning = more thorough analysis but slower and more expensive.

---

## How to Execute

### Parse User Arguments

The user can specify model and reasoning in their query:
- `--model=gpt-5` or `--model=gpt-5-codex`
- `--reasoning=low|medium|high`

If not specified, use defaults from config:
- Model: `gpt-5-codex` (from config.toml)
- Reasoning: `high` (from config.toml)

### Build Command

1. Extract model and reasoning flags from `$ARGUMENTS`
2. Build `codex exec` command:

```bash
# ⚠️ ALWAYS include full permissions flags:
# -c approval_policy="on-failure" -c sandbox="danger-full-access"

# Default (uses config: gpt-5-codex with high reasoning) + FULL PERMISSIONS
codex exec \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "question here"

# Override model + FULL PERMISSIONS
codex exec \
  -m gpt-5 \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "question here"

# Override reasoning effort + FULL PERMISSIONS
codex exec \
  -c model_reasoning_effort="high" \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "question here"

# Combined overrides + FULL PERMISSIONS
codex exec \
  -m gpt-5-codex \
  -c model_reasoning_effort="medium" \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "question here"
```

3. Set timeout: 120000ms (2 minutes) for Codex processing time, or 900000ms (15 minutes) for deep analysis
4. For long tasks, use Bash tool with `run_in_background=true`

### Extract and Present Result

- Parse Codex output (it includes session info, thinking, and answer)
- Extract the final answer after "codex" section
- Present cleanly to the user
- If errors occur but answer exists, show both

---

## Example Usage

### User types:
```
/codex What's the best Swift pattern for AsyncSequence-based return types? --reasoning=high
```

### You execute:
```bash
codex exec \
  -c model_reasoning_effort="high" \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "What's the best Swift pattern for AsyncSequence-based return types?"
```

### User types:
```
/codex Should I use struct or class for this data model? --model=gpt-5 --reasoning=low
```

### You execute:
```bash
codex exec \
  -m gpt-5 \
  -c model_reasoning_effort="low" \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "Should I use struct or class for this data model?"
```

---

## Current Config

From `~/.codex/config.toml`:
- Default model: `gpt-5-codex`
- Default reasoning: `high`
- Sandbox: `read-only`
- Working directory: swift-ai-sdk project root
- Trust level: `trusted`

---

## ⚠️ IMPORTANT: Full Permissions Required

**CRITICAL**: Codex **MUST** be run with full permissions, otherwise it gets blocked and cannot work.

### Why Full Permissions?

Codex has strict internal instructions requiring escalated permissions for all operations. Without full access:
- ❌ Cannot read files (even with `read-only` sandbox)
- ❌ Cannot analyze codebase structure
- ❌ Gets blocked immediately with permission errors
- ❌ Wastes time and tokens without producing results

### How to Grant Full Permissions

**ALWAYS add these flags to every Codex execution:**

```bash
codex exec \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  [other flags] \
  "your prompt here"
```

**Parameters explained:**
- `approval_policy="on-failure"` - Allow Codex to run commands, ask for approval only if they fail
- `sandbox="danger-full-access"` - Full filesystem and command access

### ⚠️ Safety Through Prompt Engineering

**We grant full permissions BUT control behavior through prompts:**

✅ **GOOD PROMPTS** (request analysis/reports):
```bash
"Analyze the task structure and provide a detailed report..."
"Review the architecture and recommend solutions..."
"Compare implementations and document differences..."
```

❌ **BAD PROMPTS** (request direct actions):
```bash
"Fix all the bugs in the codebase..."
"Refactor these files automatically..."
"Implement the missing features..."
```

**Strategy:**
- ✅ Give full **technical** permissions (so Codex can read/analyze)
- ✅ Request **analytical output** in prompts (reports, recommendations, analysis)
- ✅ **You** implement changes based on Codex's recommendations
- ❌ Don't ask Codex to directly modify code

### Recommended Command Template

For complex analysis tasks (like project audits):

```bash
codex exec \
  -m gpt-5-codex \
  -c model_reasoning_effort="high" \
  -c approval_policy="on-failure" \
  -c sandbox="danger-full-access" \
  "Your detailed analysis request here...

  ## Deliverables
  Provide a comprehensive report with:
  - Analysis findings
  - Recommendations
  - Action items

  DO NOT modify files directly - provide analysis only."
```

### Background Execution

For long-running analysis (>2 minutes), use background execution:

```bash
# Via Bash tool with run_in_background=true
# Set timeout=900000 (15 minutes) for deep analysis
```

---

## Implementation Instructions

1. Parse `$ARGUMENTS` to extract:
   - `--model=VALUE` → set model flag
   - `--reasoning=VALUE` → set reasoning config
   - Remaining text → actual question

2. Build command with **FULL PERMISSIONS ALWAYS INCLUDED**:
   ```bash
   codex exec \
     [model flag if specified] \
     [reasoning config if specified] \
     -c approval_policy="on-failure" \
     -c sandbox="danger-full-access" \
     "question"
   ```

3. Use Bash tool:
   - For quick questions: `timeout=120000ms` (2 minutes)
   - For deep analysis: `timeout=900000ms` (15 minutes) + `run_in_background=true`

4. Extract Codex's answer (after "codex" section in output)

5. Present result clearly to user

**CRITICAL**: Never forget the permission flags! Without them, Codex will fail immediately.

---

## Error Handling

- If github MCP timeout occurs, ignore it (it's disabled in config)
- If context7 or taskmaster MCP timeout, continue if answer exists
- If Codex itself fails, report error to user
- Always show token usage from output

---

**Working directory:** /Users/teunlao/projects/public/swift-ai-sdk
