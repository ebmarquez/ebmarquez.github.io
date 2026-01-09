#!/usr/bin/env pwsh
param([switch]$Fix, [string]$PostFile)

$ErrorActionPreference = "Stop"
$REPO_ROOT = Split-Path -Parent $PSScriptRoot
$POSTS_DIR = Join-Path $REPO_ROOT "_posts"

function Get-CurrentPacificOffset {
    $now = Get-Date
    $year = $now.Year
    $marchSundays = 1..31 | Where-Object { (Get-Date -Year $year -Month 3 -Day $_).DayOfWeek -eq 'Sunday' }
    $novemberSundays = 1..30 | Where-Object { (Get-Date -Year $year -Month 11 -Day $_).DayOfWeek -eq 'Sunday' }
    $dstStart = Get-Date -Year $year -Month 3 -Day $marchSundays[1]
    $dstEnd = Get-Date -Year $year -Month 11 -Day $novemberSundays[0]
    if ($now -ge $dstStart -and $now -lt $dstEnd) { return "-0700" }
    return "-0800"
}

function Test-BlogPost {
    param([string]$FilePath)
    $fileName = Split-Path -Leaf $FilePath
    $issues = @()
    $content = Get-Content $FilePath -Raw
    
    if ($content -notmatch '(?s)^---\s*\n(.*?)\n---') {
        return @{ File = $fileName; Issues = @("No frontmatter"); Valid = $false }
    }
    
    $dateLine = ""
    if ($matches[1] -match 'date:\s*(.+)$') {
        $dateLine = $matches[1].Trim()
        if ($dateLine -notmatch '[-+]\d{4}') {
            $issues += "Missing timezone"
        } elseif ($dateLine -notmatch '(-0800|-0700)') {
            $issues += "Wrong timezone (must be -0800 or -0700)"
        }
    } else {
        $issues += "No date field"
    }
    
    return @{
        File = $fileName
        DateLine = $dateLine
        Issues = $issues
        Valid = ($issues.Count -eq 0)
        Content = $content
        FilePath = $FilePath
    }
}

Write-Host "`nðŸ” Blog Post Timezone Validator`n" -ForegroundColor Cyan

if ($PostFile) {
    $filesToCheck = @($PostFile)
} else {
    $filesToCheck = Get-ChildItem -Path $POSTS_DIR -Filter "*.md" | Select-Object -ExpandProperty FullName
}

foreach ($file in $filesToCheck) {
    $result = Test-BlogPost -FilePath $file
    if ($result.Valid) {
        Write-Host "âœ“ $($result.File)" -ForegroundColor Green
        Write-Host "  Date: $($result.DateLine)"
    } else {
        Write-Host "âœ— $($result.File)" -ForegroundColor Red
        Write-Host "  Date: $($result.DateLine)"
        foreach ($issue in $result.Issues) {
            Write-Host "  âš ï¸  $issue" -ForegroundColor Yellow
        }
    }
}

Write-Host "`nDone!`n" -ForegroundColor Cyan

