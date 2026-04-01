---
layout: post
title: "Here's a /25 — Figure Out the Address Plan"
date: 2026-03-31 00:00:00 -0700
categories: [networking, ai]
tags: [sonic, copilot, ai, networking, bgp, automation, data-center]
author: ebmarquez
description: "I handed GitHub Copilot a /25 subnet and told it to plan IP addressing for a two-switch iBGP fabric with spine uplinks. Then we deployed it. Here's what happened."
image:
  path: https://images.unsplash.com/photo-1558494949-ef010cbdcc31
  alt: "Data center network infrastructure with fiber optic cables"
---

*This is Part 2 of a series about deploying SONiC switches with AI assistance. [Part 1](/posts/hey-copilot-can-you-ssh-into-a-switch/) covered discovery — pointing Copilot at two factory-blank switches and watching it map the hardware, topology, and CLI quirks. Now we configure things.*

---

Last time, the AI had mapped out two Dell S5248F-ON switches running SONiC — complete inventory, physical topology via LLDP, a CLI translation guide for Dell Enterprise SONiC's `sonic-cli` framework, and a list of open questions. The switches were still factory blank. Time to change that.

I opened a new session with Copilot and said something like:

> "Here's a /25 subnet — `100.100.81.128/25`. Plan the IP addressing for a two-switch iBGP fabric with uplinks to two Cisco spine switches. Then deploy it."

And then I watched.

## 128 Addresses, Zero Room for Guessing

A /25 gives you 128 addresses. That sounds generous until you start carving it up for a data center fabric. You need loopbacks for each switch (used as router IDs and VTEP sources for VXLAN later), point-to-point links between the two ToR switches, point-to-point links to each spine, and enough headroom for whatever comes next.

Here's what Copilot produced:

| Use | Address | Assignment |
|-----|---------|------------|
| Loopback — ToR A | `100.100.81.129/32` | Router ID + future VTEP source |
| Loopback — ToR B | `100.100.81.130/32` | Router ID + future VTEP source |
| P2P Link 1 (Eth38) | `100.100.81.132/31` | ToR A = .132, ToR B = .133 |
| P2P Link 2 (Eth39) | `100.100.81.134/31` | ToR A = .134, ToR B = .135 |
| Spine uplink 1 | `100.100.81.136/31` | ToR A → Spine B |
| Spine uplink 2 | `100.100.81.138/31` | ToR A → Spine A |
| Spine uplink 3 | `100.100.81.140/31` | ToR B → Spine B |
| Spine uplink 4 | `100.100.81.142/31` | ToR B → Spine A |
| Reserved | `.144` – `.254` | Growth |

Clean, sequential, predictable. Loopbacks from the bottom of the range, point-to-point /31s packed tight, and everything above .143 left untouched for future expansion. It's the kind of addressing plan you'd expect from someone who's done this before — methodical, no wasted space, easy to mentally parse when you're troubleshooting at 2 AM.

I didn't tell it to use /31s for point-to-point links. I didn't tell it to start loopbacks at .129. I didn't tell it to reserve the upper half. It made those choices based on standard data center practice. Not revolutionary — but correct, which is what matters.

## The BGP Design: iBGP Inside, eBGP Outside

With addresses planned, next came the routing design. Two decisions mattered:

**Inside the rack: iBGP.** Both ToR switches share ASN 65337. With only two nodes, you don't need a route reflector — it's a full mesh of one peer each. Simple. The AI got this right immediately.

**To the spines: eBGP.** The Cisco spine switches run ASN 64805 as part of a larger eBGP leaf-spine fabric. Each rack gets its own ASN, and the spines peer to every leaf pair. This is a standard L3 Clos design — no OSPF, no IS-IS, just eBGP everywhere above the rack.

I had to nudge the AI on the spine ASN. It initially proposed a generic private ASN, but the lab's spine fabric had an existing convention: template-based peer configs, a specific prefix-list for inbound filtering, and a description format that encoded the leaf ASN, hostname, and role. I shared a sample config from a colleague, and Copilot pattern-matched it perfectly for our two new switches.

## Deploying the Underlay

Configuration happened in layers, and this is where the human-AI collaboration pattern became clear: **I told it *what* to configure, and it figured out *how* to express it in SONiC's CLI.**

### Layer 1: Loopbacks

```
interface Loopback 0
  ip address 100.100.81.129/32
  no shutdown
```

Straightforward. Same on ToR B with `.130`. The AI applied these through the serial console, verified with `show ip interface`, and moved on.

### Layer 2: Inter-Switch P2P Links

The two ToR switches connect on Ethernet38 and Ethernet39 — the 25G DAC links we'd discovered in Part 1.

```
interface Ethernet 38
  ip address 100.100.81.132/31
  no shutdown

interface Ethernet 39
  ip address 100.100.81.134/31
  no shutdown
```

Ping between switches: ✅

### Layer 3: Spine Uplinks

This one required a physical-layer detour. The spine uplinks use 10G SR optics (SFP+) plugged into ports that default to 25G. The AI had discovered these optics during Part 1's transceiver inventory, and it knew they wouldn't negotiate correctly at the wrong speed.

The fix: set the port-group speed to 10G.

```
port-group 12 speed 10000
```

On the spine side (Cisco NX-OS), the 40G QSFP ports needed breakout configuration to get down to 10G per lane:

```
interface breakout module 1 port 27 map 10g-4x
interface breakout module 1 port 28 map 10g-4x
```

Each 40G port splits into four 10G interfaces. Lane 4 on each connected to our ToR switches. After applying IPs on both sides:

| ToR | Port | ToR IP | Spine | Spine Port | Spine IP |
|-----|------|--------|-------|------------|----------|
| ToR A | Eth47 | .138/31 | Spine A | Eth1/27/4 | .139/31 |
| ToR A | Eth46 | .136/31 | Spine B | Eth1/27/4 | .137/31 |
| ToR B | Eth47 | .142/31 | Spine A | Eth1/28/4 | .143/31 |
| ToR B | Eth46 | .140/31 | Spine B | Eth1/28/4 | .141/31 |

All four links came up. Pings verified end to end.

## Bringing Up BGP

With the underlay addressed and reachable, time for routing. The AI configured BGP in the hierarchical sub-mode that Dell Enterprise SONiC expects:

**ToR A:**

```
router bgp 65337
  router-id 100.100.81.129
  log-neighbor-changes
  timers 60 180

  address-family ipv4 unicast
    network 100.100.81.129/32
    redistribute connected

  address-family l2vpn evpn
    advertise-all-vni

  neighbor 100.100.81.133
    remote-as 65337
    address-family ipv4 unicast
      activate
    address-family l2vpn evpn
      activate

  neighbor 100.100.81.137
    remote-as 64805
    address-family ipv4 unicast
      activate

  neighbor 100.100.81.139
    remote-as 64805
    address-family ipv4 unicast
      activate
```

ToR B mirrored the config with its own router ID (`.130`) and the complementary neighbor IPs. The EVPN address family was activated between the iBGP peers — not needed yet, but it's the foundation for the VXLAN overlay coming in Phase 2.

The spine-side config used the existing peer template convention:

```
! On each spine (router bgp 64805)
template peer Host-Leaf-65337
  remote-as 65337
  address-family ipv4 unicast
    prefix-list BLOCK-FROM-RACK in
    maximum-prefix 12000 warning-only

neighbor 100.100.81.138
  inherit peer Host-Leaf-65337
```

Four spine neighbors total (two per spine), each inheriting the template. The AI composed these configs by extrapolating from the sample I'd shared — same template name pattern, same prefix-list reference, same description format. It didn't just copy; it adapted.

## "BGP ESTABLISHED but Nothing Works"

And then we hit the moment every network engineer knows and dreads.

`show bgp ipv4 unicast summary` on ToR A:

```
Neighbor        AS    MsgRcvd  MsgSent  Up/Down   State/PfxRcd
100.100.81.133  65337    42       45    00:12:34   2
100.100.81.137  64805    38       41    00:10:22   67
100.100.81.139  64805    39       40    00:10:18   67
```

All three BGP sessions: **ESTABLISHED**. The spines were sending 67 prefixes. The iBGP peer was exchanging loopbacks. Everything looked perfect on paper.

But when I said "great, now make sure the loopbacks are reachable from the spine side" — silence. The spines couldn't reach `100.100.81.129` or `.130`. The ToR-to-spine P2P links pinged fine, but anything behind them was a black hole.

The AI dug in. It checked the routing table on the spines. The ToR loopback routes were *there* — BGP had learned them. But the return path was the problem. The spines knew how to reach the ToR loopbacks (via the eBGP-learned routes), but the ToRs needed routes back to whatever the spines were sourcing from.

The issue was subtle: the spine's own P2P networks weren't being advertised back to the ToRs under the right routing context. The ToRs received 67 prefixes from the spines (the rest of the lab's routes), but the specific connected subnets on the spine-to-ToR links needed explicit `network` statements or `redistribute connected` under the correct address family.

This is a classic cross-vendor debugging exercise. SONiC on the ToR side, NX-OS on the spine side, and the problem lives in the gap between them. The AI diagnosed it by comparing what each side was advertising vs. receiving, traced it to the missing route advertisements, and proposed the fix.

After adjusting the spine configs, everything converged. The routing table on ToR A told the full story:

```
C>* 100.100.81.129/32  Direct  Loopback0
B>* 100.100.81.130/32  via 100.100.81.133  Ethernet38
C>* 100.100.81.132/31  Direct  Ethernet38
C>* 100.100.81.134/31  Direct  Ethernet39
C>* 100.100.81.136/31  Direct  Ethernet46
C>* 100.100.81.138/31  Direct  Ethernet47
```

ToR A could see ToR B's loopback via the iBGP peer. Connected routes for all P2P links present. The 67 prefixes from the spines gave visibility into the broader lab fabric. Both directions working.

`write memory` on both switches. Configs saved. Phase 1: **done.**

## What the AI Got Right (and Where I Steered)

Let me be honest about the division of labor, because I think this matters more than any single configuration command.

**What the AI handled on its own:**
- IP addressing plan — clean, sequential, no wasted space
- SONiC CLI syntax — the hierarchical BGP config mode, interface addressing, `write memory`
- Verification — running show commands after each change, confirming state before moving on
- Documentation — producing structured tables and config blocks I could review

**Where I provided direction:**
- The spine ASN (64805) and the existing template convention — the AI couldn't know this without seeing the existing fabric
- The eBGP design decision (not OSPF, not IS-IS) — I told it this was a leaf-spine eBGP Clos
- The "no MCLAG" decision — I explicitly chose iBGP with independent forwarding over multi-chassis LAG
- The port-group speed setting — I'd learned this from the colleague's sample configs and pointed the AI at the relevant section
- Debugging direction during the "ESTABLISHED but broken" moment — I told it to check the spine routing table, not just the ToR side

The pattern is clear: **the human provides architectural decisions and environmental context. The AI provides execution precision and documentation discipline.** Neither of us could have done this as efficiently alone. I'd have been slower on the CLI syntax (Dell SONiC's Klish is still unfamiliar to me). The AI would have been lost without knowing the spine fabric's conventions.

## What's Next

The underlay is up. Both ToR switches have iBGP between them, eBGP to both Cisco spines, and a clean /25 address plan with room to grow. The EVPN address family is activated and waiting.

Phase 2 is the overlay: VXLAN tunnels sourced from the loopbacks, VLANs mapped to VNIs, EVPN route exchange (Type-2 for MAC/IP, Type-3 for BUM traffic), and anycast gateways for inter-VLAN routing. That's where it gets interesting — and where the AI will need to navigate SONiC's VXLAN implementation, which has its own set of quirks.

But before that, something unexpected happened. I discovered that Dell Enterprise SONiC ships with gNMI telemetry and a REST API running out of the box — no configuration needed. That discovery led to a detour that changed how I think about switch monitoring entirely.

*Next up: "Stop SSHing Into My Switches" — gNMI telemetry on SONiC, and why streaming beats polling.*

---

*This series documents a real lab deployment using AI assistance. The configurations are from production-grade hardware in a test environment. The AI collaboration described uses GitHub Copilot — I guided the architecture, the AI executed and documented. Your mileage may vary, but the patterns are real.*
