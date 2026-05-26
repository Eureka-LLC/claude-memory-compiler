# Claude CLI utilities — dot-source this file: . "$PSScriptRoot\_api.ps1"
# Requires: claude CLI installed and authenticated (claude auth login)

# Calls claude -p with the given prompt via stdin. Returns response text.
function Invoke-ClaudeCLI {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $cliArgs = @("-p", "--output-format", "text")
    if ($DEFAULT_MODEL) {
        $cliArgs += "--model"
        $cliArgs += $DEFAULT_MODEL
    }

    $prevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $output = $Prompt | & claude @cliArgs 2>$null
    [Console]::OutputEncoding = $prevEncoding

    if ($LASTEXITCODE -ne 0) {
        throw "claude CLI exited with code $LASTEXITCODE. Verify that 'claude' is in PATH and authenticated (run: claude auth login)."
    }

    return ($output -is [array]) ? ($output -join "`n") : [string]$output
}

# Parses structured file-operation blocks from compile/query output.
# Format used in prompts:
#   <<<WRITE:path/to/file.md>>>
#   [content]
#   <<<END>>>
#
#   <<<APPEND:path/to/file.md>>>
#   [content]
#   <<<END>>>
function Invoke-ParseFileOps {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [Parameter(Mandatory)]
        [string]$RootDir
    )

    $pattern = [regex]::new(
        '<<<(WRITE|APPEND):([^>]+)>>>(.*?)<<<END>>>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $ops = $pattern.Matches($Text)
    if ($ops.Count -eq 0) { return 0 }

    $count = 0
    foreach ($m in $ops) {
        $action  = $m.Groups[1].Value
        $relPath = $m.Groups[2].Value.Trim()
        $content = $m.Groups[3].Value -replace '^\r?\n', ''   # strip leading newline

        $result = Invoke-FileTool -ToolName ($action.ToLower() + "_file") `
            -ToolInput @{ path = $relPath; content = $content } `
            -RootDir $RootDir
        Write-Host "    $result"
        $count++
    }
    return $count
}

# Security-checked file write/append — only writes inside RootDir.
function Invoke-FileTool {
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,    # "write_file" or "append_file"
        [Parameter(Mandatory)]
        $ToolInput,
        [Parameter(Mandatory)]
        [string]$RootDir
    )

    $path = $ToolInput.path
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $path = Join-Path $RootDir $path
    }
    $realPath = [System.IO.Path]::GetFullPath($path)
    $realRoot = [System.IO.Path]::GetFullPath($RootDir)

    $sep = [System.IO.Path]::DirectorySeparatorChar
    if (-not $realPath.StartsWith($realRoot + $sep) -and $realPath -ne $realRoot) {
        return "Error: '$realPath' is outside project directory."
    }

    $dir = [System.IO.Path]::GetDirectoryName($realPath)
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    switch ($ToolName) {
        "write_file" {
            [System.IO.File]::WriteAllText($realPath, $ToolInput.content, [System.Text.Encoding]::UTF8)
            return "Written: $realPath"
        }
        "append_file" {
            [System.IO.File]::AppendAllText($realPath, $ToolInput.content, [System.Text.Encoding]::UTF8)
            return "Appended: $realPath"
        }
        default { return "Unknown tool: $ToolName" }
    }
}
