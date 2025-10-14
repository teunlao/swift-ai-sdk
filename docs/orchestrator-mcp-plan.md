# Orchestrator MCP Server - План Реализации

**Дата**: 2025-10-14
**Статус**: Planning
**Цель**: MCP сервер для оркестрации параллельных Codex агентов
**Статус**: Automation-first executor ⇄ validator loop (2025-10-14)

---

## 1. Концепция

### Проблема
- Ручное управление множеством параллельных Codex агентов
- Много bash команд для запуска/мониторинга
- Нет централизованного dashboard
- Сложно масштабировать (>5 агентов)
- Нет автоматического recovery

### Решение
**MCP сервер** с инструментами для:
- Запуска агентов в worktree
- Мониторинга статуса
- Автоматического recovery
- Интеграции с Task Master
- Автоматического цикла валидации через `.orchestrator/flow` артефакты

---

## 2. Архитектура

```
Claude Code (Coordinator)
    ↓ MCP protocol
Orchestrator MCP Server
    ↓ manages
├─> executor-1 (Codex) → worktree-1
├─> executor-2 (Codex) → worktree-2
├─> validator-1 (Codex) → worktree-N
└─> Agent Manager (SQLite DB)
```

### Компоненты

1. **MCP Server** - HTTP transport
2. **Agent Manager** - CRUD для агентов
3. **Worktree Manager** - Git worktree операции
4. **Codex Manager** - Запуск/остановка Codex
5. **Log Parser** - Парсинг output, stuck detection
6. **Automation Engine** - Следит за `.orchestrator/flow` и управляет циклом executor ↔ validator
7. **Database** - SQLite для истории

---

## 3. MCP Tools (API)

### 3.1 launch_agent
**Описание**: Запуск нового агента

**Input**:
```typescript
{
  role: "executor" | "validator",
  task_id?: string,
  worktree: "auto" | "manual",  // auto создаст worktree
  prompt: string,
  cwd?: string  // если manual worktree
}
```

**Output**:
```typescript
{
  agent_id: string,        // "executor-1"
  shell_id: string,        // hex ID
  worktree?: string,       // path
  status: "running"
}
```

**Логика**:
1. Создать worktree (если auto)
2. Запустить tail -f | codex mcp-server
3. Отправить первую команду
4. Сохранить в БД
5. Вернуть результат

---

### 3.2 status
**Описание**: Статус агента(ов)

**Input**:
```typescript
{
  agent_id?: string,  // optional, все или один
  format: "summary" | "detailed"
}
```

**Output (summary)**:
```typescript
{
  agents: [{
    agent_id: "executor-1",
    task_id: "6.2",
    status: "running" | "stuck" | "completed",
    events: 1234,
    files_created: 5,
    uptime: "15m"
  }]
}
```

**Output (detailed)**:
```typescript
{
  agent_id: "executor-1",
  shell_id: "abc123",
  task_id: "6.2",
  worktree: "/path",
  status: "running",
  events: 1234,
  reasoning_count: 500,
  commands_executed: 50,
  patches_applied: 3,
  files_created: ["file1.swift", "file2.swift"],
  last_activity: "2025-10-14T01:00:00Z",
  stuck_detection: {
    is_stuck: false,
    score: 0.2
  }
}
```

**Логика**:
1. Запросить из БД
2. Парсить output файл (parse-codex-output.py)
3. Агрегировать информацию
4. Вернуть результат

---

### 3.3 get_logs
**Описание**: Получить логи агента

**Input**:
```typescript
{
  agent_id: string,
  filter: "reasoning" | "commands" | "errors" | "stuck" | "all",
  last?: number  // последние N событий
}
```

**Output**:
```typescript
{
  agent_id: "executor-1",
  logs: [{
    type: "reasoning" | "command" | "error",
    timestamp: "2025-10-14T01:00:00Z",
    content: "...",
    line_number?: number
  }]
}
```

**Логика**:
1. Читать output файл
2. Применить фильтры
3. Форматировать и вернуть

---

### 3.4 kill_agent
**Описание**: Остановить агента

**Input**:
```typescript
{
  agent_id: string,
  cleanup_worktree?: boolean  // удалить worktree
}
```

**Output**:
```typescript
{
  agent_id: "executor-1",
  status: "killed",
  worktree_removed: boolean
}
```

**Логика**:
1. KillShell с shell_id
2. Обновить статус в БД
3. Удалить worktree (если cleanup=true)
4. Вернуть результат

---

### 3.5 auto_recover
**Описание**: Включить/настроить автоматическое восстановление

**Input**:
```typescript
{
  enable: boolean,
  stuck_threshold_minutes: number,  // default: 10
  max_retries: number  // default: 2
}
```

**Output**:
```typescript
{
  enabled: boolean,
  config: {
    stuck_threshold_minutes: 10,
    max_retries: 2
  }
}
```

**Логика**:
1. Сохранить конфигурацию
2. Запустить background task для мониторинга
3. При обнаружении stuck:
   - Отправить clarification
   - Если не помогло → kill + restart
   - Логировать в БД

---

### 3.6 scale
**Описание**: Массовый запуск агентов

**Input**:
```typescript
{
  tasks: string[],  // ["6.2", "10.2", "10.3"]
  role: "executor" | "validator"
}
```

**Output**:
```typescript
{
  launched: [{
    agent_id: "executor-1",
    task_id: "6.2",
    status: "running"
  }],
  failed: []
}
```

**Логика**:
1. Для каждой задачи:
   - Получить Task Master info
   - Создать worktree
   - Запустить агента
2. Агрегировать результаты

---

### 3.7 get_history
**Описание**: История работы агентов

**Input**:
```typescript
{
  from_date?: string,
  to_date?: string,
  task_id?: string,
  role?: "executor" | "validator"
}
```

**Output**:
```typescript
{
  sessions: [{
    agent_id: "executor-1",
    task_id: "6.2",
    started: "2025-10-14T00:00:00Z",
    ended: "2025-10-14T01:00:00Z",
    duration: "1h",
    status: "completed" | "failed",
    events: 1234,
    result: "success" | "validation_failed"
  }]
}
```

---

## 4. Database Schema (SQLite)

### Table: agents
```sql
CREATE TABLE agents (
  id TEXT PRIMARY KEY,           -- "executor-1"
  role TEXT NOT NULL,            -- "executor" | "validator"
  task_id TEXT,
  shell_id TEXT NOT NULL,
  worktree TEXT,
  prompt TEXT,
  status TEXT NOT NULL,          -- "running" | "stuck" | "completed" | "killed"
  created_at TEXT NOT NULL,
  started_at TEXT,
  ended_at TEXT,
  events_count INTEGER DEFAULT 0,
  commands_count INTEGER DEFAULT 0,
  patches_count INTEGER DEFAULT 0,
  last_activity TEXT,
  stuck_detected BOOLEAN DEFAULT 0,
  auto_recover_attempts INTEGER DEFAULT 0
);
```

### Table: agent_logs
```sql
CREATE TABLE agent_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  agent_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  event_type TEXT,           -- "reasoning" | "command" | "error" | "stuck"
  content TEXT,
  FOREIGN KEY (agent_id) REFERENCES agents(id)
);
```

### Table: config
```sql
CREATE TABLE config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
```

---

## 5. Технический Стек

### Backend
- **Runtime**: Node.js 20+
- **Language**: TypeScript
- **MCP SDK**: `@modelcontextprotocol/sdk`
- **Database**: `better-sqlite3`
- **Process**: `child_process` для Codex
- **Git**: `simple-git`

### Dependencies
```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "better-sqlite3": "^11.0.0",
    "simple-git": "^3.25.0",
    "zod": "^3.23.0",
    "dotenv": "^16.4.0"
  }
}
```

---

## 6. Структура Проекта

```
tools/orchestrator-mcp/
├── src/
│   ├── server.ts              # MCP сервер
│   ├── agent-manager.ts       # CRUD агентов
│   ├── worktree-manager.ts    # Git worktree операции
│   ├── codex-manager.ts       # Запуск Codex
│   ├── log-parser.ts          # Парсинг output
│   ├── database.ts            # SQLite wrapper
│   ├── auto-recovery.ts       # Background monitoring
│   └── types.ts               # TypeScript типы
├── database/
│   └── schema.sql             # SQL схема
├── scripts/
│   └── init-db.ts             # Инициализация БД
├── package.json
├── tsconfig.json
├── .env.example
└── README.md
```

---

## 7. План Имплементации

### Phase 1: MVP (2-3 дня)

**День 1: Core Setup**
- ✅ Инициализация проекта
- ✅ Создание MCP сервера
- ✅ SQLite database setup
- ✅ Базовые типы и интерфейсы

**День 2: Core Tools**
- ✅ `launch_agent` - базовая версия
- ✅ `status` - summary формат
- ✅ `kill_agent`
- ✅ Worktree manager (create, remove)

**День 3: Integration & Testing**
- ✅ `get_logs` - базовый парсинг
- ✅ Интеграция с parse-codex-output.py
- ✅ Тестирование с 3 агентами
- ✅ README и примеры использования

### Phase 2: Advanced Features (2-3 дня)

**День 4-5: Auto Recovery**
- ✅ `auto_recover` tool
- ✅ Background monitoring
- ✅ Stuck detection
- ✅ Automatic clarification

**День 6: Scaling & History**
- ✅ `scale` - массовый запуск
- ✅ `get_history` - статистика
- ✅ Task Master интеграция
- ✅ Export в JSON/CSV

### Phase 3: Polish (1-2 дня)

**День 7-8: Production Ready**
- ✅ Error handling
- ✅ Logging (winston)
- ✅ Configuration file
- ✅ Документация
- ✅ Publish npm package

---

## 8. Примеры Использования

### 8.1 Запуск 3 агентов

```typescript
// В Claude Code:
mcp__orchestrator__scale({
  tasks: ["6.2", "10.2", "10.3"],
  role: "executor"
})

// Результат:
{
  launched: [
    { agent_id: "executor-1", task_id: "6.2", status: "running" },
    { agent_id: "executor-2", task_id: "10.2", status: "running" },
    { agent_id: "executor-3", task_id: "10.3", status: "running" }
  ]
}
```

### 8.2 Проверка статуса

```typescript
mcp__orchestrator__status({ format: "summary" })

// Результат:
{
  agents: [
    {
      agent_id: "executor-1",
      task_id: "6.2",
      status: "running",
      events: 1234,
      files_created: 5
    },
    {
      agent_id: "executor-2",
      task_id: "10.2",
      status: "stuck",
      events: 500,
      files_created: 0
    }
  ]
}
```

### 8.3 Получение логов

```typescript
mcp__orchestrator__get_logs({
  agent_id: "executor-2",
  filter: "stuck",
  last: 50
})

// Результат показывает почему executor-2 застрял
```

### 8.4 Auto Recovery

```typescript
mcp__orchestrator__auto_recover({
  enable: true,
  stuck_threshold_minutes: 10
})

// Orchestrator автоматически мониторит и восстанавливает застрявших агентов
```

---

## 9. Интеграция с Claude Code

### Конфигурация MCP

В `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "orchestrator": {
      "command": "node",
      "args": ["/path/to/orchestrator-mcp/dist/server.js"],
      "env": {
        "PROJECT_ROOT": "/Users/teunlao/projects/public/swift-ai-sdk",
        "DATABASE_PATH": "/path/to/orchestrator.db"
      }
    }
  }
}
```

### Использование

```
Пользователь: "Запусти агентов на задачи 6.2, 10.2, 10.3"

Claude Code: [использует mcp__orchestrator__scale]

Claude Code: "✅ Запущено 3 агента:
- executor-1 → Task 6.2 (worktree: swift-ai-sdk-executor-1)
- executor-2 → Task 10.2 (worktree: swift-ai-sdk-executor-2)
- executor-3 → Task 10.3 (worktree: swift-ai-sdk-executor-3)"
```

---

## 10. Следующие Шаги

### Немедленно
1. ✅ Создать директорию `tools/orchestrator-mcp/`
2. ✅ Инициализировать npm проект
3. ✅ Установить зависимости
4. ✅ Создать базовую структуру

### Этот проект
1. Дождаться завершения текущих агентов
2. Начать Phase 1 (MVP)
3. Протестировать на реальных задачах

### Будущее
1. Вынести в отдельный репозиторий
2. Опубликовать npm package
3. Добавить UI dashboard (опционально)

---

## 11. Оценка ROI

### Вложение
- Разработка: 5-7 дней
- ~40 часов работы

### Экономия (на текущем проекте)
- Координация: 9 часов
- 50 задач осталось
- Окупится уже на этом проекте

### Долгосрочная польза
- Переиспользование в других проектах
- Масштабируемость до 50+ агентов
- Надежность через auto-recovery

---

**Готово к началу имплементации**: ✅ YES

**Следующий шаг**: Создать структуру проекта и начать Phase 1
