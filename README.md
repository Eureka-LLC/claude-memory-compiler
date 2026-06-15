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
        │   index.md                ← каталог (Type/Scope/Project/Domains/Summary)
        │   concepts\
        │   connections\
        └── qa\
        reports\
        domains.md                  ← словарь доменов (контролируемый список)
        projects.json               ← реестр: проект → путь репо + домены проекта
        domain-gaps.log             ← кандидаты доменов вне словаря (из запросов)
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
    "UserPromptSubmit": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\user-prompt-submit.ps1", "timeout": 20 }]
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

# Проверка здоровья базы знаний (9 проверок)
pwsh -File scripts\lint.ps1

# Только структурные проверки (без API, бесплатно)
pwsh -File scripts\lint.ps1 -StructuralOnly

# Схлопнуть накопленные append-слои статей (layers >= 4) в единую статью
pwsh -File scripts\consolidate.ps1            # или: lint.ps1 -Consolidate

# Пересобрать индекс из frontmatter (детерминированно, без API)
pwsh -File scripts\reindex.ps1

# Разовая реклассификация легаси: проставить scope/type/source_project
pwsh -File scripts\reclassify.ps1 -DryRun   # сначала посмотреть план
pwsh -File scripts\reclassify.ps1            # затем выполнить

# Домены текущего проекта (или slash-команда /domains)
pwsh -File scripts\project-domains.ps1                       # показать домены + словарь
pwsh -File scripts\project-domains.ps1 "wordpress, php-web"  # добавить
pwsh -File scripts\project-domains.ps1 "-css-frontend"       # убрать

# «Налог второго мозга»: размер контекста, подмешиваемого в проект (или /brain)
pwsh -File scripts\brain-stats.ps1

# Статьи без проставленных доменов
pwsh -File scripts\list-no-domains.ps1
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
| `-Limit` | Макс. **обработанных** сессий за запуск | без ограничений |
| `-BatchSize` | Отчёт после каждых N сессий | `5` |
| `-NoBatch` | Отключить батч-режим | — |
| `-DryRun` | Показать план без изменений | — |
| `-Force` | Повторно обработать сессии | — |
| `-NoCompile` | Только daily-логи, без compile | — |

> **Как считается `-Limit`:** лимит применяется только к сессиям, которые фактически обработаны — то есть прошли порог `-MinTurns` и были суммаризованы или записаны. Уже обработанные ранее и слишком короткие сессии в счёт не идут, но скрипту всё равно приходится их просматривать.
>
> Пример: в архиве 200 коротких тестовых сессий (1–2 реплики) и 10 содержательных. `-Limit 5` заставит скрипт пролистать все 200 коротких, чтобы найти 5 нужных — и только тогда остановится. Это нормальное поведение: короткие сессии попутно помечаются как пропущенные в `retro-processed.json` и при следующих запусках пролетают мгновенно.

**Два режима:**

- **Fast** — скрипт записывает реплики напрямую в daily-лог без API, затем `compile.ps1` извлекает знания. ~1 API-вызов на день. Идеально для первого запуска на всём архиве.
- **Quality** — Claude суммаризирует каждую сессию индивидуально (как `flush.ps1`), затем compile. ~1 API-вызов на сессию. Лучше для выборочной обработки важных проектов.

Скрипт запоминает обработанные сессии в `retro-processed.json` — повторные запуски безопасны, уже обработанное пропускается.

---

## Глобальные и проектные знания

База знаний общая для всех проектов, но не всё знание универсально. Каждая статья помечена во frontmatter:

- `scope: global | project` — `global` полезно везде (повадки PowerShell, OS, инструментов), `project` относится только к одному проекту (схема БД, поля, ключи API, бизнес-логика).
- `source_project` — из какого проекта пришёл урок (имя папки корня git-репозитория). Хуки определяют его по `cwd` сессии и пишут строку `_Проект:_` в дневной лог; компилятор по ней разносит знания.
- `type: concept | rule` — `rule` это императивный урок «делай / не-делай / подвох» (грабли); такие подаются в контекст первыми.

**Фильтр подмешивания.** `session-start.ps1` берёт текущий проект из `cwd` и инжектит статьи текущего проекта плюс `scope: global`, **отфильтрованные по доменам проекта** (см. раздел «Домены»). В проекте A ты больше не видишь факты проекта B — меньше шума, меньше токенов.

**Где решается scope.** Классификацию делает компилятор (`compile.ps1`) в момент записи, со смещением в сторону `global` (потерять глобальный урок в одном проекте хуже, чем переклассифицировать локальный факт). `lint.ps1` — аудитор: помечает подозрительный scope, но ничего не переносит.

> Индекс `knowledge/index.md` пересобирается детерминированно скриптом `reindex.ps1` из frontmatter — фильтр в `session-start` опирается на колонки `Scope`/`Project`/`Domains`, поэтому индекс строит код, а не LLM.

---

## Домены: второй слой меток

Помимо `scope`/`source_project` у каждой статьи есть поле `domains: [..]` — теги области применимости из **контролируемого словаря** `.claude/domains.md` (по одному домену на строку). Это вторая ось релевантности (`wordpress`, `css-frontend`, `python`, `amocrm`…).

- **Автотегирование.** `tag-domains.ps1` — шаг конвейера: `compile.ps1` вызывает его после записи статей и перед `reindex`. Словарь закрытый: всё, чего нет в `domains.md`, отбрасывается. Хеш-гейт по содержимому: повторно классифицируются только новые или изменённые статьи (`-Force` — переклассифицировать все).
- **Домены проекта.** `project-domains.ps1` (команда `/domains`) хранит домены проекта в `projects.json`; `brain-stats.ps1` (команда `/brain`) показывает размер подмешиваемого контекста.

### Доменный фильтр инжекта

`session-start` подаёт `scope: global` статью только если её домены **пересекаются с доменами проекта**. Правило **fail-closed**: нет доменов у статьи или пустой профиль проекта → global не подаётся. Статьи самого проекта (`scope: project`) подаются всегда, домен их не фильтрует. Предикат — `Test-RowInjected` в `scripts/_config.ps1`, общий с `/brain`, чтобы отчёт и реальный инжект не расходились. Выключатель — `$DOMAIN_FILTER` в `_config.ps1` (`$false` → прежнее поведение, весь global).

### Авто-наполнение профиля из запросов

Профиль доменов проекта не нужно вести вручную — он накапливается сам. Хук **`UserPromptSubmit`** (`hooks/user-prompt-submit.ps1`) на каждый запрос делает один вызов лёгкой модели и:

1. классифицирует промпт по словарю `domains.md` (`$DOMAINIZE_MODEL`, по умолчанию `claude-haiku-4-5`);
2. дописывает недостающие домены в профиль проекта (`projects.json`) и просит ассистента сообщить об этом в диалог;
3. **догружает прямо в текущую сессию** `global`-статьи добавленного домена (которых не было в инжекте на старте);
4. если запрос явно про область **вне словаря** — пишет строку-кандидат в `.claude/domain-gaps.log` для ручного пополнения `domains.md`.

> Домены добавляются только вперёд (храповик); лишний убирается вручную — `/domains -<домен>`. Поток затухает сам: словарь конечен, добавляются лишь отсутствующие.

### Массовое ревью легаси (Excel)

Для ручной разметки большой уже накопленной базы есть полуавтоматический проход через Excel:

```powershell
pwsh -File scripts\suggest-domains.ps1     # 1. LLM-предложения доменов → domain-suggestions.json
pwsh -File scripts\export-review.ps1       # 2. собрать review.xlsx (чекбокс на каждый домен)
#                                            3. отредактировать review.xlsx руками
pwsh -File scripts\apply-review.ps1        # 4. прочитать xlsx обратно → во frontmatter, reindex, lint
pwsh -File scripts\apply-review.ps1 -DryRun  # предпросмотр без записи
```

Это **единственная часть проекта на Python**: сборка и чтение `.xlsx` идут через `build-review-xlsx.py` / `read-review-xlsx.py`, которые `export-review`/`apply-review` вызывают сами. Нужны Python 3 и `openpyxl` (`py -m pip install openpyxl`). Путь к мозгу скрипты получают от PowerShell аргументом — хардкода нет.

---

## Как работает

```
Разговор
  → SessionEnd / PreCompact хуки (файловый I/O + определение проекта по cwd)
  → scripts\flush.ps1 фоном (claude -p: что стоит запомнить?)
  → daily\YYYY-MM-DD.md (дневной лог со строкой _Проект:_)
  → scripts\compile.ps1 (2 прохода: план по индексу → запись; новые статьи WRITE, обновления — append-слои)
  → scripts\tag-domains.ps1 (домены из словаря во frontmatter, hash-gated)
  → scripts\reindex.ps1 (детерминированный index.md из frontmatter)
  → knowledge\concepts\, connections\, qa\ (статьи базы знаний)
  → SessionStart хук инжектирует индекс ТЕКУЩЕГО проекта (статьи проекта + global∩домены)
  → UserPromptSubmit хук: домены каждого запроса → профиль проекта + догрузка их global-статей
  → цикл повторяется
```

### Компоненты

| Файл | Назначение |
|------|-----------|
| `hooks\session-end.ps1` | Захватывает транскрипт при завершении сессии |
| `hooks\pre-compact.ps1` | Страховка: захватывает контекст перед авто-компакцией |
| `hooks\session-start.ps1` | Инжектирует индекс **текущего проекта** (статьи проекта + global, отфильтрованный по доменам проекта) |
| `hooks\user-prompt-submit.ps1` | На каждый промпт: домены запроса → профиль проекта (`projects.json`), догрузка их global-статей, лог внесловарных кандидатов (`domain-gaps.log`) |
| `scripts\flush.ps1` | Фоновый процесс: извлекает важное из разговора |
| `scripts\compile.ps1` | Компилирует дневные логи в статьи (двухпроход план→запись; обновления через append-слои, не перезапись) + классифицирует scope/type |
| `scripts\reindex.ps1` | Детерминированно пересобирает `index.md` из frontmatter |
| `scripts\reclassify.ps1` | Разовая реклассификация легаси (scope/type/source_project) |
| `scripts\retrocompile.ps1` | **Ретроспективная компиляция** исторических сессий в базу знаний |
| `scripts\tag-domains.ps1` | Тегирует статьи доменами из словаря (шаг конвейера compile, hash-gated) |
| `scripts\suggest-domains.ps1` | LLM-предложения доменов в JSON (для Excel-ревью) |
| `scripts\project-domains.ps1` | Домены проекта в `projects.json` (команда `/domains`) |
| `scripts\list-no-domains.ps1` | Список статей без доменов |
| `scripts\brain-stats.ps1` | Размер подмешиваемого контекста проекта (команда `/brain`) |
| `scripts\export-review.ps1` | Выгрузка статей в `review.xlsx` для ручного ревью доменов/scope |
| `scripts\apply-review.ps1` | Применить отредактированный `review.xlsx` обратно во frontmatter |
| `scripts\*-review-xlsx.py` | Python+openpyxl: сборка/чтение `review.xlsx` (вызываются из PS) |
| `scripts\query.ps1` | Задаёт вопросы базе знаний |
| `scripts\lint.ps1` | 9 проверок здоровья базы (вкл. аудит scope, пухлые статьи layers≥4); `-Consolidate` запускает схлопывание слоёв |
| `scripts\consolidate.ps1` | Схлопывает append-слои статей (layers≥4) в единую — с детерминированной проверкой покрытия фактов (потеря → отклонено) |
| `scripts\_api.ps1` | Утилиты: вызов `claude` CLI + парсинг файловых операций |
| `scripts\_config.ps1` | Константы путей + хелперы проекта/frontmatter |

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
│   ├── pre-compact.ps1
│   └── user-prompt-submit.ps1
├── scripts\
│   ├── _config.ps1          # пути + хелперы проекта/frontmatter (dot-source)
│   ├── _api.ps1             # Invoke-ClaudeCLI, Invoke-ParseFileOps
│   ├── flush.ps1            # фоновый процесс извлечения памяти
│   ├── compile.ps1          # компилятор: двухпроход план→запись, append-слои обновлений
│   ├── tag-domains.ps1      # автотегирование доменами (шаг compile)
│   ├── reindex.ps1          # детерминированный index.md из frontmatter
│   ├── reclassify.ps1       # разовая реклассификация легаси
│   ├── retrocompile.ps1     # ретроспективная компиляция архива
│   ├── project-domains.ps1  # домены проекта (/domains)
│   ├── brain-stats.ps1      # размер подмешиваемого контекста (/brain)
│   ├── list-no-domains.ps1  # статьи без доменов
│   ├── suggest-domains.ps1  # LLM-предложения доменов (для Excel-ревью)
│   ├── export-review.ps1    # выгрузка в review.xlsx
│   ├── apply-review.ps1     # применение review.xlsx обратно
│   ├── build-review-xlsx.py # сборка xlsx (Python+openpyxl)
│   ├── read-review-xlsx.py  # чтение xlsx (Python+openpyxl)
│   ├── query.ps1            # запросы к базе знаний
│   ├── consolidate.ps1      # схлопывание append-слоёв (layers>=4) с проверкой покрытия
│   └── lint.ps1             # проверка здоровья (9 проверок)
├── setup.ps1             # скрипт установки
├── AGENTS.md             # схема базы знаний на русском (читается LLM)
├── AGENTS.en.md          # английский оригинал схемы
└── README.md
```

---

## Стоимость API

| Операция | Примерная стоимость |
|----------|-------------------|
| Flush одной сессии | ~$0.02–0.05 |
| Компиляция одного дневного лога | ~$0.45–0.65 |
| Тегирование доменов (одна статья) | ~$0.02–0.05 |
| Доменизация промпта (на каждый запрос) | ~$0.001–0.003 (Haiku) |
| Ретрокомпиляция Fast (весь архив) | ~$0.45–0.65 × кол-во дней |
| Ретрокомпиляция Quality (одна сессия) | ~$0.02–0.05 |
| Запрос к базе | ~$0.15–0.25 |
| Lint со структурными проверками | $0.00 |
| Lint с проверкой противоречий | ~$0.15–0.25 |

Компиляция/flush/тегирование используют `claude-sonnet-4-6`; доменизация промпта — `claude-haiku-4-5`. Модели задаются в `scripts\_config.ps1` (`$DEFAULT_MODEL`, `$DOMAINIZE_MODEL`).

---

## Лицензия

MIT
