# Git Worktree Workflow for Multi-Agent Development

**Purpose**: Isolate parallel agents with Git worktrees

---

## Concept

**Git Worktrees** = separate working directories for different branches in one repository.

**Benefits:**
- ✅ Full agent isolation (own directory)
- ✅ Independent builds (`swift build` no conflicts)
- ✅ Parallel testing
- ✅ Easy merge after validation

---

## Structure

```
/Users/teunlao/projects/public/
├── swift-ai-sdk/              # Main (main branch)
│   ├── .git/                  # Shared Git repo
│   └── Sources/
├── swift-ai-sdk-executor-1/   # Worktree 1 (executor-1 branch)
│   ├── .git → ../swift-ai-sdk/.git
│   └── Sources/               # Independent copy!
└── swift-ai-sdk-executor-2/   # Worktree 2 (executor-2 branch)
    ├── .git → ../swift-ai-sdk/.git
    └── Sources/               # Independent copy!
```

**Key**: One `.git` repo, multiple working directories, separate branches.

---

## Quick Start

### 1. Create Worktree

```bash
cd /Users/teunlao/projects/public/swift-ai-sdk

git worktree add ../swift-ai-sdk-executor-N -b executor-N-task-X
```

**Naming:** `executor-N-<description>`, `validator-N-<description>`

### 2. Launch Agent

```bash
# ⚠️ cwd = worktree directory!
cat > /tmp/cmd.json <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"TASK","cwd":"/Users/teunlao/projects/public/swift-ai-sdk-executor-N","approval-policy":"never","sandbox":"danger-full-access"}}}
EOF
cat /tmp/cmd.json >> /tmp/codex-executor-N-commands.jsonl
```

### 3. Monitor

```bash
git worktree list
cd /path/to/worktree && git status
python3 scripts/parse-codex-output.py /tmp/codex-executor-N-output.json --stuck
```

### 4. Merge

```bash
cd /Users/teunlao/projects/public/swift-ai-sdk
git checkout main
git merge executor-N-task-X --no-ff -m "feat: implement task X"
swift build && swift test
git push origin main
```

### 5. Cleanup

```bash
git worktree remove ../swift-ai-sdk-executor-N
git branch -d executor-N-task-X
git worktree prune
```

---

## Agent Rules

### Working Directory

```
cwd: /Users/teunlao/projects/public/swift-ai-sdk-executor-N
```

**NOT main repository!**

### Isolation

- executor-1 creates files in executor-1/
- executor-2 creates files in executor-2/
- Each runs `swift build` independently
- No conflicts!

---

## Common Scenarios

### Parallel Tasks

```bash
# Create worktrees
git worktree add ../swift-ai-sdk-executor-1 -b executor-1-task-2.5
git worktree add ../swift-ai-sdk-executor-2 -b executor-2-task-3.1

# Launch agents (parallel work!)

# Merge after validation
git merge executor-1-task-2.5
git merge executor-2-task-3.1

# Cleanup
git worktree remove ../swift-ai-sdk-executor-1
git worktree remove ../swift-ai-sdk-executor-2
```

### Merge Conflict

```bash
# Both agents modified Package.swift
git merge executor-1-task-2.5  # ✅ OK
git merge executor-2-task-3.1  # ⚠️ CONFLICT

# Resolve manually
vim Package.swift  # Fix <<<< ==== >>>> markers
git add Package.swift
git commit
```

---

## Best Practices

### DO ✅

- Use worktrees for independent tasks (different files)
- Check `git worktree list` regularly
- Merge one at a time, test between
- Specify correct `cwd` in agent JSON

### DON'T ❌

- Don't run agents in main repository
- Don't merge all branches at once
- Don't forget to cleanup worktrees
- Don't use worktrees for dependent tasks

---

## Commands

```bash
# Create
git worktree add ../swift-ai-sdk-executor-N -b executor-N-task-X

# List
git worktree list

# Remove
git worktree remove ../swift-ai-sdk-executor-N

# Cleanup
git worktree prune
```

---

## Troubleshooting

### Worktree exists

```bash
rm -rf /path/to/worktree
git worktree add /path/to/worktree -b branch
```

### Can't remove (dirty)

```bash
cd /path/to/worktree
git add -A && git commit -m "save" || true
rm -rf .build .swiftpm
cd /main && git worktree remove --force /path/to/worktree
```

### Wrong cwd

Check JSON:
- Should be: `/path/to/swift-ai-sdk-executor-N`
- NOT: `/path/to/swift-ai-sdk`

---

## Integration

Works with `docs/multi-agent-coordination.md`:
- Multi-Agent Guide → How to launch agents
- Worktree Guide → Where agents work

---

**Last Updated**: 2025-10-14
