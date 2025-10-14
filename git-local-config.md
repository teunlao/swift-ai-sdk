# Настройка Git для использования личного GitHub email

## Проблема
По умолчанию Git использует рабочий email `dosipov@combotech.net`, который не привязан к GitHub аккаунту. Из-за этого коммиты не отображаются в GitHub Contributions и в списке Contributors.

## Решение
Настроить Git локально для конкретного репозитория с личным GitHub email.

## Шаги

### 1. Проверить текущие настройки
```bash
git config user.name
git config user.email
```

### 2. Установить локальные настройки для текущего репо
```bash
cd /path/to/your/repo
git config --local user.name "teunlao"
git config --local user.email "teunlao@gmail.com"
```

### 3. Проверить что применилось
```bash
git config --local --list | grep user
```

Должно показать:
```
user.name=teunlao
user.email=teunlao@gmail.com
```

## Важно
- `--local` применяет настройки только для текущего репозитория
- Глобальные настройки (`git config --global`) остаются без изменений
- Все новые коммиты будут автоматически использовать новый email
- Email `teunlao@gmail.com` должен быть добавлен в GitHub Settings → Emails

## Проверка
```bash
# Сделать тестовый коммит
git commit --allow-empty -m "test commit"

# Проверить автора
git log -1 --format="%an <%ae>"
```

Должно показать: `teunlao <teunlao@gmail.com>`
