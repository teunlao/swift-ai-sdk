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
mcp__taskmaster__get_tasks
projectRoot: /path/to/swift-ai-sdk
```

Options:
- `status: "pending"` — filter by status
- `tag: "block-d"` — filter by tag
- `withSubtasks: true` — include subtasks

### Get Next Task

```
mcp__taskmaster__next_task
projectRoot: /path/to/swift-ai-sdk
tag: "block-d"  # optional filter
```

Automatically finds next available task considering dependencies.

### Add Task (Manual)

```
mcp__taskmaster__add_task
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
mcp__taskmaster__add_subtask
projectRoot: /path/to/swift-ai-sdk
taskId: "1"
title: "Write tests for PrepareTools"
description: "Port all tests from prepare-tools.test.ts"
status: "pending"
```

### Update Task Status

```
mcp__taskmaster__set_task_status
projectRoot: /path/to/swift-ai-sdk
id: "1.2"
status: "done"
```

Status values: `pending`, `in-progress`, `done`, `review`, `deferred`, `cancelled`

### Add Dependencies

```
mcp__taskmaster__add_dependency
projectRoot: /path/to/swift-ai-sdk
id: "2.1"
dependsOn: "1.2"
```

Task 2.1 will be blocked until task 1.2 is done.

### ❌ Update Task — NOT AVAILABLE IN MANUAL MODE

```
❌ FORBIDDEN: mcp__taskmaster__update_task
❌ FORBIDDEN: mcp__taskmaster__update_subtask
```

**Why**: `prompt` is a **required parameter** for these tools. They ALWAYS trigger AI generation.

**Manual alternatives**:
- Change status: `mcp__taskmaster__set_task_status`
- Change other fields: Edit `.taskmaster/tasks/tasks.json` directly
- Or recreate the task with correct values

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

Task Master is the **primary** task management system:

### Task Master (Primary)
- Provides structured view with dependencies
- Helps find next task automatically
- Tracks status across multiple agents
- Useful for complex multi-block work

### Other Systems
- `.sessions/` — Session contexts for multi-session work
- `.validation/` — Validation workflow
- `plan/design-decisions.md` — Important technical decisions
- `plan/*-guide.md` — Process documentation

**Rule**: Document important technical decisions in `plan/design-decisions.md`.

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
- Never - Task Master is the primary task management system

---

## Files

```
.taskmaster/                  # Gitignored (each dev installs if needed)
├── tasks/
│   └── tasks.json           # Task database (if you use it)
├── config.json              # Configuration
└── ...

.claude/commands/tm/         # Committed (slash commands)
# Task Master MCP server configured globally (no local config needed)
```

---

## Example Workflow

### 1. Initial Setup (Optional, for those who want to use it)

Task Master is already initialized. Just use MCP tools.

### 2. Add Tasks Manually

```
# Add main task
mcp__taskmaster__add_task
  title: "Implement Block D: PrepareTools"
  description: "Port prepare-tools.ts from upstream"
  tag: "block-d"
  priority: "high"

# Add subtasks
mcp__taskmaster__add_subtask
  taskId: "1"
  title: "Implement prepareTools function"
  description: "Core function implementation"

mcp__taskmaster__add_subtask
  taskId: "1"
  title: "Port all tests"
  description: "15 tests from prepare-tools.test.ts"
```

### 3. Work on Tasks

```
# Get next task
mcp__taskmaster__next_task

# Mark as in progress
mcp__taskmaster__set_task_status
  id: "1.1"
  status: "in-progress"

# ... implement ...

# Mark as done
mcp__taskmaster__set_task_status
  id: "1.1"
  status: "done"
```

### 4. Track Dependencies

```
# Block E depends on Block D
mcp__taskmaster__add_dependency
  id: "5"      # Block E task
  dependsOn: "4"  # Block D task

# Now next_task won't return task 5 until task 4 is done
```

---

## Troubleshooting

### "No valid tasks found"

Task Master is initialized but no tasks created yet. This is normal. Either:
- Create tasks manually via `add_task`
- Task Master is the primary system

### Want to disable Task Master?

Task Master is optional but provides structured task management. If not using it, track work through git commits and design-decisions.md.

The `.taskmaster/` directory is gitignored, so it won't affect other developers.

---

## Quick Reference

| Operation | MCP Tool |
|-----------|----------|
| View all tasks | `mcp__taskmaster__get_tasks` |
| Get next task | `mcp__taskmaster__next_task` |
| Add task | `mcp__taskmaster__add_task` |
| Add subtask | `mcp__taskmaster__add_subtask` |
| Update status | `mcp__taskmaster__set_task_status` |
| Add dependency | `mcp__taskmaster__add_dependency` |
| Remove dependency | `mcp__taskmaster__remove_dependency` |
| Get specific task | `mcp__taskmaster__get_task` |
| Validate dependencies | `mcp__taskmaster__validate_dependencies` |

---

**Remember**: Task Master is a tool, not a requirement. Use it if it helps, ignore it if it doesn't.

*Last updated: 2025-10-12*
