---
layout: post
title: "I Built an MCP Server for SSH — Here's Why"
date: 2026-04-14 00:00:00 -0700
categories: [networking, ai]
tags: [ssh, mcp, ai, automation, networking, security, open-source]
author: ebmarquez
description: "Every network lab story hits the same wall: AI can SSH into a switch, but credential management falls apart fast. So I built ai-ssh-toolkit — an MCP server that gives AI agents proper SSH access with pluggable credential backends."
image:
  path: https://images.unsplash.com/photo-1562408590-e32931084e23?w=1200&q=80
  alt: "Network switch rack with structured cabling — the infrastructure AI needs to reach"
---

## The Wall Every Network Lab Eventually Hits

Every network automation story has a moment where the demo falls apart.

You're deep in a session with your AI assistant of choice — GitHub Copilot, Claude, doesn't matter — and it's going great. You ask it to SSH into a switch, pull the interface status, check some BGP neighbors. Clean. Impressive, even. You're showing your colleagues this is the future of network ops.

Then someone asks: *"Can it do that across all ten switches?"*

And that's when you hit the wall.

Not because the AI can't handle it. But because suddenly you need real credentials, stored properly, retrieved securely — and you're back to writing one-off scripts that re-invent the same wheel every single time.

---

I got into this problem for a pretty mundane reason: I was doing credential standardization across a fabric of NX-OS switches. Not glamorous. Not the kind of thing you write blog posts about. Just necessary infrastructure work — the kind that has to happen before anything interesting can happen.

The pattern that kept emerging was identical every single time. Connect to a switch. Authenticate. Run some commands. Parse the output. Do something useful with it.

I wrote Node.js scripts for each task. Parameterized, sure. Functional, yes. But *messy* — because every new agent session had to solve the same credential problem from scratch. Where do you store the passwords? How does the agent retrieve them without seeing plaintext credentials in the conversation? What happens when you rotate a credential?

After about the fourth script, I had that "this is dumb" moment that usually precedes either a coffee break or a proper solution. I picked the latter.

---

What I actually needed wasn't another SSH script. It was **infrastructure that should exist once**.

A proper server that gives any AI agent SSH capability, with pluggable credential backends — so the agent can say "connect to this switch" without ever touching a raw password. The credentials stay in your secret store. The agent gets capability. Everyone wins.

The mechanism I kept coming back to was MCP — Model Context Protocol. If you haven't bumped into it yet: MCP is the emerging standard for letting AI assistants call external tools. It's how GitHub Copilot CLI, Claude Desktop, and other agents connect to the outside world in a structured, repeatable way.

The realization was simple: if you expose SSH as an MCP tool, any AI that speaks MCP can now SSH into your infrastructure. **Write it once, use it everywhere.** NX-OS, SONiC, Dell OS10 — doesn't matter what's in the rack, as long as it speaks SSH.

That's what became the **ai-ssh-toolkit**: [github.com/ebmarquez/ai-ssh-toolkit](https://github.com/ebmarquez/ai-ssh-toolkit).

The rest of this post is the how and why of building it — credential backends, tool design, and what it actually looks like when an AI agent starts navigating your network fabric without you babysitting every command.

Buckle up.

## What's Actually In the Box

Okay, so what does `ai-ssh-toolkit` actually give your AI agent to work with?

Four tools. That's it. No sprawling API surface, no 47 endpoints to memorize. Four surgical tools that, together, let an AI assistant SSH into network gear without ever touching a password it shouldn't see.

Let's break them down.

---

### The Four MCP Tools

**`ssh_execute`** — The workhorse. Connects to a host, authenticates, runs a command, returns the output. The interesting bit is `platform_hint`: you can tell it you're talking to `nxos`, `sonic`, `linux`, or just let it `auto`-detect. This matters because NX-OS and SONiC have different prompt patterns — the tool handles that so your AI doesn't have to guess whether it successfully authenticated or just got dropped into a weird menu screen.

**`credential_get`** — Retrieves *metadata* about a credential. Not the credential itself. This is the key design decision baked right into the API surface: the AI can learn *about* a secret (which vault it's in, what username it maps to) without ever seeing the actual password. That's not an accident — it's the whole point.

**`credential_list_backends`** — Tells the AI what credential systems are available in this environment. Bitwarden? Azure Key Vault? Environment variables? The AI discovers this at runtime instead of assuming. No hardcoded "check Bitwarden first" logic scattered through your prompts.

**`ssh_check_host`** — TCP reachability check with latency before attempting a full connection. Because nothing wastes time like watching an SSH handshake timeout for 30 seconds when the host is simply unreachable. This is the "is the box even up?" sanity check that humans do reflexively but AI agents skip.

---

### Credentials: The Design Decision That Actually Matters

The credential backend architecture is where this project earns its keep.

Three backends ship out of the box:

- **Bitwarden CLI** — Reference secrets by item name in your vault. If your team already lives in Bitwarden, this is zero-friction.
- **Azure Key Vault** — Reference by `vault/secret-name`, authenticates via the `az` CLI. No new credentials to manage; it rides your existing Azure auth.
- **Environment variables** — The `MY_SWITCH_USERNAME` + `MY_SWITCH_PASSWORD` pattern. Old school, works everywhere, great for CI/CD pipelines where you don't want to involve a secrets manager at all.

The pluggable architecture means you can bolt on a new backend — HashiCorp Vault, 1Password, whatever your organization runs — without changing the tool API. The four MCP tools stay exactly the same; you're just adding a new credential resolver under the hood.

---

### What This Looks Like in Practice

You're in GitHub Copilot. You type: *"Check BGP status on all three spine switches."*

Here's what happens without you writing a single script:

1. Copilot calls `credential_list_backends` — discovers Bitwarden is available
2. Calls `credential_get` for each switch — gets usernames, vault references, no passwords exposed
3. Calls `ssh_execute` three times with `platform_hint: nxos` and `show bgp summary`
4. Returns structured output from all three switches in one conversation turn

No password in the chat transcript. No bash script you'll forget to delete. No SSH key you had to manually distribute. Just: *ask question, get answer.*

---

### Getting It Running (One Line, Seriously)

Both GitHub Copilot CLI and Claude Desktop use the same install path via `npx`:

```json
{
  "mcpServers": {
    "ai-ssh-toolkit": {
      "command": "npx",
      "args": ["-y", "ai-ssh-toolkit"]
    }
  }
}
```

Drop that in your MCP config and you're done. No global install, no version pinning headaches.

One more thing worth calling out: **Windows is a first-class citizen here**. ConPTY support means this works on Windows natively — not just in WSL, not "technically works if you squint." Network engineers live on Windows too, and this was built with that in mind from day one.

## The Part Where We Talk About Security (No, Really, Stick With Me)

Here's the thing about giving an AI agent SSH access to your network infrastructure: **it's either thoughtful or terrifying**. There's no middle ground.

Most early MCP implementations treat credentials like a sticky note — just pass the password as a string in the tool call, maybe write it to a temp file, hope for the best. This is the software equivalent of taping your house key to the front door with a label that says "house key."

Passwords passed as plain strings end up in conversation history. They show up in logs. They linger in memory until garbage collection gets around to caring. For a weekend homelab project, sure, maybe fine. For network infrastructure where your switches actually matter? That's a different conversation.

### How ai-ssh-toolkit Handles Credentials

The design starts from a simple premise: **the agent should never see the actual password.** Full stop.

Credentials in transit are stored as Node.js `Buffer` objects rather than strings. After use, they're zero-filled — actively overwritten — rather than left to float around in memory waiting for GC. No temp files are created for credential staging. CLI secrets (for tools like Bitwarden or Azure CLI) are piped via stdin rather than passed as command-line arguments, because anything on the command line shows up in your process list for anyone with `ps aux` to admire.

PTY output gets scrubbed for password echoes. And `StrictHostKeyChecking=no` — that beloved shortcut that makes SSH stop complaining — **is never used**. Host key verification stays on. Every decision has a reason.

The `credential_get` tool is worth calling out specifically: **it never returns actual passwords.** It returns metadata. The agent can confirm a credential exists and is accessible without the value ever appearing in the conversation. The actual secret stays inside whatever backend you're using — Bitwarden, Azure Key Vault, your own vault — and the audit trail lives there too.

That last point matters more than it sounds. When someone asks "did the AI agent touch that switch?", your answer shouldn't be "uh, let me grep the conversation logs." It should be "here's the Bitwarden vault access log, timestamped." Proper audit trails belong in proper systems.

### The Black Hat Review

Before implementation, the design went through a deliberate adversarial review — essentially asking "okay, how would I break this?" The result is `SECURITY.md`, which documents not just *what* the tool does but *why* each decision was made. External CLI paths (like `bw` for Bitwarden) get resolved to absolute paths at startup so there's no PATH hijacking shenanigans.

This isn't security theater. It's a genuine threat model for a real scenario: **an AI agent with SSH access to production network equipment.**

The credential backend abstraction is the key insight. The agent calls a tool. The tool handles authentication. The agent gets a session — and never had to know the password to get there. Your credential system stays the system of record. The AI conversation stays out of the loop on secrets.

Your AI agent is about to have access to your switches. That's real power. It deserves real thought.

## Putting It All Together (And What's Still Being Built)

If you've been following the SONiC series, you've seen what AI-assisted network engineering looks like when it's actually working — an LLM querying switch state, catching config drift, flagging anomalies before they become incidents. It's legitimately cool.

But there's been a recurring friction point: *how does the AI talk to the hardware?* SSH is the answer 99% of the time, and SSH comes with a whole pile of credential management complexity that nobody wants to deal with inside a language model prompt.

**`ai-ssh-toolkit` is the missing infrastructure layer.**

It's an MCP server that handles the credential plumbing, host verification, and command execution so your AI tools don't have to. The SONiC posts showed the *what* — this is the *how*.

---

### Try It Right Now

No install required:

```bash
npx -y ai-ssh-toolkit
```

If you want it wired into your AI tooling permanently, drop this into your MCP config (works with Copilot CLI or Claude Desktop):

```json
{
  "mcpServers": {
    "ai-ssh-toolkit": {
      "command": "npx",
      "args": ["-y", "ai-ssh-toolkit"]
    }
  }
}
```

Once it's running, start with `credential_list_backends` to see what credential sources are available in your environment. Then `ssh_check_host` before you ever run `ssh_execute` — it's a good habit that'll save you from mystery connection failures.

---

### What's There, What's Not

The repo is scaffolded, the tests pass, CI is green. But a few modules are still stubs — they exist, they have interfaces, they just don't do anything yet. That's intentional: the patterns are worth sharing even when the implementation isn't finished.

Contributions are welcome. If you need a backend or feature that doesn't exist yet, open an issue or send a PR. The whole point is to make this useful for real-world network automation, not just the author's lab.

→ **[github.com/ebmarquez/ai-ssh-toolkit](https://github.com/ebmarquez/ai-ssh-toolkit)**

---

### Honest Closing

This started as a lab tool for wrangling ten switches without wanting to die managing credentials manually. The patterns turned out to be useful enough to share.

If you're doing AI-assisted network automation and you keep hitting the same SSH credential wall — this might save you an afternoon. Maybe more. That's worth something.
