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
    if ($matches[1] -match '(?m)^date:\s*(.+)$') {
        $dateLine = $matches[1].Trim()
        if ($dateLine -notmatch '[-+]\d{4}') {
            $issues += "Missing timezone"
        } elseif ($dateLine -notmatch '(-0800|-0700)') {
            $issues += "Wrong timezone (must be -0800 or -0700)"
        }
        
        # Check if time is NOT midnight (00:00:00)
        if ($dateLine -notmatch '00:00:00') {
            $issues += "Must use midnight (00:00:00) for all posts"
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

function Repair-BlogPost {
    param([hashtable]$ValidationResult)
    $content = $ValidationResult.Content
    $currentOffset = Get-CurrentPacificOffset
    
    # Fix timezone AND enforce midnight (00:00:00)
    $content = $content -replace '(date:\s*\d{4}-\d{2}-\d{2}\s+)\d{2}:\d{2}:\d{2}(\s+)[-+]\d{4}', "`${1}00:00:00`$2$currentOffset"
    
    Set-Content -Path $ValidationResult.FilePath -Value $content -NoNewline
    Write-Host "  FIXED to midnight with timezone $currentOffset" -ForegroundColor Green
}

Write-Host ""
Write-Host "Blog Post Timezone Validator" -ForegroundColor Cyan
Write-Host ""

if ($PostFile) {
    $filesToCheck = @($PostFile)
} else {
    $filesToCheck = Get-ChildItem -Path $POSTS_DIR -Filter "*.md" | Select-Object -ExpandProperty FullName
}

Write-Host "Checking $($filesToCheck.Count) blog post(s)..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $filesToCheck) {
    $result = Test-BlogPost -FilePath $file
    if ($result.Valid) {
        Write-Host "PASS: $($result.File)" -ForegroundColor Green
        Write-Host "  Date: $($result.DateLine)"
    } else {
        Write-Host "FAIL: $($result.File)" -ForegroundColor Red
        Write-Host "  Date: $($result.DateLine)"
        foreach ($issue in $result.Issues) {
            Write-Host "  WARNING: $issue" -ForegroundColor Yellow
        }
        if ($Fix) {
            Repair-BlogPost -ValidationResult $result
        }
    }
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Cyan
Write-Host ""
