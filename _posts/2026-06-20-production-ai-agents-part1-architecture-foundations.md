---
layout: post
title: "Building Production AI Agents, Part 1: The Demo Is the Easy Part"
date: 2026-06-20 09:00:00 -0700
categories: [AI, Architecture]
tags: [ai, agents, architecture, llm, production, mcp, system-design]
author: ebmarquez
description: "Every AI agent demo works. Then you ship it and it falls apart. This is the first in a 5-part series on the unglamorous 80% nobody puts in the demo — starting with architecture: deciding what you don't let the model do."
---

The demo always works.

You wire up an LLM, give it a couple of tools, ask it to do something impressive, and it does. The room nods. Somebody says "ship it." You feel like a wizard.

Then you ship it, real users show up, and your wizard turns out to be a guy with a bedsheet and a flashlight. The agent loops. It hallucinates a file path. It runs the same command four times. It confidently deletes the wrong thing. The thing that crushed it on stage now needs a babysitter.

I've been living in this gap for the better part of a year — building a personal AI staff that actually runs my life, an open-source [MCP server](https://github.com/ebmarquez/nrecon-mcp) that lets an LLM autonomously explore network devices, and a local-first agent runtime with a dozen specialized agents. None of that was hard to *demo*. All of it was hard to make *survive*.

So this is a series about the survival part. Five posts, one arc: prototype to production. The demo is the easy 20%. This series is the other 80% — the memory, the safety, the orchestration, the observability — the stuff nobody puts in the launch video because it isn't sexy. It's just the difference between a toy and a tool.

We start where everything starts: architecture.

---

## The Only Architecture Question That Matters

When people say "AI agent architecture," they usually reach for a box-and-arrows diagram with an LLM in the middle and some tools hanging off it. Fine. But that diagram hides the only decision that actually determines whether your agent works in production:

**How thin should the deterministic layer be, and where does the intelligence live?**

That's it. That's the whole game. Everything downstream — reliability, security, debuggability — falls out of how you answer it.

Here's the tension. LLMs are *unreasonably* good at some things: reading messy text, inferring intent, reasoning about unfamiliar situations, adapting on the fly. And they're *catastrophically* bad at others: doing the exact same thing twice, respecting hard constraints, not making things up when they're unsure, handling a `--More--` paging prompt without losing their mind.

Production architecture is the art of putting each responsibility on the side of the line where it belongs. Code does the things that must not vary. The model does the things that require judgment. Get that boundary wrong and no amount of prompt engineering saves you.

---

## A Real Bake-Off: Three Architectures Walk Into a Switch

Let me make this concrete, because I made this exact decision on a real project and got to watch two of the three options fail on paper before I wrote a line of code.

The project: `nrecon-mcp`. The goal: let GitHub Copilot SSH into a network device it's never seen — a mystery Dell or Cisco or Arista switch with no docs — poke around, figure out what it is, and help me make sense of it. A "device whisperer."

There were three ways to build it.

**Option A — The Smart Server.** The server does everything. It connects, runs discovery commands, parses every vendor's CLI output into structured data, tracks device state, and hands the model clean JSON. The model just narrates.

The problem: I'd be writing custom parsers for `show version` on Dell OS10, and Cisco IOS, and Arista EOS, and F5 tmsh, forever. I'd be reinventing the one thing LLMs are *already great at* — reading arbitrary text and making sense of it. Every new device firmware would be a maintenance bill. **Rejected: too much reinvention.**

**Option B — The Thin Server.** The server is a dumb pipe. It opens an SSH socket, shovels raw bytes, and the model handles *everything else* — prompt detection, paging, ANSI escape codes, parsing, reasoning.

The problem: SSH is a swamp. ANSI color codes, `--More--` pagers that hang waiting for a spacebar, unpredictable prompts, login banners, timeouts. Throw all that raw sewage at the model and it spends half its tokens fighting the transport instead of thinking about the device. It's like asking a brilliant detective to solve a murder while you scream radio static in their ear. **Rejected: too unreliable.**

**Option C — The Hybrid.** The server owns the *hard transport problems*: connection management, dynamic prompt detection, auto-handling the pager, stripping ANSI codes, timeouts, error-pattern recognition. The model owns the *intelligence*: fingerprinting the device, deciding what to ask next, navigating the CLI, interpreting output, building a mental model.

The server hands the model clean, boring, reliable text. The model does the part only a brain can do.

**This is the one.** Not because it's clever — because it draws the line in exactly the right place. The deterministic layer absorbs the chaos that would otherwise poison the model's reasoning. The model gets to be smart about the thing that actually requires smarts.

That's the pattern. I'm going to keep hammering it because it generalizes to *every* agent you'll ever build:

> **A deterministic shell around a probabilistic core.**

Code is the exoskeleton. The model is the soft, clever, occasionally-hallucinating animal inside. The exoskeleton's whole job is to make sure that when the animal does something dumb, the blast radius is contained.

---

## What Goes in the Shell

If "deterministic shell, probabilistic core" is the principle, here's the practical checklist. These belong in code — *every time*, no exceptions, no "the model will probably handle it":

- **Transport and I/O.** Connections, retries, timeouts, byte-wrangling. The model should never see a raw socket.
- **Authentication and credentials.** Never, ever a model's job. (Whole post coming on this — Part 3.)
- **Validation.** Input sanitization, schema checks, allow-lists. Validate *before* the model acts and *after* it produces a tool call.
- **Rate limits and quotas.** The model has no instinct for "I've called this API 600 times in a loop." Code does.
- **Hard constraints.** The things that must be true no matter what the model "decides" — business rules, safety limits, blast-radius caps, and the idempotency guards that keep a mutating action from firing twice.

And here's what goes in the core — the things you'd be foolish to hard-code:

- Interpreting messy, unstructured input.
- Deciding *what to do next* in an open-ended situation.
- Adapting to something you didn't anticipate.
- Anything where the right answer depends on context you can't enumerate in advance.

The test is simple. For any responsibility, ask: **"If this varies run-to-run, is that a feature or a bug?"** If it's a bug, it goes in the shell. If the variation is the *point*, it goes in the core.

---

## The Single-File Agent: One Job, Done Well

There's a second architectural decision that pays off enormously in production, and it's about *granularity*. How big should an "agent" be?

In my local agent runtime, every agent follows the same shape — a single-file pattern where each agent extends a common base and does exactly one category of thing. A shell agent runs commands and touches files. A web agent fetches and searches. A memory agent remembers and recalls. An email agent reads the inbox. Each one exposes a tight set of actions and routes between them:

```typescript
// The shape every agent shares: a narrow action surface,
// one clear responsibility, predictable routing.
class WebAgent extends BasicAgent {
  // actions: "fetch" | "search"
  async run({ action, url, query }) {
    switch (action) {
      case "fetch":  return this.fetch(url);    // strips HTML, blocks private IPs
      case "search": return this.search(query); // queries, parses results
    }
  }
}
```

This looks almost too simple. That's the point. The discipline of "one agent, one responsibility, a handful of actions" gives you things that matter enormously when you're not on stage anymore:

- **You can reason about it.** A 4-action agent has a knowable surface. You can hold its entire behavior in your head.
- **You can test it.** Narrow contracts are testable contracts.
- **You can contain failure.** When the web agent breaks, it breaks *web things* — it can't accidentally wipe a file, because touching files isn't in its vocabulary.
- **You can compose it.** Small, sharp agents snap together. Big, do-everything agents fight each other.

The anti-pattern is the God Agent — one giant blob with forty tools and a 3,000-word system prompt trying to be everything. It demos *great*. It's a nightmare in production, because its surface is unknowable, its failures are unbounded, and debugging it is like trying to find a bug in a city.

(We'll build a whole *team* of these small agents in [Part 4](/posts/production-ai-agents-part4-multi-agent-orchestration/). The reason that works is the discipline we're setting up right now.)

---

## The State Illusion

One more foundational thing, and it's the one that bites people first, so it's worth naming up front.

Your agent is stateless. The model has no memory between calls. None. Every API call is a goldfish meeting you for the first time. The "conversation" you think it's having is a polite fiction you reconstruct by stuffing the entire history back into the prompt on every single turn.

This is fine for a demo — the demo is one session. It is *not* fine for anything real, where a user expects the agent to remember that they asked a related question yesterday, that they already ruled out the obvious fix, that they have preferences.

Architecturally, you have to decide *up front* where state lives, because retrofitting it later is genuinely painful — I know, because I built my memory layer too late and there's a continuity gap I'll never recover. State is not a feature you bolt on. It's a load-bearing wall. You frame the house around it.

That's a big enough topic that it gets its own post — the very next one. For now, just internalize the architectural consequence: **assume amnesia, and design the system that papers over it deliberately.**

---

## So What

If you take one thing from this post, make it this:

**Architecture is the practice of deciding what you don't let the model do.**

The demo is impressive because in a demo, you let the model do everything and you get lucky. Production is reliable because you *systematically take things away from the model* and hand them to deterministic code — transport, auth, validation, limits, guarantees — until what's left is exactly the slice that genuinely needs intelligence, wrapped in a shell that contains it when it's wrong.

A deterministic shell around a probabilistic core. Small agents with narrow surfaces. State treated as a load-bearing wall, not a bolt-on. That's the foundation. Everything else in this series — memory, tools, orchestration, observability — is built on top of it.

Get the boundary right and the model gets to be brilliant exactly where brilliance helps, and stays on a short leash exactly where it would otherwise hurt you.

Next up: the first thing that breaks when you go from demo to real life. Your agent has amnesia, and pretending otherwise is the most expensive mistake in the stack.

---

*This is Part 1 of a 5-part series on building production AI agents.*

1. **Architecture Foundations** *(you are here)*
2. [Memory & Context Management](/posts/production-ai-agents-part2-memory-context/)
3. [Tool Design & Safety](/posts/production-ai-agents-part3-tool-design-safety/)
4. [Multi-Agent Orchestration](/posts/production-ai-agents-part4-multi-agent-orchestration/)
5. [Observability & Ops](/posts/production-ai-agents-part5-observability-ops/)

*Building something similar, or think I've drawn the line in the wrong place? Find me on [GitHub](https://github.com/ebmarquez) or drop a comment below.*
