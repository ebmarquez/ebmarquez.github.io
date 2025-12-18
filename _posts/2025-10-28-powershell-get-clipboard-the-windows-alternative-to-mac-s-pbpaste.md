---
layout: post
title: "PowerShell Get-Clipboard: The Windows Alternative to Mac's pbpaste"
date: 2025-10-28
categories: [powershell, tips, windows]
tags: [powershell, clipboard, windows, productivity, commandline]
author: Eric Marquez
description: "Learn about PowerShell's Get-Clipboard command - the Windows equivalent to Mac's pbpaste for clipboard management."
excerpt: "While watching a YouTube video, I discovered Mac's pbpaste command and wondered if Windows had something similar. PowerShell's Get-Clipboard provides the same functionality."
---


As a PowerShell enthusiast, I thought I knew all the essential clipboard tricks. I've been using the `clip` command for years to redirect CLI output straight to my clipboard:

```powershell
dir temp | clip
```

Simple, effective, and a real time-saver. But today, while watching a YouTube video of someone building a development tool, I discovered something that made me pause the video and immediately open my terminal.

## The Mac Approach

The presenter was working on a Mac and used this command:

```bash
pbpaste > mynewfile
```

This redirects clipboard content directly into a new file - a useful technique for quickly capturing and manipulating clipboard content in scripts and workflows.

I must admit I was a bit jealous of this command. My typical workflow involved copying content, pasting it into a file, and then working with that file for redirection. This single command eliminated multiple steps and was much more elegant. I had never seen anything like this before, nor had I seen anyone else use a similar technique.

## The Windows Equivalent

This made me wonder, does PowerShell have something similar?

It does. PowerShell provides the same functionality through a built-in command. The command is `Get-Clipboard` - which just rolls off the tongue, right? Thankfully, it also has a short alias `gcb`:

```powershell
# The full command
Get-Clipboard

# The short alias
gcb
```

## Practical Examples

### Basic Clipboard Retrieval

```powershell
# Get whatever is currently in your clipboard
gcb

# Redirect clipboard content to a file (just like pbpaste!)
gcb > mynewfile.txt

# Append clipboard content to an existing file
gcb >> logfile.txt
```

### PowerShell Pipeline Power

Since this is PowerShell, you get all the pipeline goodness:

```powershell
# Count lines in clipboard content
gcb | Measure-Object -Line

# Search for specific text in clipboard
gcb | Select-String "error"

# Process clipboard content and save filtered results
gcb | Where-Object { $_ -like "*important*" } > filtered.txt

# Convert clipboard JSON to PowerShell objects
gcb | ConvertFrom-Json
```

### Workflow Examples

#### Scenario 1: Quick Log Analysis

Copy some log content from a web interface, then:

```powershell
gcb | Select-String "ERROR|WARN" | Out-File errors.log
```

#### Scenario 2: Code Snippet Management

```powershell
# Save a code snippet from clipboard
gcb > "snippets\$(Get-Date -Format 'yyyy-MM-dd-HHmm').ps1"
```

#### Scenario 3: Data Processing

```powershell
# Process CSV data copied from Excel
gcb | ConvertFrom-Csv | Where-Object Status -eq "Active"
```

## The Complete Clipboard Toolkit

Now you have the full Windows clipboard command:

| Direction          | Command                  | Example          |
| ------------------ | ------------------------ | ---------------- |
| **To Clipboard**   | `clip`                   | `dir \| clip`    |
| **From Clipboard** | `Get-Clipboard` or `gcb` | `gcb > file.txt` |

## Additional Resources

- [PowerShell Get-Clipboard Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-clipboard)
- [PowerShell Pipeline Fundamentals](https://docs.microsoft.com/en-us/powershell/scripting/learn/understanding-the-powershell-pipeline)
- [Using clip Command in Windows](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/clip)