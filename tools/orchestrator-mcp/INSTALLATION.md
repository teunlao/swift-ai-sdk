# Orchestrator MCP - Установка

## 1. Добавить в Claude Code конфигурацию

Файл: `~/.config/claude/config.json` (или аналогичный для вашей ОС)

```json
{
  "mcpServers": {
    "orchestrator": {
      "command": "node",
      "args": ["/Users/teunlao/projects/public/swift-ai-sdk/tools/orchestrator-mcp/dist/server.js"],
      "env": {
        "PROJECT_ROOT": "/Users/teunlao/projects/public/swift-ai-sdk",
        "DATABASE_PATH": "/Users/teunlao/projects/public/swift-ai-sdk/tools/orchestrator-mcp/orchestrator.db"
      }
    }
  }
}
```

## 2. После регистрации будут доступны команды:

```bash
# Запуск агента
mcp__orchestrator__launch_agent --role=executor --task_id="10.3" --worktree=auto --prompt="..."

# Статус
mcp__orchestrator__status --format=summary

# Логи
mcp__orchestrator__get_logs --agent_id="executor-123" --filter=all

# Убить агента
mcp__orchestrator__kill_agent --agent_id="executor-123" --cleanup_worktree=false

# История
mcp__orchestrator__get_history --task_id="10.3"

# Массовый запуск
mcp__orchestrator__scale --tasks=["6.2","10.2","10.3"] --role=executor

# Авто-восстановление
mcp__orchestrator__auto_recover --enable=true --stuck_threshold_minutes=10
```

## 3. Перезапустить Claude Code

После добавления конфигурации нужно перезапустить Claude Code, чтобы MCP сервер загрузился.

## 4. Проверка

```bash
# В Claude Code станут доступны:
mcp__orchestrator__status
mcp__orchestrator__launch_agent
# и т.д.
```

## Текущий статус

❌ **Orchestrator НЕ зарегистрирован** - поэтому используются ручные JSON-RPC вызовы
✅ **После регистрации** - будут работать прямые MCP команды как в Task Master
