---
title: "Stop Trusting Your AI Blindly: A Simple System That Tells You When to Verify"
date: 2026-05-06
categories: [AI, Developer Tools]
tags: [ai, confidence-scoring, github-copilot, chatgpt, claude, cursor, llm, developer-tools]
description: "AI assistants are confidently wrong all the time. This portable custom instruction forces them to self-score every response — so you know when to ship and when to verify."
---

Here's my fix to the problem.

When you work with another person, you can read the room — the hesitation, the "I think," the way they glance away when they're not sure. Those microexpressions tell you how much to trust what they're saying. AI has none of that. It delivers a hallucination with the same confidence as a verified fact. There are no microexpressions.

I ran into this firsthand while investigating a new switch environment — an unfamiliar platform where I didn't have deep expertise. I turned to GitHub Copilot to help me figure it out. And like always with AI, it was completely confident in its answers. The problem? It was about 50% right, and in some cases it just hallucinated the entire thing. I had no way to know which was which until I went and verified it myself — which kind of defeats the point.

I needed a way to know how confident the AI actually was before I acted on its answers. So I had it build me a skill to score its own responses. Every answer now comes with an explicit confidence rating and a reason. I thought it was useful enough to share with everyone else.

The problem isn't that AI assistants get things wrong — it's that they get things wrong in exactly the same confident tone they use when they're right. You get no signal. Every response wears the same face.

There's a fix, and it takes about two minutes to set up.

---

## AI Speaks in One Tone (and That's the Real Problem)

Here's the thing about LLM output: there's no audible difference between "I read the actual API spec" and "I vaguely remember something from training data circa 18 months ago." Both answers arrive with the same syntax, the same confident declarative structure, the same absence of hedging.

This creates a tax on your attention. You end up doing one of two things:

1. Verify everything — which defeats part of the point of having an AI assistant
2. Verify nothing — which works great until it doesn't

What's missing is a signal. Not a disclaimer wall at the top ("I may make mistakes, please verify all information"), which nobody reads — but an actual, response-specific assessment of how much you should trust *this particular answer*.

That's what confidence scoring gives you.

---

## How It Works: Three Tiers and a Non-Negotiable Rule

The system is simple by design. Every substantive AI response ends with a block like this:

```
---
**Confidence:** 🟢 HIGH (90%) — Verified against the official docs and tested locally.
```

Three tiers:

- **🟢 HIGH (85–100%)** — Direct evidence. The model read the source, ran the command, or is working from well-established domain knowledge. Act on this.
- **🟡 MEDIUM (50–84%)** — Strong reasoning, but some assumptions involved. Partial evidence. Verify the specific claim before committing.
- **🔴 LOW (<50%)** — Extrapolation, limited sources, unfamiliar territory. Treat this as a starting point and go read the actual docs.

The tiers are the easy part. The rule is where it gets interesting.

---

## The Weakest Link Rule: Why You Can't Average Your Way Out

Here's the insight most confidence-scoring implementations miss: **you can't average a chain of reasoning**.

A prosecutor can have 10 solid pieces of forensic evidence and one piece with a broken chain of custody. They can't say "well, 9 out of 10 were solid, so we're 90% confident." That one broken link determines what they can actually present. The weakest link sets the floor.

Same logic applies here. The model evaluates its response across five dimensions:

1. **Source quality** — Did it read the actual source, or is it recalling from memory?
2. **Verification** — Did it run and confirm, or state it theoretically?
3. **Specificity** — Is it answering the exact question, or a nearby one?
4. **Recency** — Could this be outdated? (APIs change. Versions matter.)
5. **Complexity** — Simple lookup vs. multi-factor judgment call?

**Score = the weakest dimension.** Not the average. Not the best case.

If the model gives you a solid, well-sourced answer about an API endpoint — but one claim in that response is an assumption about GovCloud behavior it hasn't verified — the whole response gets downgraded. It can't hedge by averaging.

This is the code review mental model: a PR can have 200 great lines and one security hole. You don't merge it at 99% — you flag it. Confidence scoring applies the same logic to AI output.

The practical effect: MEDIUM responses tell you *something specific needs verification*, not "eh, probably fine." That's the difference between a useful signal and noise.

---

## What It Looks Like in Practice

Here are three scenarios pulled from real calibration examples:

**"Will this npm package work with Node 22?"**
The package README says Node 18+ is supported. Node 22 follows the same LTS pattern and no breaking APIs appear in a quick scan of the source.
> 🟡 **MEDIUM (75%)** — Strong reasoning, but no explicit Node 22 test confirmation.

You know immediately: don't just ship this. Spin up a Node 22 environment and run the tests.

**"Does this API endpoint exist?"**
The model read the OpenAPI spec and confirmed the exact endpoint.
> 🟢 **HIGH (90%)** — Verified against official specification.

Ship it.

**"Does AWS support this feature in GovCloud?"**
AWS generally mirrors commercial features in GovCloud but with a lag; can't confirm availability without checking the GovCloud-specific docs.
> 🔴 **LOW (40%)** — General AWS knowledge; GovCloud specifics require verification.

This is a starting point. Go read the GovCloud docs before you build anything around it.

The score changes what you do next. That's the whole point.

---

## Install It in Two Minutes (Any AI Assistant)

This is where it gets genuinely useful: the scoring instruction is a single copy/paste block. No plugins, no accounts, no API keys. Drop it into your AI assistant's system prompt once, and every substantive response includes the score from that point forward.

Here's the full instruction block:

```
## Confidence Scoring

Append a confidence score at the end of any response that presents information, recommendations, technical guidance, troubleshooting steps, or research findings.

**Scale:**
- 🟢 HIGH (85–100%): Based on direct evidence — read the source, ran the command, verified the docs, or well-established domain knowledge.
- 🟡 MEDIUM (50–84%): Strong reasoning or pattern matching, but some assumptions involved. Partial evidence.
- 🔴 LOW (<50%): Extrapolation, limited sources, conflicting info, or unfamiliar territory. Treat as a starting point.

**Scoring rules:**
- Score = the weakest link. One unverified assumption in a chain drops the whole score.
- Always include a one-line reason explaining WHY you scored it that way.
- When unsure between two levels, pick the lower one.
- Round to the nearest 5% — no false precision.
- Skip the score for trivial replies (task confirmations, "done", clarifying questions).

**Format — always at the end of the response:**

---
**Confidence:** 🟢 HIGH (90%) — Verified against the official docs and tested locally.

---
**Confidence:** 🟡 MEDIUM (65%) — Based on common patterns; haven't verified this specific version's behavior.

---
**Confidence:** 🔴 LOW (30%) — Extrapolating from adjacent docs; the actual behavior may differ.

**Inline uncertainty:** If one specific claim in an otherwise confident response is uncertain, flag it inline with *(unverified)* rather than dropping the whole score. Then score at the blended level.
```

**Where to paste it:**

- **GitHub Copilot (VS Code):** Add to `.github/copilot-instructions.md` in your repo, or paste into Copilot Chat's custom instructions setting.
- **ChatGPT:** Settings → Personalization → Custom Instructions → "How would you like ChatGPT to respond?"
- **Claude (claude.ai):** Start a Project → Project instructions → paste the block.
- **Cursor / Windsurf:** Add to your `.cursorrules` file (Cursor) or `.windsurfrules` file (Windsurf).
- **Any API call:** Prepend to the `system` message.

That's it. Two minutes, any tool you already use.

---

## What Changes After You Install It

The immediate change is obvious: every response comes with a signal you can act on.

🟢 HIGH means ship it. You still get hit by the rare wrong answer, but you've done what you could with the information available.

🟡 MEDIUM means check the specific claim the score calls out. The reason field isn't decoration — "haven't verified this specific version's behavior" tells you exactly what to look up.

🔴 LOW means this is a research starting point, not an answer. Treat it like a knowledgeable colleague who's working from memory and knows it. Useful direction, not ground truth.

The longer-term change is harder to quantify but more valuable: you start reading AI responses more critically, even outside the tool. The score trains your attention. You notice when an answer *feels* like it should be MEDIUM even without the badge. You catch yourself before you act on something the model was just confidently guessing at.

---

## Calibration: The Score Is Only Useful If It's Honest

There's one failure mode worth naming: a model that inflates scores to seem more reliable.

The rules are designed to prevent this. "When unsure between two levels, pick the lower one" is explicit — the bias runs toward honesty, not confidence. "No false precision" means 70%, not 73%. "Cite the reason" means the model has to articulate the uncertainty, not just slap a badge on and move on.

Does the model always score honestly? No. Calibration is imperfect by design — you're asking an LLM to assess its own epistemic state, and that's genuinely hard. But in practice, the scoring instruction does shift model behavior. You get more hedged language in the response body. You get more explicit uncertainty flags. And you get a baseline you can push back on: if a response feels like it should be MEDIUM and it came back HIGH, that's a prompt to ask "what makes you confident about this?"

The system isn't perfect. It's a better prior than "everything sounds right, so it probably is."

---

## Try It Yourself

1. **Copy the instruction block** above.
2. **Add it to one AI assistant** — whichever you use most right now.
3. **Ask it a question you'd normally just act on** — a package compatibility question, a Terraform argument, an API behavior you half-remember.

See what score you get back. More importantly, see if the reason changes what you do next.

The interesting cases are the LOW scores that looked right. Those are the ones that would have cost you time — or more.

---

*Originally developed as an OpenClaw skill. The portable instruction block above works with any AI assistant that accepts custom instructions or system prompts — no OpenClaw required.*
