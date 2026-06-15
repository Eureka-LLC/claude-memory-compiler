#Requires -Version 7
<#
.SYNOPSIS
    Compile daily conversation logs into structured knowledge articles.
    Uses claude CLI (claude -p) — no API key required.

.EXAMPLE
    pwsh -File compile.ps1                              # compile new/changed logs only
    pwsh -File compile.ps1 -All                         # force recompile everything
    pwsh -File compile.ps1 -Log daily\2026-05-26.md
    pwsh -File compile.ps1 -DryRun
#>

param(
    [switch]$All,
    [string]$Log,
    [switch]$DryRun
)

. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_api.ps1"

$env:CLAUDE_INVOKED_BY = "memory_compile"

# Get-AllWikiContent moved to _config.ps1 (shared with query.ps1).

# --- Вариант А: перевёрнутый двухпроход (план → запись) ---
# Полная база не масштабируется: 151 статья ≈ 134k токенов → промпт перерастает стандартное
# окно claude (нужны платные 1M-credits). Вместо этого отталкиваемся от ДНЯ, а не от старого:
#   Проход 1 (план)  — даём ТОЛЬКО индекс (≈11k токенов) + лог; LLM перечисляет уроки дня и для
#     каждого решает: НОВАЯ / ОБНОВИТЬ <ключ> / ВОЗМОЖНО <ключ> (неуверенно).
#   Проход 2 (запись) — подтягиваем ПОЛНЫЕ ТЕЛА только намеченных статей (ОБНОВИТЬ+ВОЗМОЖНО) и
#     пишем. Recall-bias: «возможно» тоже тянем (место есть); бюджет-кап не даёт раздуться.

# Проход 1: вернуть план как список объектов { verdict = NEW|UPDATE|MAYBE; key; title }.
function Get-CompilePlan([string]$LogName, [string]$LogContent) {
    $idx = if (Test-Path $INDEX_FILE) { Get-Content $INDEX_FILE -Raw -Encoding UTF8 } else { "(индекс пуст)" }
    $prompt = @"
Ты планировщик компиляции знаний. Ниже ИНДЕКС существующих статей и дневной лог разговоров.
Выдели отдельные уроки/знания, которые несёт этот день, и для каждого реши: это НОВАЯ статья
или продолжение существующей из индекса.

Ответь СТРОГО построчно (одна будущая статья — одна строка), без markdown, в одном из форматов:
НОВАЯ | краткий заголовок
ОБНОВИТЬ | ключ-из-индекса | краткий заголовок
ВОЗМОЖНО | ключ-из-индекса | краткий заголовок

Правила:
- ОБНОВИТЬ — урок явно продолжает конкретную существующую статью.
- ВОЗМОЖНО — есть похожая статья, но ты не уверен (на всякий случай подтянем её тело).
- Ключ — РОВНО как в индексе (например concepts/foo-bar), без [[ ]] и без .md.
- 3–8 строк. Пропускай рутину и тривиальные правки.

## ИНДЕКС
$idx

## ДНЕВНОЙ ЛОГ ($LogName)
$LogContent
"@
    Write-Host "  Проход 1: планирование (индекс + лог)..."
    $resp = Invoke-ClaudeCLI -Prompt $prompt
    $plan = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($resp -split "`r?`n")) {
        $l = $line.Trim()
        if (-not $l -or $l -notmatch '\|') { continue }
        $parts = @($l -split '\|' | ForEach-Object { $_.Trim() })
        $v = $parts[0].ToUpper()
        if ($v -like 'НОВ*' -or $v -like 'NEW*') {
            $plan.Add([pscustomobject]@{ verdict = 'NEW'; key = ''; title = $parts[-1] })
        } elseif (($v -like 'ОБНОВ*' -or $v -like 'UPDATE*') -and $parts.Count -ge 2) {
            $plan.Add([pscustomobject]@{ verdict = 'UPDATE'; key = $parts[1]; title = $parts[-1] })
        } elseif (($v -like 'ВОЗМ*' -or $v -like 'MAYBE*') -and $parts.Count -ge 2) {
            $plan.Add([pscustomobject]@{ verdict = 'MAYBE'; key = $parts[1]; title = $parts[-1] })
        }
    }
    return @($plan)
}

# Контекст прохода 2: полный индекс (дедуп) + тела намеченных статей. Валидирует ключи по
# реальному индексу (выдуманные отбрасывает) и держит бюджет (UPDATE раньше MAYBE).
function Get-PlannedContext([object[]]$Plan, [int]$BudgetChars = 250000) {
    $idx = if (Test-Path $INDEX_FILE) { Get-Content $INDEX_FILE -Raw -Encoding UTF8 } else { "(индекс пуст)" }

    $keyToPath = @{}
    foreach ($md in (Get-AllArticles -IncludeQa)) { $keyToPath[(Get-ArticleKey $md.FullName).ToLower()] = $md.FullName }

    $ordered = @($Plan | Where-Object { $_.verdict -eq 'UPDATE' }) + @($Plan | Where-Object { $_.verdict -eq 'MAYBE' })
    $bodies = [System.Collections.Generic.List[string]]::new()
    $used = 0; $seen = @{}; $pulled = 0; $bad = 0; $capped = 0
    foreach ($item in $ordered) {
        $k = ([string]$item.key).ToLower().Trim().TrimStart('[').TrimEnd(']').Trim()
        if (-not $k -or $seen.ContainsKey($k)) { continue }
        if (-not $keyToPath.ContainsKey($k)) { $bad++; continue }     # выдуманный ключ → пропуск (станет NEW по факту)
        $raw = Get-Content $keyToPath[$k] -Raw -Encoding UTF8
        if ($used + $raw.Length -gt $BudgetChars -and $bodies.Count -gt 0) { $capped++; continue }
        $rel = $keyToPath[$k].Substring($KNOWLEDGE_DIR.Length).TrimStart('\', '/')
        $bodies.Add("## $rel`n`n$raw"); $used += $raw.Length; $seen[$k] = $true; $pulled++
    }
    $nNew = @($Plan | Where-Object { $_.verdict -eq 'NEW' }).Count
    $nUpd = @($Plan | Where-Object { $_.verdict -eq 'UPDATE' }).Count
    $nMay = @($Plan | Where-Object { $_.verdict -eq 'MAYBE' }).Count
    Write-Host "  План: NEW=$nNew UPDATE=$nUpd MAYBE=$nMay | тел подтянуто: $pulled$(if($bad){" | выдуманных ключей: $bad"})$(if($capped){" | срезано бюджетом: $capped"})"

    $parts = @("## ИНДЕКС ВСЕХ СТАТЕЙ (для дедупа)`n`n$idx")
    if ($bodies.Count -gt 0) {
        $parts += "## ПОЛНЫЕ ТЕЛА СТАТЕЙ-КАНДИДАТОВ НА ОБНОВЛЕНИЕ ($($bodies.Count))`n`n" + ($bodies -join "`n`n---`n`n")
    }
    return ($parts -join "`n`n---`n`n")
}

function Invoke-CompileLog {
    param([string]$LogPath)

    $logContent = Get-Content $LogPath -Raw -Encoding UTF8
    $schema     = if (Test-Path $AGENTS_FILE) { Get-Content $AGENTS_FILE -Raw -Encoding UTF8 } else { "(AGENTS.md not found)" }
    $leaf       = Split-Path $LogPath -Leaf
    $timestamp  = Get-NowIso

    # Проход 1 — план: что день принёс и куда втыкать (дёшево: индекс + лог).
    $plan = @(Get-CompilePlan -LogName $leaf -LogContent $logContent)
    if ($plan.Count -eq 0) { Write-Host "  Проход 1 не выделил уроков — день пропущен."; return }

    # Проход 2 — контекст: индекс (дедуп) + тела намеченных статей (валидные, под бюджет).
    $wikiContent = Get-PlannedContext -Plan $plan
    $planText = (@($plan) | ForEach-Object {
        switch ($_.verdict) {
            'NEW'    { "- НОВАЯ: $($_.title)" }
            'UPDATE' { "- ОБНОВИТЬ $($_.key): $($_.title)" }
            'MAYBE'  { "- ВОЗМОЖНО $($_.key): $($_.title)" }
        }
    }) -join "`n"

    $prompt = @"
Ты компилятор знаний. Следуя плану ниже и дневному логу, запиши знания в wiki-статьи.
ВАЖНО: Пиши ВСЁ содержимое статей ТОЛЬКО на русском языке. Названия файлов — на английском (транслитерация или ключевые слова).

## Схема (AGENTS.md)
$schema

## Намеченный план (из анализа дня — проход 1)
$planText

## База знаний
ИНДЕКС ниже — все существующие статьи (для дедупа). Под ним — ПОЛНЫЕ ТЕЛА статей-кандидатов
на обновление: перезаписывать можно ТОЛЬКО те, чьё тело приведено. Пункты плана с пометкой
НОВАЯ — создавай новыми файлами.
$wikiContent

## Дневной лог для компиляции
**Файл:** $(Split-Path $LogPath -Leaf)

$logContent

## Формат вывода

Отвечай ТОЛЬКО файловыми операциями в точном формате ниже. Без объяснений, без блоков кода.

Создать или перезаписать файл:
<<<WRITE:knowledge/concepts/filename.md>>>
[полное содержимое файла]
<<<END>>>

Дописать в существующий файл:
<<<APPEND:knowledge/log.md>>>
[содержимое для добавления]
<<<END>>>

## Правила
1. Следуй плану выше: для пунктов НОВАЯ создай статьи в knowledge/concepts/, намеченные
   ОБНОВИТЬ/ВОЗМОЖНО обнови по их приведённым телам. Не выходи за план без явной нужды.
2. У КАЖДОГО концепта во frontmatter обязательны (см. схему выше):
   - type: concept | rule — rule для императивного урока «делай / не-делай / подвох» (грабли, анти-паттерн); concept для энциклопедической статьи.
   - scope: global | project — global, если урок полезен в ЛЮБОМ проекте (инструмент/язык/OS); project только для явных локальных фактов (схемы, поля, ключи API, бизнес-логика). СМЕЩЕНИЕ В GLOBAL: при сомнении выбирай global.
   - source_project: имя проекта из строки "_Проект:_" сессии-источника; unknown, если не определимо; при нескольких источниках — через запятую.
   - summary: однострочное описание для индекса.
   - а также title, sources, created, updated.
3. Создай статьи связей в knowledge/connections/ для неочевидных взаимосвязей (по умолчанию scope: global).
4. НЕ трогай knowledge/index.md — его детерминированно пересоберёт reindex.ps1.
5. Добавь запись о сборке в knowledge/log.md:
   ## [$timestamp] compile | $(Split-Path $LogPath -Leaf)
6. Предпочитай обновлять существующие статьи, а не плодить почти-дубликаты. Но обновляй
   (перезаписывать) ТОЛЬКО те, чьи ПОЛНЫЕ ТЕЛА приведены выше. Если тема есть в индексе, а её
   тела выше нет — НЕ переписывай её вслепую (ты не видишь текущего содержимого); создавай
   новую статью только если темы в индексе действительно нет.
   При обновлении СОХРАНИ все конкретные факты старого тела (номера документов, ссылки, даты,
   имена, примеры) — только ДОПОЛНЯЙ новым; ничего из старого не выбрасывай и не обобщай.
7. Каждая статья должна иметь YAML frontmatter и [[wikilinks]].
8. Используй относительные пути от корня проекта (например, knowledge/concepts/topic.md).
9. Заголовки разделов в статьях — на русском (## Ключевые моменты, ## Детали, ## Связанные концепты, ## Источники).
"@

    Write-Host "  Calling claude CLI..."
    $response = Invoke-ClaudeCLI -Prompt $prompt
    $opsCount = Invoke-ParseFileOps -Text $response -RootDir $CLAUDE_DIR -AllowedSubdir 'knowledge'
    Write-Host "  Executed $opsCount file operation(s)"
}

# True if a daily log holds at least one line of real knowledge — i.e. something beyond
# headers, the provenance line, and FLUSH_OK/FLUSH_ERROR stubs. On the days the CLI was
# unresolved the log contains only error text; compiling those would feed the model
# garbage and burn the hash-gate (the day could then never be recovered), so the compile
# selection skips them. Recall-safe: anything not clearly a stub counts as content.
function Test-DailyHasContent([string]$Path) {
    foreach ($line in (Get-Content $Path -Encoding UTF8)) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t.StartsWith('#')) { continue }                                              # # / ## / ### headers
        if ($t -match '^_Проект:') { continue }                                           # provenance line
        if ($t -match 'FLUSH_OK|FLUSH_ERROR') { continue }                                # stub markers
        if ($t -match 'is not recognized as a name|^Check the spelling of the name') { continue }  # CLI-not-found spill
        return $true
    }
    return $false
}

# --- Determine which logs to compile ---
$state = Load-State

if ($Log) {
    $target = $Log
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $CLAUDE_DIR $target
    }
    if (-not (Test-Path $target)) { Write-Error "File not found: $Log"; exit 1 }
    $toCompile = @($target)
}
else {
    $allLogs = if (Test-Path $DAILY_DIR) {
        Get-ChildItem $DAILY_DIR -Filter "*.md" | Sort-Object Name | Select-Object -ExpandProperty FullName
    } else { @() }

    $toCompile = if ($All) {
        $allLogs
    } else {
        $ingested = $state['ingested'] ?? @{}
        $allLogs | Where-Object {
            $key = Split-Path $_ -Leaf
            -not $ingested[$key] -or $ingested[$key]['hash'] -ne (Get-FileHash256 $_)
        }
    }

    # Skip daily logs with no real knowledge — only FLUSH_ERROR / FLUSH_OK stubs (e.g. days
    # the CLI was unresolved). Compiling them feeds error text to the model and burns the
    # hash-gate so the day can never be recovered. An explicit -Log <file> bypasses this.
    $toCompile = @($toCompile | Where-Object { Test-DailyHasContent $_ })
}

if (-not $toCompile) {
    Write-Host "Nothing to compile — all daily logs are up to date."
    exit 0
}

$prefix = if ($DryRun) { "[DRY RUN] " } else { "" }
Write-Host "${prefix}Files to compile ($(@($toCompile).Count)):"
foreach ($f in $toCompile) { Write-Host "  - $(Split-Path $f -Leaf)" }
if ($DryRun) { exit 0 }

foreach ($logPath in @($toCompile)) {
    $leafName = Split-Path $logPath -Leaf
    Write-Host "`nCompiling $leafName..."

    try {
        Invoke-CompileLog -LogPath $logPath

        $logHash    = Get-FileHash256 $logPath
        $compiledAt = Get-NowIso
        $state = Update-State {
            param($s)
            if (-not $s.ContainsKey('ingested')) { $s['ingested'] = @{} }
            $s['ingested'][$leafName] = @{ hash = $logHash; compiled_at = $compiledAt }
        }
        Write-Host "  Done."
    }
    catch {
        Write-Host "  ERROR: $_"
    }
}

# Tag domains on the freshly compiled articles — the live domain step (controlled
# vocabulary, written straight to frontmatter; no manual Excel pass). Only articles
# without domains yet are classified, so repeat runs are cheap.
$tagDomainsPs = Join-Path $SCRIPTS_DIR "tag-domains.ps1"
if (Test-Path $tagDomainsPs) {
    Write-Host "`nTagging domains..."
    try { & $tagDomainsPs } catch { Write-Host "  WARNING: tag-domains.ps1 failed: $_" }
}

# Rebuild the index deterministically from article frontmatter (session-start
# filtering depends on accurate Scope/Project columns).
$reindexPs = Join-Path $SCRIPTS_DIR "reindex.ps1"
if (Test-Path $reindexPs) {
    Write-Host "`nRebuilding index..."
    try { & $reindexPs } catch { Write-Host "  WARNING: reindex.ps1 failed — index may be stale: $_" }
}

$articles = @(Get-AllArticles -IncludeQa)
Write-Host "`nDone. Knowledge base: $($articles.Count) articles"
