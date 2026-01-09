#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates blog post timezone formatting in Jekyll _posts directory

.DESCRIPTION
    Checks all markdown files in _posts/ for proper timezone formatting in frontmatter.
    Ensures dates use Pacific timezone (-0800 PST or -0700 PDT) to match _config.yml setting.

.PARAMETER Fix
    Automatically fix timezone issues found

.PARAMETER PostFile
    Validate a specific blog post file instead of all posts

.EXAMPLE
    .\validate-blog-timezone.ps1
    Validates all blog posts in _posts/

.EXAMPLE
    .\validate-blog-timezone.ps1 -Fix
    Validates and auto-fixes all timezone issues

.EXAMPLE
    .\validate-blog-timezone.ps1 -PostFile "_posts\2026-01-09-my-post.md"
    Validates a specific blog post
#>

param(
    [switch]$Fix,
    [string]$PostFile
)

$ErrorActionPreference = "Stop"

# Configuration
$REPO_ROOT = Split-Path -Parent $PSScriptRoot
$POSTS_DIR = Join-Path $REPO_ROOT "_posts"
$VALID_TIMEZONES = @("-0800", "-0700")
$TIMEZONE_NAME = "America/Los_Angeles"

# ANSI color codes
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$RESET = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $RESET)
    Write-Host "$Color$Message$RESET"
}

function Get-CurrentPacificOffset {
    $now = Get-Date
    $year = $now.Year
    $marchSundays = 1..31 | Where-Object { (Get-Date -Year $year -Month 3 -Day $_).DayOfWeek -eq 'Sunday' }
    $novemberSundays = 1..30 | Where-Object { (Get-Date -Year $year -Month 11 -Day $_).DayOfWeek -eq 'Sunday' }
    $dstStart = Get-Date -Year $year -Month 3 -Day $marchSundays[1]
    $dstEnd = Get-Date -Year $year -Month 11 -Day $novemberSundays[0]
    if ($now -ge $dstStart -and $now -lt $dstEnd) { return "-0700" } else { return "-0800" }
}

function Test-BlogPostTimezone {
    param([string]$FilePath)
    $fileName = Split-Path -Leaf $FilePath
    $issues = @()
    $content = Get-Content $FilePath -Raw
    if ($content -notmatch '(?s)^---\s*\n(.*?)\n---') {
        return @{ File = $fileName; Issues = @("No frontmatter found"); Valid = $false }
    }
    $frontmatter = $matches[1]
    $dateLine = ""
    if ($frontmatter -match 'date:\s*(.+)$') {
        $dateLine = $matches[1].Trim()
        if ($dateLine -notmatch '[-+]\d{4}') {
            $issues += "Missing timezone offset (should be -0800 or -0700)"
        } elseif ($dateLine -notmatch '(-0800|-0700)') {
            if ($dateLine -match '([-+]\d{4})') {
                $issues += "Invalid timezone '$($matches[1])' (should be -0800 or -0700)"
            }
        }
        if ($dateLine -notmatch '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+[-+]\d{4}') {
            $issues += "Date format should be: YYYY-MM-DD HH:MM:SS ±HHMM"
        }
    } else {
        $issues += "No 'date:' field found in frontmatter"
    }
    return @{ File = $fileName; DateLine = $dateLine; Issues = $issues; Valid = ($issues.Count -eq 0); Content = $content; FilePath = $FilePath }
}

function Repair-BlogPostTimezone {
    param([hashtable]$ValidationResult)
    $content = $ValidationResult.Content
    $currentOffset = Get-CurrentPacificOffset
    $content = $content -replace '(date:\s*\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s+)[-+]\d{4}', "`$1$currentOffset"
    Set-Content -Path $ValidationResult.FilePath -Value $content -NoNewline
    Write-ColorOutput "  ✓ Fixed timezone to $currentOffset" $GREEN
}

Write-ColorOutput "`n🔍 Blog Post Timezone Validator`n" $BLUE
Write-ColorOutput "Expected timezone: $TIMEZONE_NAME (PST: -0800, PDT: -0700)" $BLUE
$currentOffset = Get-CurrentPacificOffset
Write-ColorOutput "Current Pacific offset: $currentOffset`n" $BLUE

$filesToCheck = @()
if ($PostFile) {
    if (Test-Path $PostFile) { $filesToCheck = @($PostFile) }
    else { Write-ColorOutput "❌ File not found: $PostFile" $RED; exit 1 }
} else {
    if (-not (Test-Path $POSTS_DIR)) { Write-ColorOutput "❌ Posts directory not found: $POSTS_DIR" $RED; exit 1 }
    $filesToCheck = Get-ChildItem -Path $POSTS_DIR -Filter "*.md" | Select-Object -ExpandProperty FullName
}

if ($filesToCheck.Count -eq 0) { Write-ColorOutput "⚠️  No blog posts found to validate" $YELLOW; exit 0 }

Write-ColorOutput "Checking $($filesToCheck.Count) blog post(s)...`n" $BLUE
$results = @()
$hasIssues = $false

foreach ($file in $filesToCheck) {
    $result = Test-BlogPostTimezone -FilePath $file
    $results += $result
    if ($result.Valid) {
        Write-ColorOutput "✓ $($result.File)" $GREEN
        Write-ColorOutput "  Date: $($result.DateLine)" $RESET
    } else {
        $hasIssues = $true
        Write-ColorOutput "✗ $($result.File)" $RED
        Write-ColorOutput "  Date: $($result.DateLine)" $RESET
        foreach ($issue in $result.Issues) { Write-ColorOutput "  ⚠️  $issue" $YELLOW }
        if ($Fix) { Repair-BlogPostTimezone -ValidationResult $result }
    }
    Write-Host ""
}

Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" $BLUE
$validCount = ($results | Where-Object { $_.Valid }).Count
$invalidCount = ($results | Where-Object { -not $_.Valid }).Count
Write-ColorOutput "✓ Valid: $validCount" $GREEN
if ($invalidCount -gt 0) {
    Write-ColorOutput "✗ Issues found: $invalidCount" $RED
    if (-not $Fix) { Write-ColorOutput "`n💡 Run with -Fix to automatically correct timezone issues" $YELLOW }
}
Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" $BLUE
if ($hasIssues -and -not $Fix) { exit 1 } else { exit 0 }
