---
layout: post
title: "When Git Gaslights You: The Line Ending Betrayal"
date: 2026-01-09 00:00:00 -0800
categories: [development, git]
tags: [git, development, troubleshooting, windows, cross-platform, version-control, devops]
author: Eric Marquez
description: "That moment when git reset --hard does nothing and files stay modified. A deep dive into solving the Git line ending mystery that haunts cross-platform teams."
image:
  path: https://images.unsplash.com/photo-1556075798-4825dfaaf498?w=1200&q=80
  alt: "Code on a computer screen showing Git commands and terminal output"
---

## The Crime Scene

So there I was, returning to a repo I hadn't touched in over a month. You know the drill: `git pull`, `git switch` to your branch, and off you go. Except... not this time.

Git decided to welcome me back with a surprise:

```bash
Changes not staged for commit:
  modified:   global.json
  modified:   src/owners.txt
```

Wait. What? I literally just pulled. These files—especially that `owners.txt` someone else updated weeks ago—had nothing to do with my current work. Whatever stale local changes existed, I didn't need them.

**No problem**, I thought. **That's what `git reset --hard HEAD` is for.**

```powershell
git reset --hard HEAD
```

_Git blinks back at me._

```bash
Changes not staged for commit:
  modified:   global.json
  modified:   src/owners.txt
```

The files were _still there_. Still modified. Still mocking me.

I tried `git checkout -- .` for good measure. Nothing. The files refused to return to a clean state. At this point, I'm questioning my understanding of basic Git commands and wondering if I should just nuke the whole clone and start over.

**Welcome to the line ending betrayal.** Let me introduce you to the villain.

## Meet the Villain: CRLF vs LF (If It's Not UTF-8, It's EOL)

Here's the thing about line endings: they're invisible, platform-specific, and _absolutely love_ causing chaos in multi-OS dev teams. Which, spoiler alert, was exactly my situation. And if it's not a UTF-8 encoding issue causing you grief, it's line endings—End Of Line in the most literal, painful sense.

**The Cast of Characters:**

- **Windows**: Uses CRLF (Carriage Return + Line Feed: `\r\n`) — two characters to end a line because Windows doesn't do anything simply
- **Linux/macOS**: Uses LF (Line Feed only: `\n`) — one character because Unix systems are efficient like that
- **Your repo**: A mixed bag of files that may have _either_ depending on who last touched them and what their local Git config decided to do

Think of line endings like regional power outlets. Same purpose (electricity/line breaks), different implementation, total incompatibility. Except instead of blowing a fuse, you blow your afternoon debugging phantom file changes.

### Git's "Helpful" Line Ending Management

Git tries to save you from this nightmare through:

1. **`core.autocrlf`** - Your local Git config's attempt at auto-conversion
2. **`.gitattributes`** - The repository's official "this is how we do things" declaration

**The Settings Breakdown:**

- **`core.autocrlf=true`** (Windows default): Git converts LF → CRLF on checkout, CRLF → LF on commit. "I'll fix everything!" energy.
- **`core.autocrlf=input`**: Git converts CRLF → LF on commit, but leaves checkouts alone. "I'll normalize but not be pushy."
- **`core.autocrlf=false`**: "You're on your own, buddy." No conversion whatsoever.
- **`.gitattributes`**: The nuclear option. Overrides `core.autocrlf` per file pattern. "My repo, my rules."

When these settings disagree with the actual bytes in your files, Git enters a confused state where it perpetually thinks files are modified. It's trying to "fix" something that isn't broken _from your perspective_, but looks wrong _from its configuration perspective_.

## The Detective Work (AKA How I Figured This Out)

When Git commands you've used a thousand times suddenly stop working, you go into diagnostic mode. Here's how to confirm you're dealing with line ending shenanigans:

### Step 1: Confirm the Ghost Files

```powershell
git status
```

Yeah, still showing modified. Cool cool cool.

### Step 2: Check What "Changed"

```powershell
git diff global.json
```

You'll see output showing differences, but when you stare at it, nothing _actually_ looks different. The content is the same. This is your first clue that something invisible is wrong.

### Step 3: The Smoking Gun Test

```powershell
git diff --ignore-all-space global.json
```

**The key moment**: If this shows **no differences**, but regular `git diff` does, congratulations—you've got a line ending problem. The "changes" are literally just invisible newline characters.

### Step 4: Interrogate Your Git Config

```powershell
# Check what your local repo thinks
git config core.autocrlf

# Check your global setting
git config --global core.autocrlf
```

Mine said: `true`. Which means Git was in "helpful Windows mode."

### Step 5: Review the .gitattributes File

This is where things got interesting:

```gitattributes
# My repository's .gitattributes
*.json text eol=crlf
*.txt text
*.yml text eol=crlf
*.yaml text eol=crlf
```

Ah. There it is.

### Step 6: Identify the Conflict

**The problem was a three-way disagreement:**

1. **`.gitattributes`** said: "JSON and TXT files should have CRLF"
2. **The actual files in the repo** had: LF line endings (probably committed from a Linux box or by someone with different settings)
3. **My `core.autocrlf=true`** said: "I should fix this!"

So Git kept trying to "correct" the files to match `.gitattributes`, which made them appear modified. But I couldn't commit them because they weren't _really_ changed. And `git reset --hard` couldn't fix them because Git thought the "fixed" version _was_ the correct version.

The call is coming from inside the house. Git is both the villain and the victim.

## The Fix (Three Approaches, Choose Your Own Adventure)

Once I knew what I was dealing with, I had options. Here's what worked:

### Option 1: Normalize to Match .gitattributes (The "Let Git Win" Approach)

If your `.gitattributes` is correct and you want files to match it:

```powershell
# Remove all files from the index (staging area)
git rm --cached -r .

# Re-add them, letting Git apply line ending rules from .gitattributes
git add .

# Check what changed
git status

# Commit the normalized files
git commit -m "Normalize line endings per .gitattributes"
```

**When to use this**: Your `.gitattributes` is gospel, and the repo should be consistent with it going forward.

**Caveat**: This creates a commit that touches _every file_ with line ending differences. Your `git blame` history will have a fun time with that one.

### Option 2: Disable Conversion (The "I Live Dangerously" Approach)

If you want Git to stop trying to manage line endings entirely:

```powershell
# Set autocrlf to false
git config core.autocrlf false

# Now reset
git reset --hard HEAD
```

**When to use this**: You're confident the files are fine as-is, and you don't want Git second-guessing.

**Caveat**: You're now responsible for line ending consistency. If you're on a cross-platform team, this can bite you later.

### Option 3: The Hybrid (What I Actually Did)

Since my `.gitattributes` was partially wrong and I wanted a clean slate:

```powershell
# 1. Set autocrlf to input (normalize on commit, but don't mess with checkouts)
git config core.autocrlf input

# 2. Update .gitattributes to be more sensible
# (Changed *.txt from CRLF requirement to just "text", let Git decide)

# 3. Normalize the repo
git rm --cached -r .
git add .
git commit -m "Fix line endings and update .gitattributes"

# 4. Pull to ensure clean state
git reset --hard HEAD
```

**When to use this**: You want control over your `.gitattributes` strategy _and_ you want Git to help normalize things going forward.

**Result**: Clean repo, sensible rules, no phantom modifications.

## The Lesson (What I'll Remember Next Time)

When `git reset --hard` doesn't work, it's not broken—it's confused. The file _is_ in the state Git thinks is correct. The problem is that "correct" is defined by conflicting rules.

**Red flags that you're dealing with line endings:**

- Files show as modified immediately after checkout
- `git diff` shows changes but `git diff --ignore-all-space` doesn't
- `git reset --hard` or `git checkout` have no effect
- You're working cross-platform (Windows ↔ Linux/Mac)
- Your `.gitattributes` exists and references `eol=crlf` or `eol=lf`

**The hierarchy of who wins:**

1. **.gitattributes** (repository level - overrides everything)
2. **core.autocrlf** (local Git config)
3. **Actual bytes in files** (reality, but Git will try to change it)

When these disagree, chaos ensues.

## The Takeaway (TL;DR for Time Travelers)

**Problem**: Git shows files as modified, but you didn't change them, and reset commands don't fix it.

**Likely Cause**: Line ending conversion rules (`.gitattributes` + `core.autocrlf`) conflict with actual file line endings.

**Quick Diagnosis**:

```powershell
git diff --ignore-all-space [filename]
```

If this shows nothing but regular `git diff` does = line ending problem.

**Fix Options**:

1. **Normalize files to .gitattributes**: `git rm --cached -r . && git add . && git commit`
2. **Disable autocrlf**: `git config core.autocrlf false && git reset --hard`
3. **Hybrid approach**: Set `autocrlf=input`, update `.gitattributes`, normalize

**Pro Tip**: If you're on a cross-platform team, agree on `.gitattributes` rules _early_. It's way easier to prevent than fix.

## Resources & Further Reading

- [Git Pro Book - 8.1 Customizing Git - Configuration](https://git-scm.com/book/en/v2/Customizing-Git-Git-Configuration)
- [GitHub: Dealing with line endings](https://docs.github.com/en/get-started/getting-started-with-git/configuring-git-to-handle-line-endings)
- [.gitattributes Best Practices](https://www.aleksandrhovhannisyan.com/blog/crlf-vs-lf-normalizing-line-endings-in-git/)

---

**Have you fought the line ending battle?** What was your war story? Drop a comment—misery loves company, especially when it involves invisible characters breaking your workflow.
