---
layout: post
title: "Not All Rack-Aware Designs Are Equal"
date: 2026-04-09 00:00:00 -0700
categories: [networking]
tags: [azure-local, networking, rdma, data-center, hci, rack-aware]
author: ebmarquez
description: "Azure Local gives you four network designs for rack-aware clusters. The official docs describe them. Here's which one to actually pick — and why."
image:
  path: https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=1200&q=80
  alt: "Data center network infrastructure"
---

## Four Network Designs, One Brutal Constraint

A customer dropped four network diagrams on my desk and asked which one they should use for their rack-aware Azure Local deployment. Four designs. Same cluster. How hard could it be?

Turns out, the answer to "which design?" isn't about cost, or port density, or which vendor logo you prefer on your switches. It comes down to one thing: **RDMA**.

But let me back up.

### What's a Rack-Aware Cluster, Anyway?

[Azure Local rack-aware clusters](https://learn.microsoft.com/en-us/azure/azure-local/concepts/rack-aware-cluster-reference-architecture?view=azloc-2603) split nodes across two physical locations — usually two rooms or zones in the same building. Think factory floors with regulatory isolation, fault domain separation between server closets, or just "we ran out of space in Room A." You can go up to 4+4 nodes, four in each room, with one hard rule: **latency between rooms stays under 1ms**.

That's not a suggestion. That's a wall.

### The Constraint That Shapes Everything

Here's where it gets interesting. Management traffic? Flows through your spine switches like normal. Compute traffic? Same deal — routed across the spine, no drama. But **storage traffic** plays by completely different rules.

Storage in Azure Local rides on RDMA — Remote Direct Memory Access. If you haven't dealt with RDMA before, the short version is this: it lets servers read and write directly to each other's memory over the network, bypassing the CPU. It's absurdly fast. It's also absurdly picky about its network environment.

Your storage VLANs (711 and 712) are **pure Layer 2 broadcast domains**. No IP addresses. No routing. No "let's just throw a gateway on it." These VLANs exist as stretched L2 segments, and RDMA traffic flowing across them **never touches the spine layer**. It stays at the Top-of-Rack level, period.

That single constraint — RDMA storage traffic cannot traverse the spine — is the lens you need to evaluate every single one of these four designs. Every difference between them traces back to how they handle this reality.

### The Switch Requirements You Can't Skip

RDMA doesn't just need a network. It needs a **lossless** network. Regular Ethernet treats dropped packets like a Tuesday — just retransmit and move on. RDMA treats a dropped packet like a five-alarm fire. So your switches need to support the full lossless stack:

- **DCB** (Data Center Bridging) — the umbrella framework
- **PFC** (Priority Flow Control) — pause frames that prevent buffer overflows
- **ETS** (Enhanced Transmission Selection) — traffic class bandwidth guarantees
- **LLDP with DCB TLVs** — so switches and hosts can negotiate lossless settings automatically
- **MSTP** (Multiple Spanning Tree Protocol) — loop prevention across your VLANs

These aren't nice-to-haves. Skip any one of them and your RDMA traffic will hit drops, which means storage retries, which means performance craters, which means you're getting a call at 2 AM.

With that foundation set, let's look at what these four designs actually do differently — and why it matters.

## Option A — Dedicated Storage Links (The Baseline)

If you're building a two-room Azure Local cluster and want the most straightforward dual-ToR design, this is your starting point. Option A is the "say what you mean" approach — every link has a clear purpose, and traffic takes the shortest path possible.

Here's the setup: four Top-of-Rack switches — TOR-1 and TOR-2 in Room 1, TOR-3 and TOR-4 in Room 2. Each node gets two NICs. The first NIC joins a SET (Switch-Independent Teaming) team handling management and compute traffic, trunked with VLANs 7 and 8 respectively. Standard stuff.

The second NIC is where it gets interesting — it's **dedicated to storage**. No teaming, no trunking across multiple VLANs. Each storage interface carries a single VLAN: either 711 or 712. Clean. Simple. One interface, one job.

The room-to-room connectivity follows the same philosophy. Instead of dumping all storage traffic onto shared inter-switch links, you wire dedicated connections per storage VLAN:

- **TOR-1 ↔ TOR-3** carries VLAN 711
- **TOR-2 ↔ TOR-4** carries VLAN 712

Notice what's *not* happening here: MLAG stays out of the storage path entirely. Your management and compute traffic can use MLAG between the paired ToRs in each room — that's fine. But RDMA storage traffic? It bypasses MLAG completely, taking the most direct path from source to destination. Fewer hops, lower latency, less weirdness.

**Why this matters for RDMA:** Every additional hop is a latency tax. RDMA was designed to move data with minimal CPU overhead and minimal network traversal. The moment you start bouncing packets through extra switches, you're undermining the whole point. Option A respects that.

**The wins:**

- **Simplest dual-ToR design.** Less config to mess up, less to troubleshoot at 2 AM.
- **Lowest latency.** RDMA traffic takes the most direct path — no detours, no surprises.
- **Clean separation.** Each storage interface handles one VLAN. You can reason about traffic flows without a whiteboard and three energy drinks.

## Option B — Aggregated Storage Links (The Overachiever)

Option B looks at Option A and says, "But what if we added redundancy?" It uses the same four-switch topology but aggregates the room-to-room storage connectivity with vPC (or port-channels, depending on your vendor vocabulary). TOR-1 and TOR-2 form vPC pairs connecting across to TOR-3 and TOR-4.

On paper, this looks more resilient. In practice? It just adds hops.

Here's the catch. When storage traffic hits those aggregated links, the path it takes depends on the link hashing algorithm. You get two possible outcomes:

- **Direct path:** TOR-1 → TOR-3. Great. This is what you wanted.
- **MLAG traversal:** TOR-1 → TOR-4 → TOR-3. Not great. That extra hop through TOR-4 adds latency — and for RDMA, latency is the enemy you're specifically trying to avoid.

You can't control which path the hash picks. So some of your storage traffic takes the express lane, and some takes the scenic route through an extra switch. The kicker? **This extra redundancy doesn't actually buy you anything.** When you look at failure scenarios, Options A and B have equivalent resiliency. If a ToR dies, you lose the same connectivity in both designs. The vPC aggregation in Option B is complexity theater — it *looks* like it's doing something useful, but it's just adding latency and config overhead for no measurable gain.

## The Verdict: A Over B, Every Time

Here's the honest take: **Options A and B are functionally the same design** with different wiring choices for storage links. The real architectural differences show up when you compare either of them to Options C or D (which we'll get to).

But if someone's asking you to choose between A and B specifically? **Pick A.** It's simpler, it's lower latency, and it doesn't pretend to be something it's not. Option B looks impressive on a whiteboard. In practice, it just adds hops for the sake of looking busy.

Save your complexity budget for where it actually matters.

## Option C: The Budget Play (Single ToR Per Room)

Option C is the minimalist's dream: one ToR per room, handling everything — management, compute, SMB1, SMB2. All four intents on a single device, logically separated through different interfaces and VLANs. All storage intents share the same QoS policy to keep RDMA happy.

The room-to-room link can be bonded and carries both storage VLANs. Configuration is straightforward. Fewer switches means fewer things to configure, fewer things to monitor, and a lower hardware bill.

**The pro is real.** If you've ever spent a weekend configuring MLAG between four ToR switches and debugging why VLAN 712 isn't traversing correctly, you'll appreciate the simplicity of "one switch, done."

**But the con is massive.** There's no ToR redundancy. If that single switch dies — hardware failure, firmware crash, someone trips over the power cable — you lose the entire room. Not just storage, not just compute. Everything. The room goes dark until that switch comes back online.

For a test or validation environment where downtime is an inconvenience, not a disaster? Option C makes a lot of sense. The cost savings are real, the configuration is minimal, and if the switch goes down, nobody's losing production workloads.

For production factory environments with real-time industrial applications? You need to have an honest conversation about risk tolerance. If the answer is "we can't afford to lose a room," Option C isn't for you. If the answer is "we can tolerate it and we'd rather save on switches," then it's a perfectly valid choice — just make sure everyone signs off on it with eyes open.

## Option D: The Sleeper (Cross-Room Node Connectivity)

Option D is the one that surprises people. Instead of building room-to-room links for RDMA traffic, you eliminate the need for them entirely.

How? Every node connects directly to ToR devices in **both** rooms:

- SET team NIC 0 → local TOR1 (room 1)
- SET team NIC 1 → remote TOR2 (room 2)
- SMB1 NIC → TOR1 (room 1)
- SMB2 NIC → TOR2 (room 2)

The result: RDMA traffic stays **local to a specific ToR**. There's no off-ToR RDMA communication between rooms at all. Storage intent 1 talks to TOR1, storage intent 2 talks to TOR2, and never the twain shall meet at the switch level. The room-to-room links between ToR switches only carry management and compute traffic — standard MLAG, lower bandwidth, no RDMA QoS requirements on those links.

**Operationally, this is the cleanest design.** It behaves like a standard single-rack cluster that happens to be physically split across two rooms. If you're already running Azure Local clusters and you know how they work, Option D feels familiar. You can use vPC/HSRP between the ToRs for high availability on the management/compute side.

**The catch: fiber.** Every single node needs physical connections to switches in both rooms. That's cross-room fiber runs for every server. In a small deployment (4+4 nodes), that's 16 additional fiber runs you wouldn't need with Options A or B. The infrastructure cost adds up, especially if the rooms aren't next door to each other.

But here's the trade-off that makes D interesting: you're spending more on fiber to spend **less** on inter-room switch bandwidth. No RDMA traffic crossing rooms means your room-to-room links can be smaller and simpler. For some environments, the fiber investment pays for itself in reduced switch port costs and simpler QoS configuration on the inter-room links.

D is the sleeper option. Operationally the cleanest, architecturally the most elegant — but your fiber budget needs to agree.

## So Which One Do You Pick?

Let's cut through it. Here's the comparison:

| | **A (Dedicated)** | **B (Aggregated)** | **C (Single ToR)** | **D (Cross-Connect)** |
|---|---|---|---|---|
| **ToRs per room** | 2 | 2 | 1 | 1 (nodes connect to both rooms) |
| **RDMA latency** | Lowest | Higher (MLAG hops) | Low | Lowest (local only) |
| **Resiliency** | High | Same as A | Low (SPOF) | High |
| **Fiber cost** | Moderate | Moderate | Low | High |
| **Complexity** | Moderate | Higher | Lowest | Moderate (cabling) |
| **Best for** | Production | — | Test/Dev | Production (budget permitting) |

But honestly, the table oversimplifies it. The real decision isn't four options — it's three:

**Option A is your production default.** Dual ToR, dedicated storage links, lowest latency, clean separation of concerns. It's proven, it's straightforward, and it doesn't ask you to accept unnecessary risk. If a customer asks me "which one should I pick?" and gives me no other context, the answer is A.

**Option C is the budget play.** You're trading resiliency for simplicity and cost savings. That's a valid trade in non-production environments. Just make sure everyone involved understands what "loss of a ToR equals loss of a room" actually means for their workloads. Get it in writing.

**Option D is the premium option.** It gives you the cleanest operational model — standard cluster behavior in a split-room layout — but you're paying for it in fiber. If you're already running Azure Local clusters and want the rack-aware deployment to feel the same, D is your answer. The fiber investment often pays for itself in simpler inter-room links and familiar operations.

**Option B? Skip it.** It's Option A with extra hops, extra complexity, and the same resiliency. The vPC aggregation looks good on a whiteboard but doesn't help RDMA in practice.

## Context Is Everything

The right answer depends on questions only the customer can answer:

- **What are you running?** Factory automation with real-time requirements? Don't compromise on resiliency — A or D. Dev/test workloads? C might be fine.
- **What's the fiber situation?** If cross-room fiber runs are cheap (rooms are adjacent, conduit exists), D becomes very attractive. If fiber is expensive or the rooms are far apart, A wins.
- **What's your operational model?** Already running standard Azure Local clusters with a team that knows them? D gives the most familiar experience. Greenfield deployment with a lean ops team? A's simplicity is hard to beat.
- **What's your risk tolerance?** This is the C question. Some organizations genuinely can tolerate room-level failure in certain environments. Most can't in production.

## The Bottom Line

The [official reference architecture](https://learn.microsoft.com/en-us/azure/azure-local/concepts/rack-aware-cluster-reference-architecture?view=azloc-2603) tells you what these designs are. This post is about which one to pick.

The answer is almost always **A** — unless your fiber budget says **D** or your CFO says **C**.
