#!/usr/bin/env pwsh
# Validate Jekyll post dates before committing

Write-Host "🔍 Checking post timestamps..." -ForegroundColor Cyan

$issues = 0
$posts = Get-ChildItem -Path "_posts/*.md" -ErrorAction SilentlyContinue

if (-not $posts) {
    Write-Host "✅ No posts found to validate" -ForegroundColor Green
    exit 0
}

$currentTime = Get-Date
$currentUTC = $currentTime.ToUniversalTime()

foreach ($post in $posts) {
    $content = Get-Content $post -Raw
    
    # Extract date from frontmatter
    if ($content -match '(?m)^date:\s*(.+)$') {
        $dateString = $Matches[1].Trim()
        
        # Check for noon or later timestamps (12:00 PM or later in PST)
        if ($dateString -match '(1[2-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\s+-08') {
            Write-Host "⚠️  Warning: $($post.Name)" -ForegroundColor Yellow
            Write-Host "   Uses noon or later timestamp: $dateString" -ForegroundColor Yellow
            Write-Host "   Recommend: Use 00:00:00 -0800 instead" -ForegroundColor Yellow
            $issues++
        }
        
        # Try to parse the date and check if it's in the future
        try {
            # Parse format like "2026-01-09 00:00:00 -0800"
            if ($dateString -match '(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+([-+]\d{4})') {
                $datePart = $Matches[1]
                $timePart = $Matches[2]
                $offsetPart = $Matches[3]
                
                # Parse as datetime
                $postDate = [DateTime]::Parse("$datePart $timePart")
                
                # Parse timezone offset
                $offsetHours = [int]($offsetPart.Substring(1,2))
                $offsetMins = [int]($offsetPart.Substring(3,2))
                $totalOffset = $offsetHours * 60 + $offsetMins
                if ($offsetPart[0] -eq '-') { $totalOffset = -$totalOffset }
                
                # Convert to UTC
                $postUTC = $postDate.AddMinutes(-$totalOffset)
                
                if ($postUTC -gt $currentUTC) {
                    Write-Host "⚠️  Warning: $($post.Name)" -ForegroundColor Yellow
                    Write-Host "   Has future timestamp: $dateString" -ForegroundColor Yellow
                    Write-Host "   Current UTC: $($currentUTC.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
                    Write-Host "   Jekyll may skip this post without 'future: true'" -ForegroundColor Yellow
                    $issues++
                }
            }
        }
        catch {
            Write-Host "⚠️  Warning: Could not parse date in $($post.Name): $dateString" -ForegroundColor Yellow
            $issues++
        }
    }
    else {
        Write-Host "⚠️  Warning: $($post.Name) has no date field" -ForegroundColor Yellow
        $issues++
    }
}

Write-Host ""
if ($issues -gt 0) {
    Write-Host "⚠️  Found $issues issue(s) with post timestamps" -ForegroundColor Yellow
    Write-Host "ℹ️  Best practice: Always use '00:00:00 -0800' for post dates" -ForegroundColor Cyan
    Write-Host "ℹ️  Your site has 'future: true' enabled, so posts should still publish" -ForegroundColor Cyan
    exit 0  # Don't block commits, just warn
}
else {
    Write-Host "✅ All post timestamps look good!" -ForegroundColor Green
    exit 0
}
