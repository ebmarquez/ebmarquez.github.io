---
layout: post
title: "I Built a Personal AI Operating System — Here's What Actually Works"
date: 2026-06-01 00:00:00 -0800
categories: [AI, Projects]
tags: [ai, agents, openclaw, automation, productivity, personal-os, llm]
author: ebmarquez
description: "I replaced my scattered AI usage with a team of persistent agents that monitor my life, manage my projects, and remember everything. Here's what I built and what I learned."
---

The thing that broke me on single-session AI wasn't any one failure. It was the compounding grind of context tax.

Every time I opened a chat window to ask for help with something — a GitHub PR, a rental property issue, a networking problem at work — I had to spend the first five minutes explaining who I am, what I'm working on, and what I've already tried. Not once. Every single time. The model had no memory. No continuity. No awareness that I'd asked a related question yesterday, or that I'd already ruled out the obvious answers, or that I have preferences.

I was doing the same cognitive work twice: once to solve the problem, and once to bring the AI up to speed so it could help me solve the problem.

That friction compounds fast when you're juggling multiple projects, a day job, kids, a property to manage, and side work. So I stopped tolerating it. I built something different.

---

## The Philosophy First

I want to be clear about what this *isn't* before I tell you what it is.

It's not an automation platform. I'm not running n8n workflows or Zapier chains. It's not a chatbot with a memory plugin. It's not a single LLM with a longer context window.

What I built is closer to a personal staff — a main assistant with persistent memory, a set of specialist agents I can delegate to, and infrastructure that keeps the whole thing running between sessions. Think of it less like a tool and more like a team that happens to run on your laptop.

The core insight: an AI agent that knows you, remembers context, and has standing visibility into your life is categorically more useful than a stateless chat session — even if both are running the same underlying model. The difference is organizational, not algorithmic.

---

## The Main Agent: Jordan

The anchor of the system is a persistent agent I call Jordan. Jordan runs as a continuous process, not a web session. It has a name because that turned out to matter — naming an agent creates a kind of accountability contract. You treat it like a collaborator instead of a calculator.

Jordan wakes up each session and does something a chat session never does: reads its own memory. There's a `MEMORY.md` file — a curated, evolving document that captures who I am, what I'm working on, my preferences, the state of active projects, ongoing decisions. There are also daily journal files: raw logs of what happened each session. The combination means Jordan isn't starting from scratch. It's resuming.

This is closer to how a human assistant actually works. A good EA doesn't ask you every Monday who you are and what your priorities are. They already know. They've been paying attention. That's what I was trying to replicate.

The practical effect: I don't brief Jordan. I just pick up where we left off.

---

## What the Agents Actually Do

Jordan is the hub, but the real power comes from delegation. I have ten specialist agents — each focused on a specific domain, each with its own context and personality.

The roster:

- **Devon** — GitHub, CI/CD, DevOps. Watches my repos, triages issues, handles PR reviews, flags anything that needs attention on the npm package I published.
- **Mike** — Networking. My day job is Microsoft networking engineering, and Mike speaks that language. BGP configs, Azure Local, Cisco — it's the domain expert I can think out loud with.
- **Ghost** — Security. Passive CVE monitoring, hardening recommendations, scans when I ask.
- **Riley** — Technical writing. Turns rough notes or a brain dump into a readable blog post. (Riley wrote this draft, actually — more on that in a minute.)
- **Sarah** — Editing. Reads what Riley wrote and tells me what's wrong with it.
- **Taylor** — Career coaching and leadership strategy.
- **Maya** — Learning plans, when I'm picking up something new.
- **Finley** — Tax and finance. Contribution projections, entity structure questions, deduction tracking.
- **PropMan** — Manages a commercial property I own. Lease tracking, maintenance coordination, vendor communication.
- **Alexa** — Orchestration. When something requires multiple agents working in sequence, Alexa coordinates.

This matters because specialization works. A generalist LLM will give you competent-but-generic answers across domains. An agent that has been configured with domain-specific context, that remembers prior conversations about that domain, that has standing access to the relevant tools — that's a different quality of assistance.

When I have a tax question, I don't ask Jordan. I ask Finley. Finley has the context, remembers prior conversations, and gives me answers that aren't hedged to death because it actually knows my situation.

---

## The Heartbeat System

Here's the part that surprised me most when I built it: the proactive monitoring.

Jordan runs periodic check-ins — I call them heartbeats — that pull in live data and surface anything that needs my attention. Not because I asked. Because it's just doing it in the background.

What gets monitored: email (urgent unread messages), calendar (upcoming events), GitHub (open issues and PRs on my projects), home temperature via Home Assistant, kids' grades through their school's Canvas portal, weather relevant to the garden, and a hockey referee scheduling script that checks for available games.

The heartbeat runs on a schedule. If nothing needs my attention, it logs `HEARTBEAT_OK` and goes quiet. If something does — an important email, a PR that's been sitting for two days, a grade that dropped — it surfaces it. No notification spam. Just signal when signal is warranted.

I also have cron jobs for scheduled tasks: a daily briefing each morning that synthesizes overnight events, task nag reminders for things I've been procrastinating, and a few monitoring scripts for specific things I care about.

The effect is that I've stopped doing the mental overhead of checking a dozen different things. I check Jordan. Jordan tells me if anything needs my attention across all of them.

---

## The Memory System: Why It Works

Most AI memory implementations are just retrieval. You store a thing, the model retrieves it when relevant. That's better than nothing, but it's still passive.

What I've landed on is a two-layer system:

The **journal** is the raw log. After significant sessions, Jordan writes what happened, what decisions were made, what's in progress. These are dated files, one per day per machine. They're not meant to be read carefully — they're meant to exist so nothing falls through.

**MEMORY.md** is the curated layer. Every few days, Jordan reads through recent journal entries and distills what's worth keeping long-term: lessons, decisions, preferences, active project state. The journal is the inbox; MEMORY.md is the organized mind.

The reason this matters: the model starts each session with full context on my life, not just the last conversation. It knows I prefer certain tooling, that I've already tried certain approaches, that there's a dependency between project A and project B. That's not retrieval — that's continuity.

It also means I can hold the AI accountable. When I ask Jordan to follow up on something, it actually can. Because it wrote down that it was supposed to.

---

## What Surprised Me

A few things I didn't expect:

**The delegation overhead is real.** Spinning up a specialist agent, writing a handoff document, waiting for results — that's friction. It's less friction than doing the task myself, but it's not zero. The system pays off when the task is substantial. For small questions, I just ask Jordan directly.

**Naming matters more than I thought.** This sounds soft, but it's not. When an agent has a name, I interact with it differently. I give it clearer briefs. I'm more likely to push back when the output is wrong. I treat its work as accountable instead of disposable. That changes the quality of the output I get back.

**The heartbeat system trained me.** I stopped checking email compulsively because I knew the heartbeat was watching. I stopped manually scanning GitHub because Devon flags what matters. There's a weird behavioral shift that happens when you genuinely trust that something is watching — you let go of the anxious monitoring and just wait for signal. I did not expect that.

**What I'd do differently:** I built the memory system too late. I had the agents running for weeks before I built the journal layer, and there's a gap in continuity I can't recover. Start with memory infrastructure. Everything else depends on it.

---

## The "So What" — Why This Matters to Anyone

I'm not writing this to sell you on a specific tool. OpenClaw is what I used to build this, but the architecture is what matters, not the platform.

The argument I'm making is this: the people getting the most out of AI right now aren't using it harder — they're using it *differently*. They've built infrastructure. They've invested in continuity. They've organized their AI usage the way they'd organize a team: roles, accountability, standing context, clear handoffs.

If you're opening a fresh chat window every time you have a question, you're leaving most of the value on the table. Not because the model is bad. Because you're treating a potential collaborator like a search engine.

The transition from "AI as tool" to "AI as team" doesn't require anything exotic. It requires deciding that the setup cost is worth it — building memory, naming agents, establishing standing context, creating processes for when the output is wrong.

That's an organizational problem, not a technical one. And those are solvable.

---

## A Note on This Post

Riley — my technical writing agent — wrote the first draft of this. Sarah reviewed it. I edited the final version.

That's not a gimmick. That's the system working as intended. I gave Riley source material, a structure, and Eric's voice as a reference. Riley produced a draft in one pass. Sarah flagged two sections that were too vague and one that undersold the heartbeat system. I agreed with all three notes and revised.

Total time from "write this post" to published draft: less than an hour. Not because the AI did all the work — I still had to review, push back, and make judgment calls. But the heavy lifting of getting words on a page in the right order with the right structure was handled.

That's what the system is for. Not replacing the thinking. Offloading the execution so I can focus on the thinking.

---

*Questions, feedback, or you've built something similar — find me on [GitHub](https://github.com/ebmarquez) or leave a comment below.*
