# Post Date Validation Setup

This repository now includes automated validation to prevent Jekyll publish issues caused by problematic post timestamps.

## The Problem

Jekyll doesn't publish posts with future dates by default. When GitHub Actions builds in UTC, posts with timestamps later in the day (like noon PST) can be treated as "future" posts and skipped during the build.

**Example:**
- Post date: `2026-01-09 12:00:00 -0800` (noon PST)
- GitHub Actions runs at 11 AM PST = 19:00 UTC
- Post date in UTC = 20:00 UTC (8 PM UTC)
- Since 20:00 > 19:00, Jekyll treats the post as "future" ❌

## The Solution

### 1. Config Change
Added `future: true` to [_config.yml](_config.yml) - Posts with future dates will always publish.

### 2. Best Practice
Always use midnight timestamps: `YYYY-MM-DD 00:00:00 -0800`

### 3. Automated Checks

#### GitHub Actions (Automatic)
The [pages-deploy.yml](.github/workflows/pages-deploy.yml) workflow now includes a validation step that checks every post on push:
- ✅ Warns about noon or later timestamps
- ✅ Detects future-dated posts
- ✅ Runs automatically on every push
- ℹ️ Non-blocking (doesn't fail the build)

#### Local Validation Script
Run before committing:
```powershell
.\tools\validate-posts.ps1
```

### 4. Copilot Instructions
Added explicit date handling rules to:
- [AGENT.md](AGENT.md) - Repository-wide agent instructions
- [.github/copilot-instructions.md](.github/copilot-instructions.md) - GitHub Copilot specific

## Quick Reference

### ✅ Correct Date Format
```yaml
date: 2026-01-09 00:00:00 -0800
```

### ❌ Problematic Formats
```yaml
date: 2026-01-09 12:00:00 -0800  # Noon - might be "future" during UTC build
date: 2026-01-09 18:00:00 -0800  # Evening - definitely "future" during UTC build
date: 2026-01-10 00:00:00 -0800  # Actual future date
```

## Files Added/Modified

- ✅ `.github/workflows/pages-deploy.yml` - Added validation step
- ✅ `.github/copilot-instructions.md` - Created Copilot instructions
- ✅ `AGENT.md` - Updated with date handling rules
- ✅ `tools/validate-posts.ps1` - Local validation script
- ✅ `_config.yml` - Added `future: true`
- ✅ `README.md` - Documented helper tools

## Commit These Changes

```powershell
git add .github/copilot-instructions.md .github/workflows/pages-deploy.yml AGENT.md tools/validate-posts.ps1 _config.yml README.md
git commit -m "feat: add post date validation and helper tools"
git push
```

## Testing

After pushing, check the GitHub Actions run to see the validation in action:
- Go to: https://github.com/ebmarquez/ebmarquez.github.io/actions
- Click on the latest "Build and Deploy" workflow
- Check the "Validate post dates" step output
