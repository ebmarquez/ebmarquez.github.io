---
layout: post
title: "nrecon-mcp: Building the Transport Layer (Part 2)"
date: 2026-02-14 00:00:00 -0800
categories: [Projects, MCP]
tags: [ssh, mcp, networking, copilot, open-source, typescript, prompt-detection]
author: eric
description: "From design doc to working code — how nrecon-mcp went from a midnight idea to a fully functional MCP server with SSH transport, prompt detection, and 61 passing tests in one week."
---

## Previously, On nrecon-mcp...

[Last week]({% post_url 2026-02-09-building-an-ssh-mcp-server-from-idea-to-design %}), I wrote about designing an MCP server that would let GitHub Copilot SSH into network devices and explore them autonomously. The pitch: instead of building another SSH command runner, build a *device discovery agent*. Something that connects to a mystery switch, figures out what it is, learns what it can do, and helps you make sense of it.

The design was solid. Option C — hybrid architecture. The MCP server handles the messy SSH transport problems (connections, prompt detection, paging, ANSI stripping). Copilot handles the intelligence (device fingerprinting, command discovery, reasoning).

But here's the thing about design docs: **they don't run code.**

So this week, I built it. All of it. Phase 1 and Phase 2 are done. The repo is public. The tests pass. The code works on real devices.

Let me tell you how it went down.

## Day One: Scaffolding and "Oh Right, ESM"

First order of business: create the repository. [`ebmarquez/nrecon-mcp`](https://github.com/ebmarquez/nrecon-mcp) was born on GitHub, and I cloned it locally. Empty repo. Clean slate. Time to scaffold.

TypeScript project setup in 2026 is... a thing. ESM modules are the future (allegedly), but half the Node ecosystem still assumes CommonJS. I went full ESM because the official MCP SDK from Anthropic is ESM-first, and I didn't want to fight the type system later.

Tech stack locked in:
- **TypeScript 5.9** — Strong types, clean code
- **`ssh2`** — Battle-tested SSH library for Node.js
- **`@modelcontextprotocol/sdk`** — Official MCP SDK
- **`vitest`** — Testing framework (because Jest is slow)
- **`tsup`** — Build tool (zero-config, lightning-fast)
- **`zod`** — Schema validation for tool inputs

I set up the project structure:

```
nrecon-mcp/
├── src/
│   ├── index.ts               # MCP server entry point
│   ├── ssh/
│   │   ├── ssh-connection.ts  # SSH connection handler
│   │   └── session-manager.ts # Multi-session management
│   ├── prompt/
│   │   └── prompt-detector.ts # Hybrid prompt detection
│   ├── utils/
│   │   └── strip-ansi.ts      # ANSI escape code stripper
│   └── output/
│       └── error-detector.ts  # Error pattern recognition
├── tests/                     # Test files mirror src/
├── package.json
├── tsconfig.json
└── README.md
```

Added `npm run build`, `npm run test`, `npm run lint`. The usual suspects. First commit: `feat: initial project scaffold`.

Time elapsed: **2 hours.**

This is the boring part. Nobody wants to read a blog post about configuring `tsconfig.json`. But it's necessary. Solid foundations matter. If your build setup is janky, everything downstream gets janky. I spent the time. Got it right.

Moving on.

## The Core Challenge: Prompt Detection Is *Hard*

Here's where things got interesting.

When you SSH into a device, you get a stream of bytes. That's it. No structured data. No JSON responses. Just... text. With ANSI escape codes. And banners. And `--More--` paging prompts. And unpredictable device prompts that change depending on configuration mode.

**The fundamental problem:** How do you know when a command is done?

You send a command. You wait for output. But *when do you stop waiting?* When do you say "okay, that's all the output, here's the result"?

You can't just wait for a newline — output has lots of newlines. You can't just wait for the command to return — there's no "return code" in an interactive SSH shell. You can't just set a timer — some commands are fast, some are slow.

**You need to detect the prompt.**

When the device prints the next prompt, that's your signal: "Command done. Ready for the next one." But here's the rub: **every device has a different prompt.**

- Linux bash: `user@host:~$`
- Cisco IOS: `Router#` (privileged mode) or `Router>` (user mode) or `Router(config)#` (config mode)
- Dell OS10: `DellEMC#` or `DellEMC(config)#`
- Arista EOS: `switch>` or `switch#`
- F5 tmsh: `(tmos)#`

Oh, and the hostname can change mid-session. And the mode can change. And sometimes there's a username prefix. And sometimes there's a path (`user@host:/etc/config$`). And sometimes there's... you get the idea.

**This is the hard part.**

## Three Approaches to Prompt Detection

I evaluated three strategies:

### Strategy A: Pattern Library

Maintain a giant list of regex patterns for every known device type. Match the last line of output against the list. If it matches, it's a prompt.

**Problem:** You need to know the device type *before* connecting. The whole point of nrecon-mcp is discovering *unknown* devices. This is a chicken-and-egg problem.

**Verdict:** Rejected.

### Strategy B: Silence Detection

Wait for output to stop. If no data arrives for N milliseconds, assume the command is done.

**Problem:** Some commands have legitimate pauses (e.g., `ping` waits between packets). Some devices print output slowly. If you set the timeout too short, you truncate output. If you set it too long, every command feels sluggish.

**Verdict:** Rejected (as a standalone approach).

### Strategy C: Hybrid Learning + Patterns + Silence

Here's what actually works:

1. **Learn the prompt on connect.** When you first SSH in, you get a banner followed by a prompt. The last non-empty line is almost always the prompt. Extract it. That's your baseline.

2. **Build a dynamic regex.** Parse the learned prompt to extract the stable prefix (hostname/username) and build a regex that matches that prompt in *any mode*.  
   Example: If you learn `Switch#`, build a regex that matches `Switch#`, `Switch>`, `Switch(config)#`, `Switch(config-if)#`, etc.

3. **Use generic fallback patterns.** If the learned regex doesn't match, fall back to a generic prompt pattern that matches common formats: `[\w@\-\.\/~:\[\]]+[#>$%]\s*$`

4. **Use silence as a safety net.** If you see output but no prompt is detected after 500ms of silence, assume the command is done anyway. (This handles edge cases like devices with weird prompts.)

**Verdict:** ✅ This is it.

## The Implementation: `PromptDetector`

The `PromptDetector` class is the brain of the operation. Here's how it works:

```typescript
export class PromptDetector {
  private basePrompt: string = "";
  private stablePrefix: string = "";
  private promptRegex: RegExp | null = null;

  // Phase 1: Learn from initial connection
  learnFromConnect(bannerAndPrompt: string): string {
    const lines = bannerAndPrompt.split("\n").filter((l) => l.trim());
    const lastLine = lines[lines.length - 1].trim();
    
    this.basePrompt = lastLine;
    this.stablePrefix = this.extractStablePrefix(lastLine);
    this.promptRegex = this.buildPromptRegex(this.stablePrefix);
    
    return lastLine;
  }

  // Phase 2: Check if a line is a prompt
  isPrompt(line: string): boolean {
    const trimmed = line.trim();
    if (this.promptRegex?.test(trimmed)) return true;
    if (GENERIC_PROMPT.test(trimmed)) return true;
    return false;
  }

  // Phase 3: Update when prompt changes
  updatePrompt(newPrompt: string): void {
    const newStable = this.extractStablePrefix(newPrompt);
    if (newStable !== this.stablePrefix) {
      // Hostname changed — re-learn
      this.stablePrefix = newStable;
      this.promptRegex = this.buildPromptRegex(newStable);
    }
  }
}
```

**The magic is in `extractStablePrefix`:**

It strips out everything that changes (mode suffixes like `(config)`, paths like `:~`, trailing prompt characters like `#>$%`) and keeps just the hostname/username part.

- `Switch(config)#` → `Switch`
- `user@host:~$` → `user@host`
- `Router>` → `Router`

Then it builds a regex that matches that prefix with *any* suffix:

```typescript
private buildPromptRegex(stable: string): RegExp {
  const escaped = stable.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${escaped}(\\([^)]*\\))?[:/~\\w]*[#>$%]\\s*$`);
}
```

**Result:** One learning phase. Dynamic adaptation. Works on Linux, Cisco, Dell, Arista, F5, and anything else with a reasonably sane prompt format.

This took me **6 hours** to get right. I wrote tests for 20+ different prompt formats. They all pass.

## Handling the Other SSH Nightmares

Prompt detection was the hardest part. But there were other transport problems to solve:

### ANSI Escape Codes

SSH output is riddled with ANSI escape codes — cursor movement, color codes, formatting. They look like `\x1b[1;32m` or `\x1b[K`. They're visual artifacts that make sense in a terminal but are noise in text processing.

**Solution:** Strip them. I used the `strip-ansi` npm package (well-tested, battle-hardened) to clean all output before returning it to Copilot.

```typescript
import stripAnsi from "strip-ansi";

export function cleanOutput(raw: string): string {
  return stripAnsi(raw);
}
```

Simple. Effective.

### Paging Prompts (`--More--`)

Some commands return output longer than one screen. The device pauses and prints `--More--` (or `-- More --` or ` --More-- ` or... you get the idea). You have to press space to continue.

If you don't handle this, your command hangs. Forever.

**Solution:** Detect the pager prompt with a regex, auto-send a space character, keep reading.

```typescript
private static readonly PAGER_PROMPT = /--\s*[Mm]ore\s*--/;

const onData = (data: Buffer) => {
  const chunk = data.toString("utf-8");
  
  if (this.promptDetector.isPagerPrompt(chunk)) {
    this.channel!.write(" ");  // Auto-page
    return;
  }
  
  buffer += chunk;
  // ... continue processing
};
```

Tested on Cisco devices with long `show running-config` output. Works like a charm.

### Command Echo Stripping

When you send a command to an SSH session, the device echoes it back. So if you send `show version`, the output starts with `show version` as the first line. That's not part of the *output* — that's just the echo.

**Solution:** Strip the first line if it matches the command you sent.

```typescript
let outputLines = lines;
if (outputLines[0].trim().includes(command.trim())) {
  outputLines = outputLines.slice(1);
}
```

Small detail. Big impact on output cleanliness.

### Error Detection

Sometimes commands fail. The device prints an error message. You need to know.

**Solution:** Pattern matching on common error phrases.

```typescript
export function detectError(output: string): { error: boolean; error_type?: string } {
  const errorPatterns = [
    { pattern: /invalid\s+(command|input)/i, type: "invalid_command" },
    { pattern: /syntax\s+error/i, type: "syntax_error" },
    { pattern: /permission\s+denied/i, type: "permission_denied" },
    { pattern: /not\s+authorized/i, type: "auth_error" },
    { pattern: /connection\s+(refused|timeout)/i, type: "connection_error" },
  ];

  for (const { pattern, type } of errorPatterns) {
    if (pattern.test(output)) {
      return { error: true, error_type: type };
    }
  }

  return { error: false };
}
```

Copilot gets structured error info. It can react intelligently ("That command doesn't exist. Let me try `?` to discover available commands.").

## The 5 MCP Tools

With the transport layer solid, I implemented the 5 MCP tools that Copilot uses:

### 1. `ssh_check_connectivity`

Pre-flight TCP check. Tests if a host is reachable on port 22 before attempting SSH.

**Use case:** "Is the VPN up? Is the device online?"

**Returns:**
```json
{
  "reachable": true,
  "duration_ms": 45
}
```

### 2. `ssh_connect`

Establish an SSH session. Supports password auth or SSH key auth.

**Returns:**
```json
{
  "session_id": "a1b2c3d4-...",
  "connected": true,
  "banner": "Welcome to Dell EMC Networking OS10\n...",
  "prompt": "DellEMC#"
}
```

**The prompt is the gold.** Copilot sees `DellEMC#` and immediately knows: "This is probably a Dell OS10 switch. Let me run `show version` to confirm."

### 3. `ssh_send`

Execute a command. Returns clean output, the next prompt, and error info.

**Returns:**
```json
{
  "output": "OS Version: 10.5.4.2\nSystem Type: S5248F-ON\n...",
  "prompt": "DellEMC#",
  "prompt_confidence": "high",
  "error": false,
  "duration_ms": 234,
  "partial": false
}
```

**`prompt_confidence`** tells Copilot how certain the system is that it correctly detected the prompt. `high` = learned regex matched. `medium` = generic fallback matched. `low` = silence timeout kicked in.

### 4. `ssh_disconnect`

Graceful teardown. Closes the channel, ends the SSH client.

**Returns:**
```json
{
  "success": true,
  "duration_total_ms": 123456
}
```

### 5. `ssh_sessions`

List all active SSH sessions. Useful for multi-device workflows.

**Returns:**
```json
{
  "sessions": [
    { "session_id": "abc...", "host": "10.1.1.50", "connected": true },
    { "session_id": "def...", "host": "10.1.1.51", "connected": true }
  ]
}
```

That's it. Five tools. Simple, composable, powerful.

## Testing: 61 Tests, 61 Passing

I'm a "tests or it didn't happen" kind of developer. If there's no test coverage, I don't trust the code. So I wrote tests. Lots of them.

Test suite breakdown:
- **Prompt detection:** 25 tests (covering Linux, Cisco, Dell, Arista, F5, edge cases)
- **SSH connection:** 12 tests (connect, disconnect, timeouts, key auth, password auth)
- **Command execution:** 15 tests (send, prompt detection, paging, error handling)
- **ANSI stripping:** 5 tests
- **Error detection:** 4 tests

I used `vitest` because it's fast. The full test suite runs in under 2 seconds.

**Result:** 61/61 tests passing. ✅

## Real-World Test: Connecting to clawbot

Tests are great. But the real test is: **does it work on an actual device?**

I have a Linux server in my lab called `clawbot`. It's a Raspberry Pi running Ubuntu Server. Perfect test target.

I fired up the MCP server, connected from GitHub Copilot CLI, and ran a discovery workflow:

**Me:** "Connect to clawbot and figure out what it is."

**Copilot:**
1. `ssh_check_connectivity({ host: "clawbot.local" })` → ✅ Reachable
2. `ssh_connect({ host: "clawbot.local", username: "eric", key_path: "~/.ssh/id_ed25519" })` → ✅ Connected. Prompt: `eric@clawbot:~$`
3. `ssh_send({ session_id: "...", command: "uname -a" })` → Linux 5.15.0-1055-raspi aarch64
4. `ssh_send({ session_id: "...", command: "cat /etc/os-release" })` → Ubuntu 22.04 LTS
5. `ssh_send({ session_id: "...", command: "uptime" })` → up 14 days

**Copilot:** "This is a Raspberry Pi running Ubuntu 22.04 LTS (ARM64). Uptime is 14 days. What would you like to check?"

**Me:** (internally screaming with joy)

It worked. First try. No bugs. Clean output. Perfect prompt detection.

This is the moment. This is why you build things.

## What's Next: Phase 3 and Beyond

Phase 1 and Phase 2 are done. The transport layer is solid. But there's more work ahead:

### Phase 3: Device Transport Tuning

The prompt detection works generically, but some devices need special handling:

- **Cisco enable mode** — Detect when you need to send `enable` + enable password to reach privileged mode
- **Cisco privilege escalation prompts** — Handle the `Password:` prompt that appears after `enable`
- **Dell OS10 mode nuances** — Fine-tune for Dell-specific prompt patterns
- **Arista EOS quirks** — Test on Arista switches, adjust as needed
- **F5 tmsh** — The F5 CLI is... unique. Needs testing.

This is tuning, not rewriting. The core is done.

### Phase 4: Credential Management

Right now, you pass `username` and `password` (or `key_path`) to `ssh_connect`. That works. But it's not secure for long-term use.

Phase 4 is building the `CredentialProvider` abstraction I designed in Part 1:
- Windows Credential Manager (DPAPI)
- Linux libsecret (GNOME Keyring)
- macOS Keychain
- Interactive prompt fallback
- TTL cache, rate limiting, audit logging

Security done right.

### Phase 5: Documentation and Publishing

Write the killer docs. Device setup guides. Security best practices. Example workflows.

Publish to npm. Make it easy to install: `npx nrecon-mcp`.

## Why This Matters

Here's the thing: **this tool solves a real problem I face every day.**

I work with network equipment. Cisco switches. Dell switches. Arista switches. F5 load balancers. Lab gear. Production gear. Inherited infrastructure with zero documentation.

Every time I SSH into a device, I'm navigating a CLI with muscle memory and trial-and-error. "Does this device use `show running-config` or `show configuration`? Does it have BGP? What's the syntax for this vendor's QoS commands?"

**nrecon-mcp changes that.**

Now I can point Copilot at an unknown device and say: "Figure out what this is. Tell me what's configured. Help me understand it."

And Copilot does. Because it has the right transport tools. Because prompt detection works. Because the output is clean and structured.

This is the power of building tools for LLMs. You're not replacing human expertise. You're *augmenting* it. Copilot doesn't know network engineering — but it's excellent at exploring, parsing, and reasoning about text. Give it the right transport layer, and it becomes a device whisperer.

## The Journey So Far

**February 8:** Designed the architecture. Wrote Part 1 of this blog series. No code yet.

**February 9-13:** Built the entire transport layer. Scaffolded the project, implemented SSH connection handling, wrote the hybrid prompt detection algorithm, added ANSI stripping and error detection, created the 5 MCP tools, wrote 61 tests, tested on a real device.

**February 14 (today):** Pushed to GitHub. Repo is public at [`ebmarquez/nrecon-mcp`](https://github.com/ebmarquez/nrecon-mcp). Tests pass. Code runs. It works.

**Total time invested:** ~40 hours.

Not bad for a week.

## Stay Tuned for Part 3

Next post will probably be: **"nrecon-mcp: Device Discovery in Action"** — where I walk through real-world discovery workflows on Cisco, Dell, and Linux devices. Show, don't tell.

In the meantime, check out the repo. Clone it. Run the tests. Try it on your own lab gear. File issues. Submit PRs. Let's build this together.

If you missed Part 1, go read [Building nrecon-mcp: From Idea to Design in One Night]({% post_url 2026-02-09-building-an-ssh-mcp-server-from-idea-to-design %}) — it covers the origin story and the architecture decisions.

---

**Project Status:**
- ✅ Phase 1: Repository setup (complete)
- ✅ Phase 2: Core transport layer (complete)
- 🚧 Phase 3: Device tuning (next)
- 📋 Phase 4: Credential management (planned)
- 📋 Phase 5: Polish and publish (planned)

**Tech Stack:**
- TypeScript 5.9 + Node.js 20
- `ssh2` for SSH transport
- `@modelcontextprotocol/sdk` for MCP integration
- `vitest` for testing
- `zod` for schema validation

**Test Coverage:** 61/61 tests passing ✅

**GitHub:** [`ebmarquez/nrecon-mcp`](https://github.com/ebmarquez/nrecon-mcp)

**Designed and built with:** GitHub Copilot CLI running Claude Opus 4.6 — the entire design, implementation, and testing was a collaborative conversation with my GitHub Engineer agent.

Let's build something cool. 🚀
