---
layout: post
title: "Building Production AI Agents, Part 5: You Can't Debug What You Can't See"
date: 2026-07-02 09:00:00 -0700
categories: [AI, Architecture]
tags: [ai, agents, observability, ops, llm, production, monitoring, devops]
author: ebmarquez
description: "The scariest agent failure isn't the one that crashes — it's the one that quietly does the wrong thing while looking fine. The finale of the production AI agents series: observability, ops, cost control, and the feedback loop that closes the whole system."
---

The agent failure that should scare you isn't the one that crashes.

A crash is *easy*. It throws an error, something turns red, you get paged, you fix it. A crash is honest. The failure that should keep you up at night is the agent that's confidently, quietly doing the *wrong thing* — succeeding at the wrong task, building on a stale fact, looping on an expensive operation — while every dashboard stays green and every status says `OK`. It's not on fire. It's just wrong, calmly, and nobody knows.

That's the one that bites you in production. And it bites *harder* with agents than with normal software, for a reason we've been circling this whole series: agents are non-deterministic. The same input can produce different paths on different runs. "It worked yesterday" is not evidence of anything. You cannot reason your way to "it's probably fine." You have to be able to *see*.

This is the finale. Across [Parts 1–4](/posts/production-ai-agents-part1-architecture-foundations/) we built up a real system: a deterministic shell around a probabilistic core, with memory, safe tools, and a coordinated team of agents. Every layer we added bought capability — and added something new that can fail silently, expensively, and invisibly. This post is about the discipline that makes all of it operable: observability and ops. Because you cannot run in production what you cannot see, and most people building agents right now are flying blind and calling the quiet "stability."

---

## Why Agents Are Harder to See Into

Traditional observability assumes determinism. Same input, same code path, same output — so a failure is reproducible, and a trace tells a consistent story. Agents break all three assumptions:

- **Non-determinism.** The model can take a different route every run. A bug might show up one time in ten. You can't reliably reproduce it, which means you need to have *captured* it when it happened — there's no "run it again and watch."
- **Multi-step opacity.** A single user request can fan out into a dozen model calls, tool invocations, and agent handoffs. When the final answer is wrong, *which step* went wrong? Without a trace of the whole chain, you're guessing.
- **Silent semantic failure.** Normal software fails *loudly* — exceptions, stack traces, non-zero exits. Agents fail *quietly* — a plausible-looking answer that happens to be wrong. There's no exception for "technically ran fine, but hallucinated the account number."

So agent observability isn't just "add logging." It's capturing enough of the *reasoning and action trace* to reconstruct what the system was thinking when it did something dumb — because you will not get to ask it to do the dumb thing again on command.

---

## Signal, Not Spam: The Heartbeat Pattern

Let me start with the monitoring pattern I'm proudest of, because it solved a problem I didn't expect: *most monitoring is useless because it's either silent or screaming.*

I built a heartbeat system — periodic check-ins where the dispatcher pulls live data and surfaces anything that needs my attention. It watches a lot: urgent unread email, upcoming calendar events, open PRs sitting too long, home temperature, the kids' grades, weather for the garden, a hockey-referee scheduling script. A real spread of things I'd otherwise have to check manually.

The design decision that makes it *work* is dead simple:

> If nothing needs attention, it logs `HEARTBEAT_OK` and goes quiet. If something does, it surfaces it. No spam. Just signal when signal is warranted.

This is the whole art of operational monitoring compressed into one rule. The failure mode of most alerting isn't too few alerts — it's too *many*. Alert on everything and you've built a system people learn to ignore. It's the smoke detector that chirps so often you take the battery out — and then it's just decoration on the day there's an actual fire. The heartbeat's silence is *meaningful*: when it speaks, you listen, because it only speaks when it matters.

The behavioral payoff surprised me. I stopped compulsively checking email and GitHub, because I genuinely trusted that something was watching and would tap me on the shoulder when it mattered. That's the real goal of observability — not dashboards you stare at, but earned trust that you'll *find out* when something's wrong, so you can stop anxiously watching and go do your actual job.

Alongside the heartbeat I run scheduled jobs: a daily briefing each morning that synthesizes overnight events into one digest, and nag reminders for things I've been procrastinating. The pattern underneath both: **proactive synthesis beats reactive querying.** Don't make the human go ask twelve systems how things are. Have the system watch twelve things and tell the human the one that matters.

---

## What to Actually Instrument

Concretely, here's what earns its place in an agent's telemetry. Each ties back to a problem from an earlier post.

**Tool-call traces.** Every tool invocation: which tool, what arguments, what it returned, success or failure. This is your single highest-value signal. When an agent misbehaves, the tool trace usually shows exactly where reality diverged from intent — the wrong file, the looping call, the silently-empty return from [Part 3](/posts/production-ai-agents-part3-tool-design-safety/). If you instrument *one* thing, instrument this.

**Token and cost tracking, per agent, per task.** Non-negotiable, and it's where the multi-agent costs from [Part 4](/posts/production-ai-agents-part4-multi-agent-orchestration/) come home to roost. A looping agent or a bloated context window doesn't crash — it just quietly runs up a bill until your invoice arrives wearing a Halloween mask. Track tokens per agent per task, set budget alarms, and *cap* runaway loops. A cost graph is a debugging tool: a spike is often the first visible symptom of a logic bug.

**Audit logs.** Remember the security trail from Part 3 — host, user, action, result, timestamp, *never the secret*? That audit log was a safety control when we built it. In production it's also *telemetry*: an immutable record of every consequential action the agent took. When you need to answer "what did the agent actually do at 2am," this is the receipt. Safety and observability turn out to be the same log read two different ways.

**One hard caveat, because logging is where production agents leak:** the instinct to "log everything" collides head-on with secrets and PII. Tool arguments and return values are exactly where a password, an API token, a customer email, or a full account number sneaks into your logs — and a log is a low-security copy of data that was supposed to be high-security. Redact at the logging boundary: scrub known-sensitive fields, hash or mask identifiers you only need for correlation, and add the same CI check from Part 3 (grep the logs for `password`, `secret`, `token`, and obvious PII patterns; fail the build on a hit). "Log everything" means every *action*, not every *value*. The audit trail should prove what happened without itself becoming the breach.

**Confidence as telemetry.** The confidence scores from Part 3 aren't just a per-response gate — aggregate them and they become an operational signal. A sudden run of LOW-confidence outputs on a task that used to score HIGH is an early warning: something upstream changed — a source moved, an assumption broke, the world drifted out from under the agent. Confidence trends are a leading indicator of decay, and they're free once you're already scoring.

**Latency, per step.** Not just end-to-end. Step-level latency tells you *where* the time goes — which model call, which tool, which handoff is the bottleneck. Users feel slowness, and "the agent got slow" is unactionable without per-step numbers.

The throughline: instrument the **seams**. The boundaries between model and tool, between agent and agent, between this turn and the last. That's where agents fail, and the seams are exactly where the non-determinism leaks through.

---

## The Ops Problems Nobody Warns You About

Beyond instrumentation, running agents in production surfaces a category of operational hazards that traditional services just don't have.

**Model drift and version pinning.** Your agent's "code" is partly the model itself — and that model can change underneath you. A provider ships a new version, subtly alters behavior, and your carefully-tuned prompts quietly degrade. Nothing in *your* repo changed, but your agent got worse. **Pin model versions** where you can, and treat a model upgrade like any other dependency bump: test before you roll it, don't let it happen to you by surprise. Your most important dependency is one you don't host and can't freeze without trying.

**Prompt regression.** Tweak a system prompt to fix one behavior and you can silently break three others. Prompts are code, but most teams change them with none of the discipline they'd apply to code — no tests, no review, no version control. Keep a suite of evaluation cases — known inputs with expected-ish outputs — and run them when you change prompts. Prompt engineering without regression testing is just vibes with a deploy button.

**Cost runaway.** Said it already, saying it again louder, because it's the one that actually shows up on a credit card. An agent that loops, re-reads a huge context every turn, or fans out into a recursive multi-agent storm can burn money *fast*. Hard limits. Loop caps. Budget alarms. Build the circuit breaker before you need it, because the failure mode is "find out at the invoice," and by then it's spent.

**Graceful degradation.** What happens when the model API is down, or rate-limited, or timing out? A production agent needs a plan that isn't "explode." Fallback models, cached responses, a clear "I can't do that right now" instead of a hang or a crash. The deterministic shell from [Part 1](/posts/production-ai-agents-part1-architecture-foundations/) is exactly where this lives — when the probabilistic core is unavailable, the shell should fail *gracefully*, not catastrophically. Design the sad path, because the sad path is the one production will find for you.

---

## Closing the Loop

Here's the part that makes observability more than damage control, and it's where the whole series quietly snaps shut.

Observability isn't only about catching failures. It's the *input to improvement*. Watch the closed loop:

1. **Observe** — the agent does something wrong, and your telemetry catches it (a bad tool call, a LOW-confidence streak, a cost spike).
2. **Diagnose** — the trace shows you *why*: a misunderstood instruction, a stale fact, a missing guardrail.
3. **Update** — you fix it. And often the fix lands in *memory* — a corrected fact, a new preference, a lesson written into the curated layer from [Part 2](/posts/production-ai-agents-part2-memory-context/). Remember the retrospective ceremony from Part 4? Its output is a memory update. That's this loop running.
4. **Improve** — next time, the agent does better, because the system learned even though the model didn't.

That's the whole thing. The model is static — it's the same model on day one and day one hundred. But the *system* around it gets smarter every cycle: observability catches the misses, diagnosis explains them, memory absorbs the lessons, behavior improves. Observability is the sensory organ that makes the rest of the system capable of learning. Without it, your agent repeats its mistakes forever, confidently, in the dark.

---

## So What — and the Whole Series in One Breath

Production AI is an engineering discipline, not a prompt.

That's been the argument under every post in this series, and observability is where it becomes undeniable. You instrument the seams. You make silence meaningful and alerts rare. You track cost like it can hurt you, because it can. You pin your models, test your prompts, and design the sad path. And you close the loop, so every failure makes the system a little smarter.

Step back and look at what this series actually was. Five posts, and notice what almost none of them were about: **the model.** They were about everything *around* the model.

- **Part 1** — a deterministic shell around a probabilistic core. Deciding what you *don't* let the model do.
- **Part 2** — memory, because continuity is an org problem, not a context-window problem.
- **Part 3** — tools and safety, because power needs guardrails that live in code, not vibes.
- **Part 4** — orchestration, because a team of agents is org design, not a clever diagram.
- **Part 5** — observability, because you can't run what you can't see.

That's the 80% nobody puts in the demo. The demo is the model being impressive for thirty seconds under ideal conditions. Production is the unglamorous scaffolding — the memory systems, the credential vaults, the handoff protocols, the audit logs, the cost alarms, the regression suites — that lets the model be impressive *reliably, safely, and affordably*, on a Tuesday, at 2am, when nobody's watching.

The model is the easy part. You can swap it out; they get better every few months on their own. The engineering around it is the hard part, the durable part, the part that's actually *yours*. The people getting real value out of AI right now aren't the ones with a cleverer prompt. They're the ones who did the unglamorous work of building the system.

The demo is the easy 20%. Now you've got a map of the other 80%. Go build the boring parts. That's where production lives.

---

*This is Part 5 — the finale — of a 5-part series on building production AI agents. Thanks for reading the whole arc.*

1. [Architecture Foundations](/posts/production-ai-agents-part1-architecture-foundations/)
2. [Memory & Context Management](/posts/production-ai-agents-part2-memory-context/)
3. [Tool Design & Safety](/posts/production-ai-agents-part3-tool-design-safety/)
4. [Multi-Agent Orchestration](/posts/production-ai-agents-part4-multi-agent-orchestration/)
5. **Observability & Ops** *(you are here)*

*If this series saved you one 2am incident — or one Halloween-masked invoice — it did its job. And if you've shipped agents to production and learned something I got wrong or left out, that's the comment I actually want to read. Come tell me what broke: find me on [GitHub](https://github.com/ebmarquez) or drop it in the comments. Now go build the boring parts.*
