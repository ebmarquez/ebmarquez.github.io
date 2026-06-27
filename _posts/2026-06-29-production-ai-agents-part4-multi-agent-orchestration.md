---
layout: post
title: "Building Production AI Agents, Part 4: From Soloist to Symphony"
date: 2026-06-29 09:00:00 -0700
categories: [AI, Architecture]
tags: [ai, agents, multi-agent, orchestration, llm, production, system-design]
author: ebmarquez
description: "One agent can only do so much. Part 4 of the production AI agents series: when to reach for a team, the orchestration patterns that actually work, handoff protocols, and why the hard part of multi-agent systems is org design, not code."
---

There's a seductive idea in the agent world that goes: if one agent is good, ten agents must be ten times as good.

It's wrong in the same way "if one cook is good, ten cooks must be better" is wrong. Put ten cooks in a kitchen with no head chef, no stations, and no tickets, and you don't get a ten-course tasting menu. You get a grease fire and a lot of yelling. More agents without coordination isn't a force multiplier. It's a force *divider* with extra API bills.

But coordinated? That's different. I run eleven agents as a personal staff — a main dispatcher and ten specialists — and the difference between that and one mega-agent isn't subtle. It's the difference between a person and an org.

In [Parts 1–3](/posts/production-ai-agents-part1-architecture-foundations/) we built a single capable agent: a deterministic shell around a probabilistic core, with memory and safe tools. This post is about what happens when one agent isn't enough — and, just as important, when reaching for many is a mistake. Because multi-agent orchestration is the most over-reached-for pattern in this entire space, and the hard part isn't the code. It's the org design.

---

## Why Specialize At All?

Start with the case *for* it, because it's real.

A single generalist LLM gives you competent-but-generic answers across every domain. Ask it a tax question and a networking question and a writing question and you get three serviceable, slightly-hedged, jack-of-all-trades responses. It's the friend who knows a little about everything and isn't quite an expert at any of it.

A *specialized* agent is different. It's configured with domain-specific context, it remembers prior conversations *about that domain* (scoped memory, straight from [Part 2](/posts/production-ai-agents-part2-memory-context/)), and it has standing access to exactly the tools that domain needs. The output quality is categorically better — not because the underlying model changed, but because the *context* did.

In my own staff, when I have a tax question, I don't ask the dispatcher. I ask the finance agent — it has the context, remembers prior conversations about my situation, and gives me answers that aren't hedged into uselessness because it actually *knows* the specifics. The networking agent speaks BGP and Azure Local natively. The writing agent knows the house style. The security agent watches CVEs. Each one is the small-surface, single-responsibility principle from Part 1 — scaled up from "tool" to "teammate."

Specialization works for agents for the exact same reason it works for humans: depth beats breadth when the problem is hard.

---

## The Orchestration Patterns That Actually Work

Once you have specialists, *something* has to coordinate them. Here are the patterns that survive contact with production, roughly in order of how often you should reach for them.

### 1. Hub-and-Spoke (start here)

One coordinator — a dispatcher — sits at the center. The human talks to the hub. The hub routes work to the right specialist, collects the result, and relays it back. Spokes don't talk to each other directly; everything flows through the hub.

This is my daily driver. There's one agent I actually interact with; it dispatches to the specialists and hands me back the answer. It's air-traffic control: the planes (specialists) don't negotiate runways with each other and hope for the best — the tower (hub) sequences everything. Simple, debuggable, and the single point of coordination is also a single point of *visibility*, which matters enormously when something goes wrong (see [Part 5](/posts/production-ai-agents-part5-observability-ops/)).

**Reach for this first.** It covers the vast majority of real needs.

### 2. Pipeline / Handoff Chains

Some work is inherently sequential: agent A produces something, agent B refines it, agent C validates it. A writer drafts, an editor revises, a publisher checks. Each stage hands off to the next.

The classic version in my world: the writing agent produces a draft, the editing agent reviews it and flags what's weak, and I make the final call. (This very series is going through exactly that pipeline — drafted by one agent, about to be torn apart by another.) The key is that the handoff is *explicit and structured* — which we'll get to in a second, because it's where pipelines live or die.

### 3. The Coordinator for Genuinely Parallel Work

When a task truly decomposes into independent sub-tasks that can run at once — research three topics in parallel, analyze five files simultaneously — a coordinator can fan the work out, let the specialists run concurrently, and assemble the results.

This is the most powerful pattern and the one most likely to blow up in your face, because parallel probabilistic workers produce parallel surprises. Use it when the work is genuinely parallelizable and substantial. Don't use it to make a simple thing feel sophisticated.

---

## Handoffs: The Make-or-Break Artifact

Here's the thing nobody tells you: **multi-agent systems live and die on the quality of their handoffs.** When agent A passes work to agent B, everything A knew that doesn't make it into the handoff is *lost*. Context evaporates at every boundary. A sloppy handoff is a game of telephone; a good one is a clean baton pass.

So I treat handoffs as a real artifact with a required structure. When one agent finishes work another needs, it writes a handoff document containing, at minimum:

- **The task** — what specifically needs doing next.
- **The context** — what was done, what was decided, what was tried and rejected. The *why*, not just the *what*.
- **The deliverable location** — where the output actually lives. A path, a link, a concrete pointer.
- **The next agent in the chain** — who picks this up, and whether anyone needs to route it.
- **Status** — `PENDING` / `IN_PROGRESS` / `COMPLETE`. So nothing silently stalls.

That status field looks trivial. It's not. It's how you keep work from vanishing into the gap between two agents, each assuming the other has it. A handoff without a status is a dropped baton waiting to happen.

The discipline here is the same as a good engineering team. When you hand off a ticket, you don't just say "your turn" — you write down the context, link the work, and mark the state. Agents need that *more* than humans do, because they have no hallway, no Slack DM, no "hey real quick" to recover lost context. The document is the only channel. If it's not in the handoff, it didn't happen.

---

## Ceremonies: Stealing from Scrum (the Good Parts)

The squad system I built for a software project borrowed something from human teams that turned out to matter: **ceremonies** — lightweight structured checkpoints around the work.

Two earned their keep:

**Design review, before the work.** Trigger: a task involving two or more agents modifying shared systems. Before anyone writes anything, the relevant agents agree on the interfaces and contracts between their pieces, identify risks and edge cases, and assign action items. This is the multi-agent version of "measure twice, cut once." When several probabilistic workers are about to touch the same system, agreeing on the contract *first* prevents the most expensive failure mode: two agents confidently building incompatible halves of the same bridge.

**Retrospective, after a failure.** Trigger: a build failure, a test failure, a rejected review. The involved agents do a blameless post-mortem — what happened (facts only), root cause, what should change, action items for next time. This is how the *system* learns instead of repeating the same mistake. And it closes a loop straight back to [Part 2](/posts/production-ai-agents-part2-memory-context/): the output of a retrospective is a memory update.

These sound like corporate theater. They're not, because the agents actually *do* them — and the structure is what keeps a group of independent reasoners pointed at the same goal instead of optimizing locally and colliding globally.

---

## Diagnostic Integrity: Keep the Receipts

One non-obvious practice that saved me real debugging pain: when multiple agents contribute to a final artifact, **preserve every agent's raw output verbatim**, in an appendix, unedited.

The temptation is to have the coordinator polish everything into one smooth result and throw away the messy intermediate outputs. Don't. When the final artifact is wrong — and eventually it will be — those raw outputs are how you figure out *which agent* went sideways. The coordinator assembles the clean result on top, but it is forbidden from rewriting the raw outputs underneath. They're the receipts. They're the flight recorder.

This is a multi-agent-specific failure mode worth internalizing: when a *single* agent is wrong, you read its trace. When a *team* produces a wrong answer, you need to know whose contribution poisoned the well. Without preserved raw outputs, a multi-agent bug is a whodunit with no witnesses. With them, it's just reading the transcript.

---

## The Hard Parts (or: Why Not to Do This)

Now the honest part, the part the breathless multi-agent demos skip. Orchestration has real costs, and you should reach for it *reluctantly*.

**Delegation overhead is real.** Spinning up a specialist, writing the handoff, waiting for the result — that's friction. It's less friction than doing a big task yourself, but it is *not zero*. For a small question, delegation is pure overhead. I delegate when the task is substantial; for quick things, I just ask the hub directly. The setup cost only pays off at scale.

**Cost multiplies.** Every agent in a chain is its own set of LLM calls. A five-agent pipeline can be five times the tokens — or worse, if they loop or re-process each other's context. A multi-agent system can quietly become a money fire. (Watch this in [Part 5](/posts/production-ai-agents-part5-observability-ops/).)

**Context fragments.** This is the deep one. In a single agent, all the context lives in one place. Split the work across five agents and the context shatters into five partial views, and *no one agent sees the whole picture*. Every handoff is a chance to lose the thread. The architecture that gives you specialization is the same architecture that fragments understanding — that's the fundamental tension of multi-agent design, and you don't get to escape it. You only get to manage it, with disciplined handoffs and a clear source of truth.

**Someone has to own the truth.** When five agents each have memory, *which* memory is authoritative? You need one clear source of truth or your agents will confidently disagree with each other, each certain it's right. Usually the hub owns the canonical state and specialists hold scoped, subordinate views.

**Termination conditions.** Two agents can hand work back and forth forever, each politely waiting for the other, or "improving" each other's output in an infinite loop. Multi-agent systems need explicit stopping rules — max iterations, a clear definition of done — or they'll happily spend your entire budget being productive at each other.

Here's my honest heuristic, hard-won: **reach for a second agent when the task is substantial and genuinely benefits from specialization or parallelism. For everything else, one good agent with good tools beats a committee.** The committee *looks* more impressive in a diagram. It is usually slower, pricier, and harder to debug. A lot of "multi-agent systems" are one good agent's job wearing five hats and charging you for all five.

---

## So What

Multi-agent orchestration isn't a software problem. It's an org-design problem.

Everything that makes a human team work — clear roles, real accountability, structured handoffs, a single source of truth, checkpoints before and after, keeping the receipts — is exactly what makes an agent team work, for exactly the same reasons. The technology is almost incidental. You're not really wiring up LLMs. You're designing an organization that happens to be staffed by probabilistic workers who can't chat in the hallway to recover lost context, which means your handoffs have to be *better* than a human team's, not worse.

Specialize when depth beats breadth. Coordinate through a hub until you have a concrete reason not to. Make handoffs a real artifact with a status. Steal the good ceremonies. Keep the raw outputs. And — most importantly — don't reach for a symphony when a soloist will do. The most sophisticated multi-agent architecture is worthless if a single well-built agent would've shipped the answer yesterday for a fifth of the cost.

Next up — the finale. We've got a team of agents, with memory, wielding powerful tools. Which means we now have a *lot* of moving parts that can fail silently, expensively, and invisibly. You cannot run in production what you cannot see. Time to talk observability.

---

*This is Part 4 of a 5-part series on building production AI agents.*

1. [Architecture Foundations](/posts/production-ai-agents-part1-architecture-foundations/)
2. [Memory & Context Management](/posts/production-ai-agents-part2-memory-context/)
3. [Tool Design & Safety](/posts/production-ai-agents-part3-tool-design-safety/)
4. **Multi-Agent Orchestration** *(you are here)*
5. [Observability & Ops](/posts/production-ai-agents-part5-observability-ops/)

*How many agents are too many? I've got opinions and I want yours — [GitHub](https://github.com/ebmarquez) or comments below.*
