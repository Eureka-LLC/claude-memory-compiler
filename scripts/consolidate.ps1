#Requires -Version 7
<#
.SYNOPSIS
    Консолидация append-слоёв (холодный путь LSM). Статьи с layers >= Threshold
    переписываются LLM в единую чистую статью: датированные слои «## Обновление …»
    сливаются в тело, повторы убираются.

    БЕЗОПАСНОСТЬ: после переписывания идёт ДЕТЕРМИНИРОВАННАЯ проверка покрытия фактов —
    все факт-токены оригинала (код в `..`, URL, номера документов, числовые значения)
    обязаны присутствовать в результате. Потерян хоть один → консолидация ОТКЛОНЯЕТСЯ,
    слои остаются нетронутыми. Перед записью — бэкап. Так «та же перезапись» становится
    безопасной: даже если LLM уронит факт, проверка это поймает.

.EXAMPLE
    pwsh -File consolidate.ps1                 # все статьи layers >= 4
    pwsh -File consolidate.ps1 -Threshold 1    # порог 1 (для проверки механики)
    pwsh -File consolidate.ps1 -Article concepts/getcourse-dates
    pwsh -File consolidate.ps1 -DryRun         # показать кандидатов, без LLM и записи
#>
param(
    [int]$Threshold = 4,
    [string]$Article = "",
    [switch]$DryRun
)

. "$PSScriptRoot\_config.ps1"
. "$PSScriptRoot\_api.ps1"

$env:CLAUDE_INVOKED_BY = "memory_consolidate"

# Факт-токены, которые консолидация обязана сохранить: код в `обратных кавычках`, URL,
# номера документов (№ …) и числовые значения (3+ симв — чтобы не ловить шум вроде «4»/«v2»).
# Строки-заголовки слоёв «## Обновление ГГГГ-ММ-ДД» исключаются: их даты служебные, не факты.
function Get-FactTokens([string]$Text) {
    $body = ($Text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*##\s+Обновление\b' }) -join "`n"
    $toks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in [regex]::Matches($body, '`[^`]+`'))            { [void]$toks.Add($m.Value.Trim()) }
    foreach ($m in [regex]::Matches($body, 'https?://[^\s)]+'))   { [void]$toks.Add($m.Value) }
    foreach ($m in [regex]::Matches($body, '№\s*[^\s,.;]+'))      { [void]$toks.Add(($m.Value -replace '\s', '')) }
    foreach ($m in [regex]::Matches($body, '\b\d[\d\-/.]{2,}\b')) { [void]$toks.Add($m.Value) }
    return $toks
}

function Get-LayerCount([string]$Raw) { ([regex]::Matches($Raw, '(?m)^\s*##\s+Обновление\b')).Count }

function Invoke-Consolidate([string]$Path) {
    $rel = $Path.Substring($KNOWLEDGE_DIR.Length).TrimStart('\', '/')
    $raw = Get-Content $Path -Raw -Encoding UTF8
    Write-Host "`n$rel ($(Get-LayerCount $raw) слоёв)"

    $prompt = @"
Ниже статья базы знаний, в которую со временем дописывались датированные слои
«## Обновление ГГГГ-ММ-ДД». Слей слои в основной текст: убери датированные заголовки слоёв и
повторяющиеся факты, упорядочи разделы в связный текст. КРИТИЧНО: сохрани ВСЕ конкретные
факты — числа, номера документов, ссылки (URL), код в обратных кавычках, имена. Ничего не
выбрасывай и не обобщай «своими словами» в ущерб конкретике. Сохрани YAML frontmatter.
Верни ТОЛЬКО полное новое содержимое файла, без пояснений и без ``` блоков.

## Статья ($rel)
$raw
"@

    if ($DryRun) { Write-Host "  [dry-run] здесь был бы вызов LLM"; return $null }

    $new = (Invoke-ClaudeCLI -Prompt $prompt).Trim()
    if (-not $new -or -not $new.StartsWith('---')) {
        Write-Host "  ОТКЛОНЕНО: LLM вернул пустой ответ или без frontmatter" -ForegroundColor Yellow
        return $false
    }

    # Детерминированная проверка покрытия: ни один факт-токен не должен исчезнуть.
    $orig = Get-FactTokens $raw
    $cons = Get-FactTokens $new
    $missing = @($orig | Where-Object { -not $cons.Contains($_) })
    if ($missing.Count -gt 0) {
        Write-Host "  ОТКЛОНЕНО: потеряно бы $($missing.Count) факт(ов) — слои оставлены. Пример: $((@($missing) | Select-Object -First 6) -join ' | ')" -ForegroundColor Yellow
        return $false
    }

    # Бэкап → запись → layers сбрасываем в 0 (слоёв в теле больше нет).
    $bdir = Join-Path $CLAUDE_DIR "backups\consolidate-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Path $bdir -Force | Out-Null }
    Copy-Item $Path $bdir
    $new = Set-FrontmatterField $new 'layers' (Get-LayerCount $new)   # = 0 после слияния
    $new = Set-FrontmatterField $new 'updated' (Get-TodayIso)
    [System.IO.File]::WriteAllText($Path, $new, [System.Text.Encoding]::UTF8)
    Write-Host "  OK: слои слиты, все $($orig.Count) факт-токенов на месте. Бэкап: backups\$(Split-Path $bdir -Leaf)" -ForegroundColor Green
    return $true
}

# --- Отбор кандидатов ---
$targets = if ($Article) {
    $a = ($Article -replace '\.md$', '') -replace '/', '\'
    @((Join-Path $KNOWLEDGE_DIR "$a.md"))
} else {
    @(Get-AllArticles -IncludeQa | Where-Object {
        $f = Get-ArticleFields (Get-Content $_.FullName -Raw -Encoding UTF8)
        [int]($f['layers'] ?? 0) -ge $Threshold
    } | ForEach-Object { $_.FullName })
}

if (-not $targets) { Write-Host "Нет статей с layers >= $Threshold — консолидировать нечего."; exit 0 }
Write-Host "К консолидации: $(@($targets).Count) статья(й) (порог layers >= $Threshold)$(if($DryRun){' [DRY RUN]'})"

$ok = 0; $rej = 0
foreach ($t in $targets) {
    if (-not (Test-Path $t)) { Write-Host "  пропуск (нет файла): $t" -ForegroundColor DarkGray; continue }
    $r = Invoke-Consolidate $t
    if ($r -eq $true) { $ok++ } elseif ($r -eq $false) { $rej++ }
}

Write-Host "`nГотово. Консолидировано: $ok | отклонено (защита от потери): $rej"
if ($ok -gt 0 -and -not $DryRun) {
    $reindexPs = Join-Path $SCRIPTS_DIR "reindex.ps1"
    if (Test-Path $reindexPs) { & $reindexPs 2>&1 | Select-Object -Last 1 }
}
