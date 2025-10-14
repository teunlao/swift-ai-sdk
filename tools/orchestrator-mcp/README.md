# Orchestrator MCP Server

MCP server for orchestrating parallel Codex agents with automatic recovery and monitoring.

## Features

- 🚀 Launch agents in isolated Git worktrees
- 📊 Real-time status monitoring
- 🔄 Automatic stuck detection and recovery
- 📝 Centralized logging and history
- 🎯 Task Master integration
- ⚡ Scale to multiple agents simultaneously
- 🤖 Flow-file automation for executor → validator cycles

## Automation Workflow

1. Executors and validators launch with system prompts that standardize `.orchestrator/` artifacts.
2. Executors maintain `.orchestrator/flow/<executor-id>.json` and publish Markdown requests in `.orchestrator/requests/` when ready.
3. The automation engine watches flow files, opens validation sessions, and launches a validator in the same worktree.
4. Validators write reports under `.orchestrator/reports/` and update their own flow state; automation finalizes the session.
5. Rejections trigger an automatic `continue_agent` prompt, looping until the validator approves or a blocker is raised.

## Installation

```bash
cd tools/orchestrator-mcp
npm install
npm run build
```

## Usage

### Start the MCP server

```bash
npm start
```

### Available MCP Tools

1. **launch_agent** - Launch a new agent
2. **status** - Get agent status
3. **get_logs** - Retrieve agent logs
4. **kill_agent** - Stop an agent
5. **auto_recover** - Enable automatic recovery
6. **scale** - Launch multiple agents
7. **get_history** - View execution history
8. **request_validation** - Create validation session for executor
9. **assign_validator** - Attach validator to executor worktree
10. **submit_validation** - Record validation verdict
11. **get_validation** - Inspect validation session details

## Development

```bash
npm run dev    # Watch mode
npm run build  # Build
npm test       # Run tests
```

## Configuration

See `docs/orchestrator-mcp-plan.md` and `plan/orchestrator-automation.md` for full documentation.
