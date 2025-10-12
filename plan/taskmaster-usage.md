# Task Master Usage Guide

## Overview

Task Master AI is available as an **optional structured task tracker** for this project.

**Important**: We use it in **manual mode only** (no AI features, no API keys needed).

---

## Key Principles

### ❌ Do NOT Use
- `--research` flag
- `parse-prd` with AI generation
- `expand-task` with AI
- `add-task --prompt` with AI generation
- Any feature requiring API keys

### ✅ DO Use
- Manual task creation with explicit text
- Structured task database with IDs
- Tags for organization (block-a, block-b, etc.)
- Dependencies tracking between tasks
- Status management (pending/in-progress/done/review/cancelled)
- Subtasks for breaking down complex tasks

---

## Basic Operations (via MCP)

### View Tasks

```
mcp__taskmaster-ai__get_tasks
projectRoot: /path/to/swift-ai-sdk
```

Options:
- `status: "pending"` — filter by status
- `tag: "block-d"` — filter by tag
- `withSubtasks: true` — include subtasks

### Get Next Task

```
mcp__taskmaster-ai__next_task
projectRoot: /path/to/swift-ai-sdk
tag: "block-d"  # optional filter
```

Automatically finds next available task considering dependencies.

### Add Task (Manual)

```
mcp__taskmaster-ai__add_task
projectRoot: /path/to/swift-ai-sdk
title: "Implement PrepareTools function"
description: "Port prepareTools from @ai-sdk/ai/src/generate-text/prepare-tools.ts"
details: "- Convert CoreTool[] to LanguageModelTool[]\n- Handle toolChoice parameter\n- Match upstream behavior exactly"
priority: "high"
tag: "block-d"
```

**No `prompt` parameter** — we provide explicit text, not AI generation.

### Add Subtask

```
mcp__taskmaster-ai__add_subtask
projectRoot: /path/to/swift-ai-sdk
taskId: "1"
title: "Write tests for PrepareTools"
description: "Port all tests from prepare-tools.test.ts"
status: "pending"
```

### Update Task Status

```
mcp__taskmaster-ai__set_task_status
projectRoot: /path/to/swift-ai-sdk
id: "1.2"
status: "done"
```

Status values: `pending`, `in-progress`, `done`, `review`, `deferred`, `cancelled`

### Add Dependencies

```
mcp__taskmaster-ai__add_dependency
projectRoot: /path/to/swift-ai-sdk
id: "2.1"
dependsOn: "1.2"
```

Task 2.1 will be blocked until task 1.2 is done.

### Update Task (Manual)

```
mcp__taskmaster-ai__update_task
projectRoot: /path/to/swift-ai-sdk
id: "1.2"
prompt: "Added implementation notes:\n- Function signature matches upstream\n- All 15 tests passing"
append: true
```

**Note**: `prompt` here is just text content to append, NOT AI generation.

---

## Task ID Format

- Main tasks: `1`, `2`, `3`, etc.
- Subtasks: `1.1`, `1.2`, `1.3`, etc.
- Sub-subtasks: `1.1.1`, `1.1.2`, etc.

---

## Tags for Organization

Recommended tags matching our blocks:

- `block-a` — Provider interfaces
- `block-b` — Provider utils
- `block-c` — Errors
- `block-d` — Prompt utilities
- `block-e` — Generate text
- `block-f` — Streams
- `tests` — Testing tasks
- `docs` — Documentation tasks
- `bugfix` — Bug fixes
- `refactor` — Refactoring tasks

---

## Integration with Existing Workflow

Task Master is **optional** and **supplements** (not replaces) existing docs:

### Primary Sources (Always Used)
- `plan/todo.md` — High-level plan with blocks A-O
- `plan/progress.md` — Session history and completed work
- `.sessions/` — Session contexts for multi-session work
- `.validation/` — Validation workflow

### Task Master (Optional)
- Provides structured view with dependencies
- Helps find next task automatically
- Tracks status across multiple agents
- Useful for complex multi-block work

**Rule**: If task is in Task Master, keep both `plan/progress.md` and Task Master in sync.

---

## When to Use Task Master

### ✅ Good Use Cases
- Complex projects with many dependencies
- Multiple agents working in parallel
- Need to track "what's next" automatically
- Want structured task hierarchy
- Working on multiple blocks simultaneously

### ❌ Not Worth It For
- Simple linear tasks
- Single-block implementation
- Quick one-off fixes
- When `plan/todo.md` is sufficient

---

## Files

```
.taskmaster/                  # Gitignored (each dev installs if needed)
├── tasks/
│   └── tasks.json           # Task database (if you use it)
├── config.json              # Configuration
└── ...

.claude/commands/tm/         # Committed (slash commands)
.mcp.json                    # Committed (MCP config, optional)
```

---

## Example Workflow

### 1. Initial Setup (Optional, for those who want to use it)

Task Master is already initialized. Just use MCP tools.

### 2. Add Tasks Manually

```
# Add main task
mcp__taskmaster-ai__add_task
  title: "Implement Block D: PrepareTools"
  description: "Port prepare-tools.ts from upstream"
  tag: "block-d"
  priority: "high"

# Add subtasks
mcp__taskmaster-ai__add_subtask
  taskId: "1"
  title: "Implement prepareTools function"
  description: "Core function implementation"

mcp__taskmaster-ai__add_subtask
  taskId: "1"
  title: "Port all tests"
  description: "15 tests from prepare-tools.test.ts"
```

### 3. Work on Tasks

```
# Get next task
mcp__taskmaster-ai__next_task

# Mark as in progress
mcp__taskmaster-ai__set_task_status
  id: "1.1"
  status: "in-progress"

# ... implement ...

# Mark as done
mcp__taskmaster-ai__set_task_status
  id: "1.1"
  status: "done"
```

### 4. Track Dependencies

```
# Block E depends on Block D
mcp__taskmaster-ai__add_dependency
  id: "5"      # Block E task
  dependsOn: "4"  # Block D task

# Now next_task won't return task 5 until task 4 is done
```

---

## Troubleshooting

### "No valid tasks found"

Task Master is initialized but no tasks created yet. This is normal. Either:
- Create tasks manually via `add_task`
- Or continue using `plan/todo.md`

### Want to disable Task Master?

Just don't use it! Everything works from `plan/todo.md` and `plan/progress.md`.

The `.taskmaster/` directory is gitignored, so it won't affect other developers.

---

## Quick Reference

| Operation | MCP Tool |
|-----------|----------|
| View all tasks | `mcp__taskmaster-ai__get_tasks` |
| Get next task | `mcp__taskmaster-ai__next_task` |
| Add task | `mcp__taskmaster-ai__add_task` |
| Add subtask | `mcp__taskmaster-ai__add_subtask` |
| Update status | `mcp__taskmaster-ai__set_task_status` |
| Add dependency | `mcp__taskmaster-ai__add_dependency` |
| Remove dependency | `mcp__taskmaster-ai__remove_dependency` |
| Get specific task | `mcp__taskmaster-ai__get_task` |
| Validate dependencies | `mcp__taskmaster-ai__validate_dependencies` |

---

**Remember**: Task Master is a tool, not a requirement. Use it if it helps, ignore it if it doesn't.

*Last updated: 2025-10-12*
