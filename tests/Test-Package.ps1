#requires -Version 7.0
[CmdletBinding()]
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-MarkdownInfo {
    param([string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    $prose = [regex]::Replace($text, '(?ms)^```[^\r\n]*\r?\n.*?^```[^\r\n]*\r?$', '')
    $anchors = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $headings = @()
    $counts = @{}
    foreach ($match in [regex]::Matches($prose, '(?m)^(#{1,6})[ \t]+(.+?)\r?$')) {
        $title = $match.Groups[2].Value.Trim()
        $slug = [regex]::Replace($title.ToLowerInvariant(), '[^\p{L}\p{N}_ -]', '').Replace(' ', '-')
        $number = if ($counts.ContainsKey($slug)) { $counts[$slug] } else { 0 }
        $counts[$slug] = $number + 1
        $anchor = if ($number -eq 0) { $slug } else { "$slug-$number" }
        $null = $anchors.Add($anchor)
        $headings += [pscustomobject]@{ Level = $match.Groups[1].Length; Title = $title; Anchor = $anchor }
    }
    foreach ($match in [regex]::Matches($prose, '<a\s+(?:id|name)="([^"]+)"')) {
        $null = $anchors.Add($match.Groups[1].Value)
    }
    [pscustomobject]@{ Prose = $prose; Headings = $headings; Anchors = $anchors }
}

$documents = @((Get-Item -LiteralPath "$Root\Readme.md")) +
    @(Get-ChildItem -LiteralPath "$Root\docs" -Filter '*.md' -File -Recurse)
$cache = @{}
foreach ($file in $documents) { $cache[$file.FullName] = Get-MarkdownInfo $file.FullName }
$linksChecked = 0
foreach ($file in $documents) {
    $info = $cache[$file.FullName]
    foreach ($heading in $info.Headings) {
        if ($heading.Level -in 2, 3 -and $heading.Title -notin 'Contents', 'Table of contents') {
            Assert-True ($info.Prose.Contains("](#$($heading.Anchor))")) "TOC missing '$($heading.Title)' in $($file.Name)."
        }
    }
    foreach ($match in [regex]::Matches($info.Prose, '!?\[[^\]\r\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"]*")?\)')) {
        $target = [Uri]::UnescapeDataString($match.Groups[1].Value.Trim('<', '>'))
        if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') {
            Assert-True ($target -notmatch '^(file:|https://file\+)') "Nonportable editor/file link in $($file.Name)."
            continue
        }
        $parts = $target.Split('#', 2)
        $destination = if ($parts[0]) {
            [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $parts[0]))
        } else { $file.FullName }
        $relative = [IO.Path]::GetRelativePath($Root, $destination)
        Assert-True (-not $relative.StartsWith('..') -and -not [IO.Path]::IsPathRooted($relative)) "Link escapes package in $($file.Name): $target"
        Assert-True (Test-Path -LiteralPath $destination) "Missing destination in $($file.Name): $target"
        if ($parts.Count -eq 2 -and $parts[1]) {
            Assert-True ($cache.ContainsKey($destination)) "Anchor target is not a published Markdown document: $target"
            Assert-True ($cache[$destination].Anchors.Contains($parts[1])) "Missing anchor in $($file.Name): $target"
        }
        $linksChecked++
    }
    foreach ($match in [regex]::Matches($info.Prose, '(?:src|href)="([^"]+)"')) {
        $target = $match.Groups[1].Value
        Assert-True ($target -match '^https://' -or
            (Test-Path -LiteralPath (Join-Path $file.DirectoryName $target))) "Missing HTML resource in $($file.Name): $target"
    }
    $columns = 0
    foreach ($line in ($info.Prose -split '\r?\n')) {
        if ($line.Trim().StartsWith('|')) {
            $width = [regex]::Split($line.Trim().Trim('|'), '(?<!\\)\|').Count
            if ($columns -ne 0) { Assert-True ($width -eq $columns) "Table width mismatch in $($file.Name): $line" }
            $columns = $width
        } else { $columns = 0 }
    }
}

$scripts = @(Get-ChildItem -LiteralPath "$Root\scripts", "$Root\tests" -Filter '*.ps1' -File -Recurse)
foreach ($file in $scripts) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) { throw "PowerShell parse failure: $($file.Name): $($errors.Message -join '; ')" }
}
$null = Get-Content -LiteralPath "$Root\infra\azd\main.parameters.json" -Raw | ConvertFrom-Json
$ignore = @(Get-Content -LiteralPath "$Root\.gitignore")
foreach ($rule in @('/.local/', '/AGENTS.md', '/docs/Error-and-Solutions.md', '/.azure/', '.env', '.env.*')) {
    Assert-True ($ignore -contains $rule) "Missing private-file ignore rule: $rule"
}
$attributes = @(Get-Content -LiteralPath "$Root\.gitattributes")
foreach ($rule in @('*.ps1 -text', 'data/*.tsv -text', 'data/Synthetic-ULS.log -export-ignore', '/.local/** export-ignore', '/.azure/** export-ignore', '/AGENTS.md export-ignore', '/docs/Error-and-Solutions.md export-ignore')) {
    Assert-True ($attributes -contains $rule) "Missing byte/distribution policy: $rule"
}
$data = [Text.UTF8Encoding]::new($false, $true).GetString(
    [IO.File]::ReadAllBytes("$Root\data\SharePoint-IncidentDemo-v1.tsv"))
Assert-True ($data.Contains("`r`n") -and -not $data.Replace("`r`n", '').Contains("`n")) 'Incident v1 data must retain CRLF bytes.'
Assert-True (-not (Test-Path -LiteralPath "$Root\Labs.md") -and
    -not (Test-Path -LiteralPath "$Root\Readme-0.1.md")) 'Superseded entry points must stay outside the published package.'

if (Test-Path -LiteralPath "$Root\.git") {
    $tracked = @(& git --no-pager -C $Root ls-files)
    Assert-True ($LASTEXITCODE -eq 0) 'Cannot inspect tracked publication paths.'
    foreach ($path in $tracked) {
        Assert-True ($path -eq 'data/Synthetic-ULS.log' -or
            $path -notmatch '(^|/)(\.local|\.azure)/|(^|/)AGENTS\.md$|(^|/)\.env($|\.)|\.(pem|pfx|log)$|\.local\.|\.results\.json$') "Private/generated file is tracked: $path"
    }
    Assert-True ($tracked -notcontains 'docs/Error-and-Solutions.md') 'Private troubleshooting notes must not be tracked.'
    foreach ($path in @('.local/publication-check', 'AGENTS.md', 'docs/Error-and-Solutions.md', '.azure/publication-check', '.env')) {
        $null = & git --no-pager -C $Root check-ignore --no-index -- $path
        Assert-True ($LASTEXITCODE -eq 0) "Git does not ignore private path: $path"
    }
} else {
    Write-Host 'No repository initialized; destination tracking/export checks remain a publication gate.'
}
Write-Host "PASS: $($documents.Count) Markdown documents, $linksChecked local links/anchors, $($scripts.Count) PowerShell sources, private-file rules and byte policy. No Azure calls."
