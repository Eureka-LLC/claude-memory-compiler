# claude-memory-compiler (PowerShell)

[🇬🇧 English version](README.en.md)

**Ваши разговоры с Claude Code сами компилируются в структурированную базу знаний.**

При завершении сессии (или перед авто-компакцией) хуки перехватывают транскрипт разговора и в фоне извлекают важное: решения, уроки, паттерны, грабли. Всё накапливается в дневных логах, которые затем компилируются в структурированные статьи с перекрёстными ссылками.

> Источник вдохновения: **[coleam00/claude-memory-compiler](https://github.com/coleam00/claude-memory-compiler)** — оригинальная Python/uv реализация той же идеи.
> Архитектура знаний основана на подходе [Andrej Karpathy's LLM Knowledge Base](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Этот репозиторий — **нативный PowerShell порт** для Windows: никакого Python, никакого uv, никаких виртуальных окружений. Только `pwsh` и `claude` CLI из твоей подписки.

---

## Ключевая идея: скрипты и данные — в разных папках

```
E:\tools\claude-memory-compiler\   ← репо (скрипты, хуки) — клонируй сюда
    brain.path                      ← одна строка: путь к твоему мозгу

E:\my-brain\                        ← база знаний (данные) — настраивается в setup.ps1
    .claude\                        ← все данные memory compiler (как .git/)
        daily\                      ← сюда автоматически падают все разговоры
        knowledge\
        │   concepts\
        │   connections\
        └── qa\
        reports\
```

`setup.ps1` спрашивает, где хочешь хранить данные, сохраняет путь в `brain.path` и прописывает **глобальные** хуки Claude Code. После этого **все сессии из любых проектов** автоматически попадают в одну базу знаний.

Обновить скрипты: `git pull` — данные в `brain.path` не трогает.

---

## Требования

- Windows 10/11
- PowerShell 7+ (`pwsh`) — [скачать](https://github.com/PowerShell/PowerShell/releases)
- [Claude Code](https://claude.ai/download) — CLI или IDE-расширение (уже установлен, раз ты это читаешь)
- Отдельный API ключ **не нужен** — используется подписка через `claude` CLI

---

## Установка

```powershell
# 1. Клонировать репо (скрипты и хуки)
git clone https://github.com/YOUR_USERNAME/claude-memory-compiler-ps E:\tools\claude-memory-compiler
cd E:\tools\claude-memory-compiler

# 2. Запустить setup — спросит, где хранить данные, и настроит всё остальное
pwsh -File setup.ps1
# > Brain directory [Enter for default: C:\Users\...\brain]: E:\my-brain
```

> **Рекомендуется запускать `setup.ps1` из терминала внутри Claude Desktop** — тогда хуки будут зарегистрированы в том же окружении, где работает приложение, и сразу начнут перехватывать сессии. Для этого в Claude Desktop нажми «Terminal» или запусти `pwsh` прямо из встроенного терминала.
>
> `setup.ps1` автоматически настраивает `ExecutionPolicy` (см. ниже).
> Путь к мозгу сохраняется в `brain.path` (gitignored) — можно изменить, перезапустив `setup.ps1`.

---

## Разрешения PowerShell (один раз)

Windows по умолчанию запрещает запуск `.ps1` скриптов. Выполни **один раз**, без прав администратора:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

`setup.ps1` делает это автоматически. После этого — никаких диалогов разрешений.

Хуки Claude Code также не показывают диалогов: раз прописаны в `settings.json`, они запускаются автоматически.

### Ручная настройка хуков

Хуки можно настроить **глобально** (работают из любого проекта) — в `~\.claude\settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\session-start.ps1", "timeout": 15 }]
    }],
    "PreCompact": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\pre-compact.ps1", "timeout": 10 }]
    }],
    "SessionEnd": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\session-end.ps1", "timeout": 10 }]
    }]
  }
}
```

Замените `E:\\claude-memory-compiler` на реальный путь установки (двойные обратные слэши обязательны).

---

## Команды

```powershell
# Скомпилировать новые дневные логи в статьи базы знаний
pwsh -File scripts\compile.ps1

# Скомпилировать всё заново
pwsh -File scripts\compile.ps1 -All

# Скомпилировать конкретный лог
pwsh -File scripts\compile.ps1 -Log .claude\daily\2026-05-26.md

# Задать вопрос базе знаний
pwsh -File scripts\query.ps1 "Как я обычно обрабатываю ошибки API?"

# Задать вопрос и сохранить ответ обратно в базу
pwsh -File scripts\query.ps1 "Какие паттерны я использую для аутентификации?" -FileBack

# Проверка здоровья базы знаний (7 проверок)
pwsh -File scripts\lint.ps1

# Только структурные проверки (без API, бесплатно)
pwsh -File scripts\lint.ps1 -StructuralOnly
```

### ⭐ Ретроспективная компиляция

Уже работал с Claude Code до установки этого инструмента? Не беда — `retrocompile.ps1` найдёт все исторические транскрипты в `~/.claude/projects/` и впишет их в базу знаний.

```powershell
# Пробный запуск — посмотреть что будет обработано
pwsh -File scripts\retrocompile.ps1 -DryRun

# Быстрый режим: скрипт сам пишет реплики в daily-логи → compile делает 1 вызов на день
# По умолчанию работает в батч-режиме: отчёт после каждых 5 сессий
pwsh -File scripts\retrocompile.ps1

# Батч по 10 сессий
pwsh -File scripts\retrocompile.ps1 -BatchSize 10

# Без батч-режима — обработать всё без промежуточных отчётов
pwsh -File scripts\retrocompile.ps1 -NoBatch

# Качественный режим: Claude суммаризирует каждую сессию → лучшие статьи
pwsh -File scripts\retrocompile.ps1 -Mode Quality

# Обработать по 20 сессий за раз (удобно для Quality-режима)
pwsh -File scripts\retrocompile.ps1 -Mode Quality -Limit 20

# Только определённые проекты, начиная с даты
pwsh -File scripts\retrocompile.ps1 -Projects "my-saas","side-project" -Since 2026-01-01

# Только заполнить daily-логи, без компиляции
pwsh -File scripts\retrocompile.ps1 -NoCompile

# Повторно обработать уже обработанные сессии
pwsh -File scripts\retrocompile.ps1 -Force
```

**Параметры:**

| Параметр | Описание | По умолчанию |
|----------|----------|-------------|
| `-Mode` | `Fast` или `Quality` | `Fast` |
| `-Projects` | Фильтр по имени проекта (подстрока) | все |
| `-MinTurns` | Минимум реплик в сессии | `3` |
| `-Since` | Только с даты `YYYY-MM-DD` | всё время |
| `-Limit` | Макс. сессий за запуск | без ограничений |
| `-BatchSize` | Отчёт после каждых N сессий | `5` |
| `-NoBatch` | Отключить батч-режим | — |
| `-DryRun` | Показать план без изменений | — |
| `-Force` | Повторно обработать сессии | — |
| `-NoCompile` | Только daily-логи, без compile | — |

**Два режима:**

- **Fast** — скрипт записывает реплики напрямую в daily-лог без API, затем `compile.ps1` извлекает знания. ~1 API-вызов на день. Идеально для первого запуска на всём архиве.
- **Quality** — Claude суммаризирует каждую сессию индивидуально (как `flush.ps1`), затем compile. ~1 API-вызов на сессию. Лучше для выборочной обработки важных проектов.

Скрипт запоминает обработанные сессии в `retro-processed.json` — повторные запуски безопасны, уже обработанное пропускается.

---

## Как работает

```
Разговор
  → SessionEnd / PreCompact хуки (только файловый I/O, без API)
  → scripts\flush.ps1 фоном (Anthropic API: что стоит запомнить?)
  → daily\YYYY-MM-DD.md (дневной лог)
  → scripts\compile.ps1 (Anthropic API + tool use: write_file, append_file)
  → knowledge\concepts\, connections\, qa\ (статьи базы знаний)
  → SessionStart хук инжектирует index.md в следующую сессию
  → цикл повторяется
```

### Компоненты

| Файл | Назначение |
|------|-----------|
| `hooks\session-end.ps1` | Захватывает транскрипт при завершении сессии |
| `hooks\pre-compact.ps1` | Страховка: захватывает контекст перед авто-компакцией |
| `hooks\session-start.ps1` | Инжектирует индекс базы знаний в каждую сессию |
| `scripts\flush.ps1` | Фоновый процесс: извлекает важное из разговора |
| `scripts\compile.ps1` | Компилирует дневные логи в структурированные статьи |
| `scripts\retrocompile.ps1` | **Ретроспективная компиляция** исторических сессий в базу знаний |
| `scripts\query.ps1` | Задаёт вопросы базе знаний |
| `scripts\lint.ps1` | 7 проверок здоровья базы знаний |
| `scripts\_api.ps1` | Утилиты: вызов Anthropic API + цикл tool use |
| `scripts\_config.ps1` | Константы путей |

### Почему PowerShell вместо Python?

| | Python (uv run) | PowerShell |
|---|---|---|
| Старт | 2–4 сек | ~0 сек |
| Таймаут хука | 10 сек — риск | 10 сек — норма |
| Зависимости | uv, venv, пакеты | встроено |
| JSON | `json.loads()` | `ConvertFrom-Json` |
| HTTP | `httpx` / `requests` | `Invoke-RestMethod` |

---

## Структура проекта

```
claude-memory-compiler/
├── hooks\
│   ├── session-end.ps1
│   ├── session-start.ps1
│   └── pre-compact.ps1
├── scripts\
│   ├── _config.ps1          # константы путей (dot-source)
│   ├── _api.ps1             # Invoke-ClaudeCLI, Invoke-ParseFileOps
│   ├── flush.ps1            # фоновый процесс извлечения памяти
│   ├── compile.ps1          # компилятор дневных логов
│   ├── retrocompile.ps1     # ретроспективная компиляция архива
│   ├── query.ps1            # запросы к базе знаний
│   └── lint.ps1             # проверка здоровья
├── setup.ps1             # скрипт установки
├── AGENTS.md             # схема базы знаний (читается LLM)
└── README.md
```

---

## Стоимость API

| Операция | Примерная стоимость |
|----------|-------------------|
| Flush одной сессии | ~$0.02–0.05 |
| Компиляция одного дневного лога | ~$0.45–0.65 |
| Ретрокомпиляция Fast (весь архив) | ~$0.45–0.65 × кол-во дней |
| Ретрокомпиляция Quality (одна сессия) | ~$0.02–0.05 |
| Запрос к базе | ~$0.15–0.25 |
| Lint со структурными проверками | $0.00 |
| Lint с проверкой противоречий | ~$0.15–0.25 |

Используется `claude-sonnet-4-6`. Модель задаётся в `scripts\_config.ps1`.

---

## Лицензия

MIT
