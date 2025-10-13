# Git Worktree Workflow for Multi-Agent Development

**Date**: 2025-10-14
**Purpose**: Правила работы с Git worktrees для изоляции параллельных агентов

---

## Концепция

**Git Worktrees** позволяют создать **отдельные рабочие директории** для разных веток в одном репозитории.

**Зачем:**
- ✅ Полная изоляция агентов (каждый в своей директории)
- ✅ Независимые билды (`swift build` не конфликтуют)
- ✅ Параллельное тестирование (`swift test` одновременно)
- ✅ Нет конфликтов файлов между агентами
- ✅ Легкий мерж после завершения

---

## Структура

```
/Users/teunlao/projects/public/
├── swift-ai-sdk/                    # Main repository (main branch)
│   ├── .git/                        # Единый Git репозиторий
│   ├── Sources/
│   ├── Tests/
│   └── Package.swift
│
├── swift-ai-sdk-executor-1/         # Worktree #1 (ветка executor-1)
│   ├── .git → ../swift-ai-sdk/.git  # Ссылка на main repo
│   ├── Sources/                     # Копия кода (независимая!)
│   ├── Tests/
│   └── Package.swift
│
└── swift-ai-sdk-executor-2/         # Worktree #2 (ветка executor-2)
    ├── .git → ../swift-ai-sdk/.git  # Ссылка на main repo
    ├── Sources/                     # Копия кода (независимая!)
    ├── Tests/
    └── Package.swift
```

**Ключевое:**
- Один `.git` репозиторий (shared history)
- Разные рабочие директории (isolated files)
- Разные ветки (isolated commits)

---

## Правила для Координатора

### 1. Создание Worktree

**ВСЕГДА используй этот паттерн:**

```bash
# Из main репозитория
cd /Users/teunlao/projects/public/swift-ai-sdk

# Создать worktree с понятным именем ветки
git worktree add ../swift-ai-sdk-executor-N -b executor-N-<task-description>
```

**Примеры:**
```bash
git worktree add ../swift-ai-sdk-executor-1 -b executor-1-task-2.5
git worktree add ../swift-ai-sdk-executor-2 -b executor-2-task-3.1
git worktree add ../swift-ai-sdk-validator-1 -b validator-1-task-2.5
```

**Naming Convention:**
- `executor-N-<описание>` - для executor агентов
- `validator-N-<описание>` - для validator агентов
- `analyzer-N-<описание>` - для analyzer агентов

**Проверка:**
```bash
git worktree list
# Должно показать все worktrees с их ветками
```

---

### 2. Запуск Агента в Worktree

**Обязательно указывай `cwd` на worktree директорию!**

```bash
# 1. Создать command buffer
touch /tmp/codex-executor-N-commands.jsonl

# 2. Запустить MCP session
Bash(
    command="tail -f /tmp/codex-executor-N-commands.jsonl | codex mcp-server > /tmp/codex-executor-N-output.json 2>&1",
    run_in_background=True,
    timeout=7200000
)

# 3. Отправить задачу (🚨 cwd = worktree директория!)
cat > /tmp/cmd.json <<'JSONEOF'
{
  "jsonrpc":"2.0",
  "id":1,
  "method":"tools/call",
  "params":{
    "name":"codex",
    "arguments":{
      "prompt":"YOUR TASK HERE",
      "cwd":"/Users/teunlao/projects/public/swift-ai-sdk-executor-N",
      "approval-policy":"never",
      "sandbox":"danger-full-access"
    }
  }
}
JSONEOF
cat /tmp/cmd.json >> /tmp/codex-executor-N-commands.jsonl
```

**Критично:** `cwd` ДОЛЖЕН указывать на worktree, а не на main!

---

### 3. Мониторинг Worktrees

**Проверка активных worktrees:**
```bash
git worktree list
```

**Проверка изменений в конкретном worktree:**
```bash
cd /Users/teunlao/projects/public/swift-ai-sdk-executor-1
git status
git diff
```

**Проверка из main репозитория:**
```bash
cd /Users/teunlao/projects/public/swift-ai-sdk

# Список веток
git branch -a

# Изменения в конкретной ветке
git log main..executor-1-task-2.5

# Diff с main
git diff main..executor-1-task-2.5
```

**Через parse script:**
```bash
# Мониторинг агента
python3 scripts/parse-codex-output.py /tmp/codex-executor-1-output.json --stuck
python3 scripts/parse-codex-output.py /tmp/codex-executor-1-output.json --last 50 --reasoning
```

---

### 4. Мерж После Завершения

**Когда мержить:**
- ✅ Validation APPROVED
- ✅ All tests passing
- ✅ User approval

**Процесс:**

```bash
# 1. Вернуться в main репозиторий
cd /Users/teunlao/projects/public/swift-ai-sdk

# 2. Убедиться что на main
git checkout main

# 3. Смержить ветку worktree
git merge executor-1-task-2.5 --no-ff -m "feat: implement task 2.5"

# 4. Проверить результат
git log --oneline -5

# 5. Запустить тесты в main
swift build && swift test

# 6. Если всё ок - push
git push origin main
```

**Если конфликты:**
```bash
# Git покажет конфликты
git status

# Разрешить вручную
vim <conflicted-file>

# Завершить мерж
git add <conflicted-file>
git commit
```

---

### 5. Очистка Worktree

**После успешного мерджа:**

```bash
# 1. Удалить worktree директорию
git worktree remove ../swift-ai-sdk-executor-1

# 2. Удалить ветку (опционально)
git branch -d executor-1-task-2.5

# 3. Очистить orphaned worktrees
git worktree prune
```

**Если worktree больше не нужен (без мерджа):**
```bash
# Force удаление
git worktree remove --force ../swift-ai-sdk-executor-1

# Удалить ветку
git branch -D executor-1-task-2.5  # -D = force
```

---

## Правила для Агентов (Codex)

### 1. Рабочая Директория

**Агент ВСЕГДА работает в своём worktree:**

```
cwd: /Users/teunlao/projects/public/swift-ai-sdk-executor-N
```

**НЕ в main репозитории!**

### 2. Создание Файлов

**Все новые файлы создаются в worktree:**

```bash
# executor-1 создаёт:
/Users/teunlao/projects/public/swift-ai-sdk-executor-1/Sources/AISDKProviderUtils/NewFile.swift

# executor-2 создаёт:
/Users/teunlao/projects/public/swift-ai-sdk-executor-2/Sources/SwiftAISDK/AnotherFile.swift
```

**Изоляция:** executor-1 не видит файлы executor-2 (и наоборот)!

### 3. Билды и Тесты

**Каждый агент билдит независимо:**

```bash
# executor-1
cd /Users/teunlao/projects/public/swift-ai-sdk-executor-1
swift build   # Создаёт .build/ в executor-1/
swift test    # Тесты в executor-1/

# executor-2 (параллельно!)
cd /Users/teunlao/projects/public/swift-ai-sdk-executor-2
swift build   # Создаёт .build/ в executor-2/
swift test    # Тесты в executor-2/
```

**Нет конфликтов** - каждый в своей директории!

### 4. Коммиты

**Агент коммитит только в свою ветку:**

```bash
# executor-1
cd /Users/teunlao/projects/public/swift-ai-sdk-executor-1
git add Sources/AISDKProviderUtils/NewFile.swift
git commit -m "feat: implement task 2.5"

# Коммит попадает в ветку executor-1-task-2.5
```

**Не трогает main или другие ветки!**

---

## Частые Сценарии

### Сценарий 1: Два Независимых Таска

**Задача:** Реализовать Task 2.5 и Task 3.1 параллельно

**Workflow:**

```bash
# 1. Создать worktrees
git worktree add ../swift-ai-sdk-executor-1 -b executor-1-task-2.5
git worktree add ../swift-ai-sdk-executor-2 -b executor-2-task-3.1

# 2. Запустить агентов
# executor-1: cwd = swift-ai-sdk-executor-1
# executor-2: cwd = swift-ai-sdk-executor-2

# 3. Агенты работают параллельно (нет конфликтов!)

# 4. После завершения - мержить последовательно
git merge executor-1-task-2.5
git merge executor-2-task-3.1

# 5. Очистить worktrees
git worktree remove ../swift-ai-sdk-executor-1
git worktree remove ../swift-ai-sdk-executor-2
```

---

### Сценарий 2: Executor + Validator

**Задача:** Реализовать и валидировать Task 2.5

**Workflow:**

```bash
# 1. Создать worktree для executor
git worktree add ../swift-ai-sdk-executor-1 -b executor-1-task-2.5

# 2. executor-1 реализует таск

# 3. После завершения executor - создать worktree для validator
git worktree add ../swift-ai-sdk-validator-1 -b validator-1-task-2.5

# 4. Validator проверяет (в отдельной директории!)

# 5. Если APPROVED - мержить executor ветку
git merge executor-1-task-2.5

# 6. Очистить оба worktrees
git worktree remove ../swift-ai-sdk-executor-1
git worktree remove ../swift-ai-sdk-validator-1
git branch -d validator-1-task-2.5  # Validator ветка не нужна в main
```

---

### Сценарий 3: Конфликт Файлов

**Проблема:** Оба агента изменили один и тот же файл

**Что происходит:**

```bash
# executor-1 изменил Package.swift
# executor-2 тоже изменил Package.swift

# При мердже в main:
git merge executor-1-task-2.5  # ✅ OK
git merge executor-2-task-3.1  # ⚠️ CONFLICT in Package.swift!
```

**Решение:**

```bash
# Git покажет конфликт
Auto-merging Package.swift
CONFLICT (content): Merge conflict in Package.swift

# Открыть файл
vim Package.swift

# Увидишь:
<<<<<<< HEAD
// Изменения от executor-1
=======
// Изменения от executor-2
>>>>>>> executor-2-task-3.1

# Разрешить вручную (оставить нужное или объединить)

# Сохранить и закоммитить
git add Package.swift
git commit -m "merge: resolve conflict in Package.swift"
```

**Профилактика:**
- Назначай агентам разные файлы
- Проверяй git diff перед мерджем
- Мержи по одному (не все сразу)

---

## Ограничения и Best Practices

### ✅ DO

1. **Используй worktrees для независимых тасков**
   - Разные файлы
   - Разные модули
   - Параллельная реализация

2. **Проверяй git worktree list регулярно**
   - Знай сколько worktrees активно
   - Не забывай чистить старые

3. **Мержи по одному**
   - Сначала executor-1
   - Проверяй тесты
   - Потом executor-2

4. **Коммить часто в worktree ветках**
   - Сохраняет прогресс
   - Легче откатить при ошибках

5. **Указывай правильный cwd для агентов**
   - ВСЕГДА worktree директория
   - НЕ main репозиторий

### ❌ DON'T

1. **Не запускай агентов в main репозитории**
   - Создаёт конфликты
   - Нет изоляции

2. **Не мержи все ветки сразу**
   - Сложно разрешать конфликты
   - Непонятно что сломалось

3. **Не забывай чистить worktrees**
   - Занимают место
   - Создают путаницу

4. **Не коммить в main из worktree**
   - Worktree = отдельная ветка
   - Main = через мердж

5. **Не используй worktrees для связанных тасков**
   - Если Task B зависит от Task A
   - Используй sequential workflow

---

## Команды Quick Reference

```bash
# Создать worktree
git worktree add ../swift-ai-sdk-executor-N -b executor-N-task-X

# Список worktrees
git worktree list

# Удалить worktree
git worktree remove ../swift-ai-sdk-executor-N

# Очистить orphaned
git worktree prune

# Проверить ветку в worktree
cd /path/to/worktree && git branch --show-current

# Diff между worktree и main
git diff main..executor-N-task-X

# Мержить worktree ветку
git merge executor-N-task-X

# Удалить ветку после мерджа
git branch -d executor-N-task-X
```

---

## Troubleshooting

### Problem: "fatal: '/path/to/worktree' already exists"

**Причина:** Директория уже существует

**Решение:**
```bash
rm -rf /path/to/worktree
git worktree add /path/to/worktree -b branch-name
```

---

### Problem: "cannot remove worktrees/.../: Directory not empty"

**Причина:** Uncommitted changes или .build/ директории

**Решение:**
```bash
cd /path/to/worktree
git add -A && git commit -m "save work" || true
rm -rf .build .swiftpm

cd /main/repo
git worktree remove --force /path/to/worktree
```

---

### Problem: Агент создал файлы вне worktree

**Причина:** Неправильный `cwd` в JSON команде

**Решение:**
- Проверь `cwd` параметр
- Должен быть: `/Users/teunlao/projects/public/swift-ai-sdk-executor-N`
- НЕ: `/Users/teunlao/projects/public/swift-ai-sdk`

---

### Problem: Merge conflict в Package.swift

**Причина:** Оба агента добавляли зависимости

**Решение:**
- Открыть Package.swift
- Объединить изменения вручную
- Убедиться что синтаксис корректный
- `swift build` для проверки

---

## Integration с Multi-Agent Coordination

**Этот workflow дополняет** `docs/multi-agent-coordination.md`:

| Feature | Multi-Agent Guide | Worktree Guide |
|---------|-------------------|----------------|
| Agent naming | ✅ executor-N | ✅ executor-N |
| MCP sessions | ✅ Interactive | ✅ + worktrees |
| Isolation | ⚠️ File-based | ✅ Directory-based |
| Parallel builds | ❌ Conflicts | ✅ Independent |
| Merge strategy | Manual | ✅ Git merge |

**Используй вместе:**
- Multi-Agent Guide → Как запускать агентов
- Worktree Guide → Где агенты работают

---

## Заключение

**Git Worktrees = идеальное решение для параллельных агентов:**

✅ Полная изоляция (директории, билды, тесты)
✅ Нет конфликтов между агентами
✅ Легкий мердж в main после validation
✅ Чистый Git history

**Ключевое правило:**
> Один агент = один worktree = одна ветка = одна директория

---

**Author**: Claude Code (Sonnet 4.5)
**Date**: 2025-10-14
**Related**:
- `docs/multi-agent-coordination.md` - Agent coordination patterns
- `docs/native-background-tasks.md` - Background task basics
- `docs/interactive-mcp-sessions.md` - MCP persistent sessions

**Last Updated**: 2025-10-14
