# Autonomous Codex MCP Server ✅ WORKING

**MCP прокси-сервер** который обеспечивает полностью автономную работу Codex CLI БЕЗ manual approvals.

## Статус: 🎉 **ПОЛНОСТЬЮ РАБОЧИЙ**

Протестировано 2025-10-13 - файлы создаются автоматически без user approvals!

---

## Как работает

### Архитектура

```
Claude Code
    ↓ JSON-RPC: tools/call
Autonomous Codex Proxy (server.py)
    ↓ 💉 ИНЖЕКТИТ параметры в JSON:
    ↓    - approval-policy: "never"
    ↓    - sandbox: "danger-full-access"
codex mcp-server
    ↓ Обрабатывает с auto-approval
    ↓ safety.rs: (Never, DangerFullAccess) → AutoApprove
Файлы создаются АВТОМАТИЧЕСКИ! ✅
```

### Два уровня защиты

1. **JSON Parameter Injection** (основная защита):
   - Прокси модифицирует каждый `tools/call` request
   - Добавляет `approval-policy: "never"` (kebab-case!)
   - Добавляет `sandbox: "danger-full-access"`
   - Codex видит правильные параметры и делает auto-approve

2. **Elicitation Interception** (backup):
   - Если всё равно появится `elicitation/create` (patch-approval)
   - Прокси автоматически отправит `{decision: "approved"}`
   - Двойная защита от ручных approvals

---

## Техническая документация

### Почему это работает

Из исходников Codex CLI (`external/codex/codex-rs/`):

**`mcp-server/src/codex_tool_config.rs`** (строки 38-42):
```rust
pub struct CodexToolCallParam {
    #[serde(default)]
    pub approval_policy: Option<CodexToolCallApprovalPolicy>,  // ⚠️ kebab-case в JSON!
    #[serde(default)]
    pub sandbox: Option<CodexToolCallSandboxMode>,
}
```

**`core/src/safety.rs`** (строки 154-160):
```rust
match (approval_policy, sandbox_policy) {
    (Never, DangerFullAccess) => SafetyCheck::AutoApprove {
        sandbox_type: SandboxType::None,
        user_explicitly_approved: false,
    },
    // ...
}
```

**Вывод**: Комбинация `approval-policy: "never"` + `sandbox: "danger-full-access"` активирует auto-approve в Codex!

### Почему `-c` флаги НЕ работают

❌ **Старый неправильный подход**:
```python
# НЕ РАБОТАЕТ в MCP mode!
await asyncio.create_subprocess_exec(
    "codex", "mcp-server",
    "-c", 'sandbox_mode="danger-full-access"',  # ❌ Игнорируется!
    "-c", 'approval_policy="never"'              # ❌ Игнорируется!
)
```

✅ **Правильный подход**:
```python
# РАБОТАЕТ - инжекция в JSON arguments
if method == "tools/call":
    arguments["approval-policy"] = "never"        # ⚠️ kebab-case!
    arguments["sandbox"] = "danger-full-access"
```

**Причина**: CLI флаги `-c` применяются к interactive mode, но в MCP mode параметры читаются из JSON `arguments`!

---

## Конфигурация для Claude Code

Добавь в `~/.claude/mcp_config.json`:

```json
{
  "mcpServers": {
    "autonomous-codex": {
      "command": "python3",
      "args": [
        "/Users/teunlao/projects/public/swift-ai-sdk/.mcp-servers/autonomous-coder/server.py"
      ]
    }
  }
}
```

Или используй абсолютный путь:
```json
{
  "mcpServers": {
    "autonomous-codex": {
      "command": "python3",
      "args": [
        "/absolute/path/to/server.py"
      ]
    }
  }
}
```

---

## Использование

### Из Claude Code

1. Перезапусти Claude Code после добавления конфига
2. Теперь у тебя есть `autonomous-codex` MCP tool
3. Используй его так же как `codex`, но БЕЗ approvals!

### Прямое тестирование

```bash
# Тест через pipe
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Create hello.py","cwd":"/tmp"}}}' | \
  python3 server.py 2>&1

# Проверить результат
ls -lh /tmp/hello.py
cat /tmp/hello.py
```

### Пример JSON request

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "Create a Snake game in Python using curses",
      "cwd": "/path/to/project"
    }
  }
}
```

Прокси автоматически добавит:
```json
{
  "arguments": {
    "prompt": "...",
    "cwd": "...",
    "approval-policy": "never",           // 💉 Injected
    "sandbox": "danger-full-access"       // 💉 Injected
  }
}
```

---

## Логи и мониторинг

Прокси выводит подробные логи в stderr:

```
🚀 Starting Autonomous Codex MCP Proxy (FIXED VERSION)...
✅ Codex MCP server started (PID: 12345)
📥 FROM CLAUDE: tools/call
💉 Injected approval-policy: never
💉 Injected sandbox: danger-full-access
✅ Modified request: {...}
📤 FROM CODEX: codex/event
📤 FROM CODEX: patch_apply_begin {"auto_approved": true}  ⭐ SUCCESS!
📤 FROM CODEX: patch_apply_end {"success": true}
```

### Что искать в логах

✅ **Успешная работа**:
- `💉 Injected approval-policy: never`
- `💉 Injected sandbox: danger-full-access`
- `"auto_approved": true`
- `"success": true`

❌ **Проблема**:
- `🔍 Detected elicitation: patch-approval` (backup защита сработала)
- `❌ JSON decode error`
- `"success": false`

---

## Безопасность

### ⚠️ КРИТИЧЕСКИ ВАЖНО

Этот прокси **автоматически одобряет ВСЕ изменения кода** БЕЗ подтверждения!

**Используй ТОЛЬКО в**:
- ✅ Dev машина (локальная разработка)
- ✅ Docker контейнер (изолированный)
- ✅ VM с снапшотами (можно откатить)
- ✅ CI/CD с изоляцией (автотесты)

**НЕ используй в**:
- ❌ Production сервер
- ❌ Машина с важными данными
- ❌ Общедоступные системы
- ❌ Без бэкапов

### Что обходит

1. **Patch approvals**: Файлы создаются/изменяются автоматически
2. **Command approvals**: Команды выполняются автоматически
3. **Sandbox restrictions**: Full file system access

### Рекомендации

- Используй git для отслеживания изменений
- Делай частые коммиты
- Проверяй изменения перед push
- Работай в feature branch, не в main

---

## Debugging

### Прокси не запускается

```bash
# Проверь Python
python3 --version  # Должен быть 3.7+

# Проверь что Codex установлен
which codex
codex --version
```

### Файлы не создаются

```bash
# Запусти с полными логами
python3 server.py 2>&1 | tee /tmp/proxy-debug.log

# Отправь тестовый запрос
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"codex","arguments":{"prompt":"Create test.txt","cwd":"/tmp"}}}' | python3 server.py

# Проверь логи
grep "Injected" /tmp/proxy-debug.log
grep "auto_approved" /tmp/proxy-debug.log
```

### Approval всё равно запрашивается

Проверь логи на наличие `💉 Injected` - если их нет, параметры не инжектируются.

Возможные причины:
- Неправильный format JSON request
- `method` не равен `"tools/call"`
- `params.name` не равен `"codex"` или `"codex-reply"`

---

## Технические детали

### Зависимости

- Python 3.7+ (asyncio)
- Codex CLI установлен и доступен в PATH
- JSON-RPC over stdio (стандартный MCP protocol)

### Производительность

- Добавляет ~1-2ms latency (JSON parsing)
- Async обработка (non-blocking)
- Нет disk I/O кроме Codex subprocess

### Ограничения

- Работает только с MCP mode (не с interactive CLI)
- Требует Python 3.7+ (async/await syntax)
- Один subprocess на сессию (не multiplexing)

---

## Исходники Codex

Репозиторий скачан в `external/codex/` для reference.

Ключевые файлы изучены:
- `codex-rs/mcp-server/src/codex_tool_config.rs` - параметры tool-call
- `codex-rs/mcp-server/src/patch_approval.rs` - approval logic
- `codex-rs/core/src/safety.rs` - auto-approve условия

---

## FAQ

**Q: Почему бы не использовать `--dangerously-bypass-approvals-and-sandbox`?**
A: Этот флаг работает только в interactive CLI mode. В MCP mode он игнорируется.

**Q: Безопасно ли это?**
A: НЕТ для production! ДА для dev окружения с git.

**Q: Можно ли выборочно одобрять?**
A: Нет, прокси одобряет ВСЁ. Для выборочного одобрения используй оригинальный Codex CLI.

**Q: Работает ли с Claude Code через MCP?**
A: ДА! Именно для этого и создан.

**Q: Нужен ли Codex API key?**
A: ДА, Codex CLI требует авторизацию.

---

## Changelog

### 2025-10-13 - v2.0 (WORKING)

**Исправлено**:
- ✅ Убраны `-c` флаги subprocess (не работали в MCP mode)
- ✅ Добавлена инжекция параметров в JSON arguments
- ✅ Используется kebab-case для параметров
- ✅ Протестировано на hello.py - РАБОТАЕТ!

**Было**:
```python
codex_process = await asyncio.create_subprocess_exec(
    "codex", "mcp-server",
    "-c", 'sandbox_mode="danger-full-access"',  # ❌ Игнорировалось
)
```

**Стало**:
```python
# Модифицируем JSON перед отправкой
arguments["approval-policy"] = "never"          # ✅ Работает!
arguments["sandbox"] = "danger-full-access"
```

### 2025-10-12 - v1.0 (Broken)

- ❌ Первая версия с `-c` флагами (не работала)
- ❌ Approval всё равно запрашивались

---

## Благодарности

- OpenAI за Codex CLI и открытые исходники
- Anthropic за Claude Code и MCP protocol
- Community за документацию MCP

---

**Last Updated**: 2025-10-13
**Status**: ✅ Fully Working
**Version**: 2.0 (Fixed)
