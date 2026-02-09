---
layout: post
title: "Building nrecon-mcp: From Idea to Design in One Night"
date: 2026-02-09 00:00:00 -0800
categories: [Projects, MCP]
tags: [ssh, mcp, networking, copilot, open-source, typescript, security]
author: eric
description: "The origin story of nrecon-mcp — an open-source MCP server that lets GitHub Copilot SSH into network devices and explore them autonomously — designed entirely in a single Copilot conversation."
---

## The Problem That Started It All

Picture this: You're staring at a Dell switch you've never touched before. No documentation. No idea what version of the OS it's running. You don't even know if it has BGP configured or what VLANs are active. You SSH in, see a prompt, and... now what?

This is my life as a network engineer working with Cisco, Dell, Arista switches, and F5 devices. Every device has its own CLI quirks, its own command syntax, its own way of paginating output. And when you're dealing with lab equipment or inherited infrastructure, good luck finding docs.

So tonight (February 8th, 2026), I decided to fix it. Not with more documentation. Not with another "cheat sheet." I wanted something smarter: **What if GitHub Copilot could SSH into these devices, explore them autonomously, learn their capabilities, and help me — even on devices with zero documentation?**

I spent the next few hours designing exactly that — a complete design doc for an open-source MCP (Model Context Protocol) server. No code yet, just a solid blueprint. This is how it started.

## The Initial Pitch: SSH Command Runner

I started with a simple idea: build an MCP server that lets Copilot run SSH commands on network devices. Connect, execute commands, get output, disconnect. Clean and straightforward.

Copilot and I kicked off the research phase. Language choices, SSH libraries, credential management. We evaluated TypeScript (with `ssh2`), Python (with `paramiko`), and Go (with `x/crypto/ssh`). TypeScript won pretty quickly — the official MCP SDK from Anthropic is in TypeScript, the docs are solid, and `ssh2` is battle-tested.

We sketched out tool designs:
- `ssh.check_connectivity` — Pre-flight TCP check to validate VPN is up
- `ssh.connect` — Establish a session
- `ssh.send` — Execute a command, get output
- `ssh.disconnect` — Clean teardown

Looked good. We even started talking about repository structure, CI/CD pipelines, issue templates. Classic open-source project setup stuff.

But then I realized something.

## The Pivot: This Isn't About Running Commands

Here's the thing: **I don't need help running SSH commands.** I can already do that in a terminal. What I need is help *understanding unknown devices*.

When I connect to a mystery switch, I don't know:
- What OS is it running?
- What commands are available?
- Is BGP configured? What peers?
- What's the QoS policy?
- How do I even navigate this CLI?

**That's the real problem.** I don't need a remote execution tool. I need a discovery agent. Something that connects to a device, pokes around, figures out what it is, learns what it can do, and then helps me make sense of it.

So I asked Copilot to redesign the whole thing with that in mind.

And that's when things got interesting.

## Three Architectures Walk Into a Bar

We evaluated three possible architectures for this "autonomous discovery agent" concept:

### Option A: Smart MCP Server

The MCP server does everything. It connects, discovers device capabilities, parses output, maintains device state, and returns structured data to Copilot.

**Problem:** We'd be duplicating what LLMs are already amazing at. Why write custom parsers for every vendor's CLI output when GPT/Claude can already reason about text?

**Verdict:** Rejected. Too much reinvention.

### Option B: Thin MCP Server + Smart Copilot

The MCP server is just a dumb SSH transport layer. It sends commands, returns raw text. Copilot handles *everything* else: prompt detection, paging, parsing, reasoning.

**Problem:** SSH is *messy*. You've got ANSI escape codes, paging prompts (`--More--`), unpredictable device prompts, timeouts, banner text. If we throw all that chaos at Copilot, it'll spend half its time fighting transport issues instead of actually reasoning about the device.

**Verdict:** Rejected. Too unreliable.

### Option C: Hybrid (The Goldilocks Zone)

The MCP server handles the *hard transport problems*:
- SSH connection management
- Dynamic prompt detection
- Paging auto-handling (detect `--More--`, auto-send space)
- ANSI code stripping
- Timeout management
- Error pattern recognition

Copilot handles the *intelligence*:
- Device fingerprinting (parse `show version`)
- Command discovery (send `?`, reason about output)
- CLI navigation (understand mode changes)
- Output interpretation (parse tables, configs, status)
- Knowledge building (accumulate session context)
- Recommendations (advise the user based on what it learned)

**Verdict:** ✅ This is it. The MCP server is a reliable transport layer. Copilot is the brain.

We went with Option C.

## The Security Debate: Credentials Are Everything

If there's one thing I learned tonight, it's this: **Security is the #1 priority. If credentials aren't secure, nobody will use this tool.**

We spent a solid chunk of time architecting the credential system. And let me tell you, it was a journey.

### The Keytar Incident

Early on, I asked about using `keytar` — a popular npm package for OS keyring access. Copilot immediately flagged it: **"keytar is DEPRECATED and ARCHIVED. Do not use it."**

Well, that's not great. Time to redesign.

### The Abstraction Layer

We designed a `CredentialProvider` interface that supports multiple backends:

1. **OS Credential Store (Primary)** — Windows Credential Manager (DPAPI), Linux libsecret (GNOME Keyring), macOS Keychain. Encrypted at rest, tied to user profiles. The gold standard.

2. **Interactive Prompt (Fallback)** — No stored credential? Prompt the user at connect time. Nothing persisted unless they explicitly store it.

3. **Environment Variables (CI/CD Only)** — For ephemeral CI runners. Never for interactive use. Too risky.

4. **Encrypted File (Docker/Headless)** — Use `sops` or `age` for encryption. No custom crypto. For containerized deployments.

### The Non-Negotiables

We documented a list of security controls that are **absolutely non-negotiable**:

- **Never log passwords.** Ever. CI checks will grep for `password`, `secret`, `credential` in logs.
- **30-minute TTL** on cached credentials. Cleared immediately on disconnect.
- **Rate limiting:** 3 failed auth attempts → 60-second cooldown per host. (Nobody wants to lock out a production device.)
- **Audit logging:** Log `host + user + provider + result + timestamp`. Never the password.
- **Host key policy:** Strict by default. Trust but verify.
- **No plaintext on disk.** Passwords never written to files, configs, or logs.

Oh, and Cisco enable passwords? Those are first-class citizens. Network devices often need a secondary "enable password" for privileged mode, so we built that into the credential model:

```typescript
{
  username: "admin",
  password: "login-password",
  enablePassword: "enable-secret"  // optional, for network devices
}
```

This was the part of the design where I really felt like we were building something serious. Credential management is *hard*. Get it wrong, and you've built a security nightmare. Get it right, and people might actually trust this thing.

## The "Aha Moment": Copilot as a Device Whisperer

The design really clicked when we mapped out a discovery workflow. Imagine this:

**User:** "Connect to 10.1.1.50 — I don't know what this device is."

**Copilot (thinking):**
1. `ssh.check_connectivity({ host: "10.1.1.50" })` → Reachable ✅
2. `ssh.connect({ host: "10.1.1.50", credential_id: "lab-admin" })` → Session established. Prompt: `DellEMC#`
   - *Copilot sees "DellEMC#" → probably Dell OS10*
3. `ssh.send({ session_id: "abc", command: "show version" })` → Parses output: Dell S5248F, OS10 10.5.4.2
4. `ssh.send({ session_id: "abc", command: "?" })` → Learns available top-level commands
5. `ssh.send({ session_id: "abc", command: "show running-configuration" })` → Discovers: BGP configured, 3 peers, VLANs 100-200

**Copilot (responds):**  
"This is a Dell S5248F running OS10 10.5.4.2. It has BGP configured with 3 peers (10.0.0.1, 10.0.0.2, 10.0.0.3). VLANs 100-200 are active. What would you like to explore?"

**User:** "What QoS policies are applied?"

**Copilot (thinking):**
6. `ssh.send({ session_id: "abc", command: "show qos ?" })` → Discovers QoS sub-commands
7. `ssh.send({ session_id: "abc", command: "show qos interface summary" })` → Gets policy mappings

**Copilot (responds):**  
"QoS policy 'VOICE-PRIORITY' is applied to interfaces eth1/1/1-24..."

**This is the vision.** Copilot doesn't just run commands. It *learns* the device. It builds a mental model of what's there, what's configured, what's possible. And then it helps you navigate it.

That's when I realized: we're not building an SSH command runner. We're building a device whisperer.

## What's Next: From Design to Reality

So where are we now? **Day zero.** No code written. No repo created. Just a really solid design doc sitting in my Obsidian vault.

But here's what needs to happen next:

### Phase 1: Repository Setup
- Pick a project name ~~(candidates: `terminus-mcp`, `conduit-mcp`, `netssh-mcp`, `ssh-mcp-server`, `shellbridge-mcp`)~~ → **`nrecon-mcp`** ✅
- Create the GitHub repo under [`ebmarquez/nrecon-mcp`](https://github.com/ebmarquez/nrecon-mcp)
- Set up CI/CD, issue templates, branch protection
- Write a killer README

### Phase 2: Core Transport Layer
- Scaffold the TypeScript project
- Integrate MCP SDK and `ssh2`
- Build the core tools: `check_connectivity`, `connect`, `send`, `disconnect`
- Implement dynamic prompt detection and paging auto-handling
- Strip ANSI codes, detect error patterns, return clean output

### Phase 3: Device Transport Tuning
- Cisco prompt patterns (user mode, privileged mode, config mode)
- Cisco enable mode support
- Dell OS10, Arista EOS, F5 tmsh quirks
- SSH banner/MOTD separation from command output

### Phase 4: Credential Management
- Implement the `CredentialProvider` abstraction
- Windows DPAPI provider
- Linux libsecret provider
- macOS Keychain provider
- Interactive prompt fallback
- TTL cache, rate limiting, audit logging

### Phase 5: Polish
- Comprehensive docs
- Security guide
- Device-specific setup guides
- Docker deployment option
- Publish to npm

Estimated effort? **40+ hours.** But honestly, this is the fun kind of engineering — building something that solves a real problem I face every day.

## Why I'm Sharing This Now

This is a "day one" blog post. The project doesn't exist yet. There's no code to fork, no npm package to install, no GitHub repo to star.

So why write this now?

Because **this is how projects actually start.** Not with a polished launch. Not with perfect code. But with an idea, a conversation, a design session, and a lot of "what if" thinking.

And because I want to build this in the open. I want to document the journey from idea → design → MVP → production. I want to invite the community to follow along, contribute, challenge assumptions, and help shape what this becomes.

If you're a network engineer who's tired of Cisco vs. Dell vs. Arista CLI whiplash, this project is for you.

If you're an MCP enthusiast who wants to see what GitHub Copilot can do when given the right tools, this project is for you.

If you're a security-conscious developer who thinks "credential management done right" is a hill worth dying on, this project is *definitely* for you.

## Stay Tuned

I'll be documenting the build process here on the blog. Next post will probably be: **"nrecon-mcp: Building the Transport Layer"** — where we actually write some code and see if this design holds up in the real world.

In the meantime, if you have thoughts, ideas, or strong opinions about SSH, MCP servers, or network device automation, hit me up. The project will live at [`ebmarquez/nrecon-mcp`](https://github.com/ebmarquez/nrecon-mcp) on GitHub.

Let's build something cool.

---

**Update (Feb 9, 2026):** The project has a name: **`nrecon-mcp`** — Network Reconnaissance via autonomous SSH. Think `nmap` vibes, but for device CLI discovery. The design doc is still evolving. I'm iterating on the tool interface, refining security controls, and debating whether to support SSH keys in addition to passwords. The full design doc will be published in the repo at [`ebmarquez/nrecon-mcp`](https://github.com/ebmarquez/nrecon-mcp) once it's created.

**Tech Stack (Locked In):**
- Language: TypeScript
- Runtime: Node.js 20+
- SSH Library: `ssh2`
- MCP SDK: `@modelcontextprotocol/sdk`
- Credentials: OS-native (DPAPI/libsecret/Keychain)
- License: MIT

**Designed With:** GitHub Copilot CLI running Claude Opus 4.6 — the entire design session was a single conversation with my GitHub Engineer agent.

**Architecture Decision:** Option C — Hybrid (thin MCP server handles SSH transport, Copilot LLM handles intelligence/discovery)

**Security Posture:** Non-negotiable. If it's not secure, it doesn't ship.

See you in the next post. 🚀
