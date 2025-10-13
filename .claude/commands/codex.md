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
# Default (uses config: gpt-5-codex with high reasoning)
codex exec "question here"

# Override model
codex exec -m gpt-5 "question here"
codex exec -m gpt-5-codex "question here"

# Override reasoning effort
codex exec -c model_reasoning_effort="low" "question here"
codex exec -c model_reasoning_effort="medium" "question here"
codex exec -c model_reasoning_effort="high" "question here"

# Combined overrides
codex exec -m gpt-5 -c model_reasoning_effort="medium" "question here"
```

3. Set timeout: 120000ms (2 minutes) for Codex processing time
4. Sandbox: read-only (safe, already in config)

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
codex exec -c model_reasoning_effort="high" "What's the best Swift pattern for AsyncSequence-based return types?"
```

### User types:
```
/codex Should I use struct or class for this data model? --model=gpt-5 --reasoning=low
```

### You execute:
```bash
codex exec -m gpt-5 -c model_reasoning_effort="low" "Should I use struct or class for this data model?"
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

## Implementation Instructions

1. Parse `$ARGUMENTS` to extract:
   - `--model=VALUE` → set model flag
   - `--reasoning=VALUE` → set reasoning config
   - Remaining text → actual question

2. Build command:
   ```bash
   codex exec [model flag if specified] [reasoning config if specified] "question"
   ```

3. Use Bash tool with timeout=120000ms

4. Extract Codex's answer (after "codex" section in output)

5. Present result clearly to user

---

## Error Handling

- If github MCP timeout occurs, ignore it (it's disabled in config)
- If context7 or taskmaster MCP timeout, continue if answer exists
- If Codex itself fails, report error to user
- Always show token usage from output

---

**Working directory:** /Users/teunlao/projects/public/swift-ai-sdk
