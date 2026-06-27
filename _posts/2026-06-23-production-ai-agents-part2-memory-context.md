---
layout: post
title: "Building Production AI Agents, Part 2: Your Agent Has Amnesia"
date: 2026-06-23 09:00:00 -0700
categories: [AI, Architecture]
tags: [ai, agents, memory, context, llm, production, rag]
author: ebmarquez
description: "Most 'AI memory' is just retrieval, and retrieval isn't continuity. Part 2 of the production AI agents series: the two-layer memory system that turns a goldfish into a colleague, and the context-window economics nobody warns you about."
---

Every time I opened a fresh chat window, I had to reintroduce myself to a genius with no long-term memory.

Who I am. What I'm working on. What I already tried. What I prefer. Not once — *every single time*. I was doing the work twice: once to solve the problem, and once to bring the AI up to speed so it could help me solve the problem. The model was brilliant and completely amnesiac, like Leonard from *Memento* if he also happened to know all of Stack Overflow.

That friction has a name. I call it **context tax**, and it compounds viciously when you're juggling a day job, multiple projects, a property, kids, and side work. Every interaction starts at zero. The bill comes due on every turn.

In [Part 1](/posts/production-ai-agents-part1-architecture-foundations/) I said state is a load-bearing wall, not a bolt-on. This post is about actually building that wall — and about the trap most people fall into, which is confusing *retrieval* with *continuity*. They are not the same thing, and the difference is the difference between an agent that feels like a tool and one that feels like a colleague.

---

## Retrieval Is Not Continuity

Here's the standard advice for "giving your agent memory": stuff your documents in a vector database, embed the user's query, pull back the top-k similar chunks, jam them in the prompt. RAG. Done. Memory achieved.

Except it isn't. That's *retrieval*, and retrieval is passive. It answers "what stored text is similar to this question?" It does not answer "what does this agent know about this user, this project, this ongoing situation?" Those are wildly different questions.

Retrieval is a librarian who can fetch any book you describe but has never met you and forgets you the moment you leave. Continuity is an assistant who's been working with you for six months, knows your projects are interdependent, remembers you hate a particular tool, and knows you already ruled out the obvious fix last Tuesday.

A good executive assistant doesn't ask you every Monday who you are and what your priorities are. They *already know*. They've been paying attention. That's continuity, and it's an organizational achievement, not a similarity-search result.

Production agents need both. Retrieval handles "find the relevant fact in this 10,000-document corpus." Continuity handles "resume our working relationship where we left off." Most people build the first and call it done, then wonder why their agent still feels like a stranger.

---

## The Two-Layer System: Inbox and Mind

Here's what I actually run, and it's almost embarrassingly low-tech. No exotic infrastructure. Two layers of Markdown.

**Layer one: the journal.** After any significant session, the agent writes down what happened — decisions made, work in progress, what got tried, what's blocked. These are dated files, one per day. They are *not* meant to be read carefully. They're raw. They're the inbox. Their entire job is to exist, so nothing falls through the cracks. Think of it as the append-only log of the agent's working life.

**Layer two: the curated memory.** Every few days, the agent reads back through recent journal entries and distills what's worth keeping long-term: lessons, decisions, durable preferences, the live state of active projects. This goes into a single curated document — `MEMORY.md`. It's the organized mind.

> The journal is the inbox. `MEMORY.md` is the organized mind.

The journal is high-volume and low-signal. The curated layer is low-volume and high-signal. The distillation step — promoting raw entries into curated truth — is the part that makes it *work*, because it's where noise becomes knowledge. Without it you just have a growing pile of logs nobody reads. With it, the agent starts each session by reading a tight, current snapshot of everything that matters and *resumes* instead of *restarting*.

That word — resume — is the whole point. A chat session restarts every time. A production agent resumes. The user shouldn't have to brief it. It should already know.

This maps cleanly onto how memory works in a runtime I built, where a dedicated memory agent exposes exactly four verbs — `remember`, `recall`, `list`, `forget` — over a persistent store with theme categorization (`preference`, `fact`, `note`). The verbs are boring on purpose. The intelligence is in the *curation policy*, not the API.

---

## The Context Window Is a Budget, Not a Closet

Now the part nobody warns you about, the one that turns a clean demo into a degrading mess over time.

You do not get to just "remember everything." The context window is finite, and even when it's enormous, it is not free. Every token you load is a token you pay for — in money, in latency, and, most insidiously, in *quality*. Cramming the window full doesn't make the model smarter. Past a point, it makes it dumber.

Treat the context window like a budget you're actively spending, not a closet you cram full and shut the door on. Every turn, something is deciding what gets loaded. If that something is "everything, always," you have three problems:

1. **Cost.** You're paying to re-send the same history on every turn, forever.
2. **Latency.** Big prompts are slow prompts. Users feel it.
3. **The lost-in-the-middle problem.** This is the sneaky one. Models attend well to the *start* and *end* of a long context and get foggy in the *middle*. Bury the critical fact in the center of a giant prompt and the model effectively can't see it. More context literally caused worse recall.

So you budget. The hierarchy I use, roughly in priority order:

- **Always-load (the curated mind).** The tight, durable snapshot — who, what, current project state, hard preferences. Small. High-signal. Earns its slot every time.
- **Recent (recency window).** The last little while of actual conversation, verbatim. This is your short-term memory.
- **Retrieved-on-demand (relevance window).** Pull specific facts from the journal or document store *only when this turn needs them*. Don't pre-load the whole archive on the off chance.
- **Summarized (compressed history).** When the conversation gets long, compress the older middle into a summary instead of carrying it verbatim. Trade fidelity for room.
- **Dropped.** Yes, dropped. Some things age out. Letting go is a feature.

The skill is balancing **recency versus relevance**. The thing that happened most recently isn't always the thing that matters most, and the thing that matters most might be a preference you set two months ago. A good memory system serves both: a steady recency stream *plus* targeted relevance pulls, against a curated always-on baseline.

---

## Scoped Memory: Not Every Agent Needs Every Memory

There's a structural decision here that ties straight back to the small-agents principle from Part 1.

When you run multiple specialized agents, you do *not* give them all one shared blob of memory. You scope it. My tax agent doesn't need to remember a networking debugging session. My networking agent doesn't need my property's lease terms. Each specialist carries the context relevant to its domain, plus a thin shared layer of "who the human is."

Scoped memory buys you the same things small agents bought you in Part 1:

- **Less noise.** The model isn't wading through irrelevant context to find what matters. (Remember the lost-in-the-middle problem — irrelevant context isn't neutral, it's actively harmful.)
- **Cleaner reasoning.** Domain context produces domain-quality answers, not hedged-to-death generic ones.
- **Cheaper turns.** You're not paying to load the property agent's brain into the tax agent's prompt.

The shared layer stays small and universal. The scoped layers stay deep and specific. It's the same org-design instinct as small agents: give each component exactly what it needs and nothing it doesn't.

---

## The Ways Memory Betrays You

Memory isn't free of failure modes. It introduces new ones. Forewarned:

**Stale memory.** A "fact" that *was* true. The agent confidently tells you the project uses library X — which you ripped out three weeks ago, but the curated note never got updated. Stale memory is worse than no memory, because it's confidently wrong. The fix: distillation has to *update and retire*, not just append. Memory that only grows is memory that rots.

**Context poisoning.** A bad fact — a hallucination, a wrong inference, a misread — gets written into memory and then *persistently* corrupts every future session. One bad entry, and the agent keeps "remembering" something that was never true. The fix: be careful what you let into the curated layer. The journal can be messy; the mind must be trustworthy. Promotion is a gate, not a firehose.

**The generation-loss drift.** Over enough cycles of distill-and-summarize, meaning quietly mutates — a game of telephone the agent plays with itself. Guard the curated layer against lossy self-summarization of the things that must stay precise. Some facts get carried verbatim, not paraphrased.

The throughline: **the curated layer is sacred.** Guard what gets in. A clean, trusted, current `MEMORY.md` beats a giant pile of half-true logs every day of the week.

---

## So What

Continuity is an organizational problem, not a model problem.

You don't solve amnesia by waiting for a bigger context window. You solve it by *building a memory system*: a raw journal that catches everything, a curated mind that distills what matters, a budget that spends the context window deliberately, and scoping that gives each agent exactly the context it needs. The model is the same on day one and day one hundred. The system around it is what makes day one hundred better than day one.

This is, again, the lesson from Part 1 in a new costume: the intelligence is in the *system design*, not the raw model. Memory is the part of that system that turns a goldfish into a colleague — something that resumes instead of restarting, that you brief once instead of every time.

Build the memory infrastructure early. I built mine late and lost continuity I can't get back. Don't make my mistake — frame the house around this wall.

Next up: memory is what the agent *knows*. Tools are what it can *do*. And the moment you hand a probabilistic system real power — shell access, credentials, the ability to change the world — the stakes change completely. That's where it gets dangerous, and that's the next post.

---

*This is Part 2 of a 5-part series on building production AI agents.*

1. [Architecture Foundations](/posts/production-ai-agents-part1-architecture-foundations/)
2. **Memory & Context Management** *(you are here)*
3. [Tool Design & Safety](/posts/production-ai-agents-part3-tool-design-safety/)
4. [Multi-Agent Orchestration](/posts/production-ai-agents-part4-multi-agent-orchestration/)
5. [Observability & Ops](/posts/production-ai-agents-part5-observability-ops/)

*How do you handle memory in your agents? I'm always looking for better distillation strategies — find me on [GitHub](https://github.com/ebmarquez) or comment below.*
