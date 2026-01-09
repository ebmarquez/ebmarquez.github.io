# GitHub Copilot Instructions for ebmarquez.github.io

## Post Date Formatting
**CRITICAL:** When creating or suggesting Jekyll blog posts, always use midnight Pacific time for timestamps.

### Required Format
```yaml
date: YYYY-MM-DD 00:00:00 -0800
```

### Example
```yaml
date: 2026-01-09 00:00:00 -0800
```

### Why This Matters
Jekyll doesn't publish posts with future dates. Since GitHub Actions builds in UTC, using noon or later times (in PST) can cause posts to be treated as "future" and not published.

## Other Requirements
- Author field: `Eric Marquez`
- Use `categories:` (plural) not `category:`
- Use `description:` not `summary:` for SEO
