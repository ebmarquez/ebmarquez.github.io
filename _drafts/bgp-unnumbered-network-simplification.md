---
layout: post
title: "BGP Unnumbered: The Network Simplification You Didn't Know You Needed"
date: 2026-02-15 12:00:00 -0800
categories: [networking]
tags: [bgp, unnumbered, loopback, spine-leaf, cisco, dell, lab, data-center]
author: Eric Marquez
description: "How BGP unnumbered with loopback peering simplifies spine-leaf fabric operations at scale."
image:
  path: 
  alt: "BGP unnumbered spine-leaf network diagram"
---

You just got approval for a build. Maybe it's 5 racks. Maybe it's 20. Servers are racked, power is connected, and now someone turns to you and says: "So how are we networking all of this?"

If you're reaching for a spreadsheet to start planning /31 subnets for every point-to-point link in your spine-leaf fabric, stop. Put the spreadsheet down. There's a better way.

Welcome to **BGP unnumbered** — the part of your build where networking finally gets out of the way.

## The Problem with "Just Give Every Link an IP"

Traditional spine-leaf fabrics require IP addresses on every point-to-point link between leaves and spines. Each link gets a /31. Both sides need configured neighbor statements referencing the remote IP. Every link is unique.

For a small fabric — 2 racks, 4 leaf switches, 2 spines — that's maybe 8 links and 16 addresses. Manageable. Annoying, but manageable.

Now scale it to a real environment:

**10 racks, 20 leaf switches, 2 spines:**

- 40 point-to-point links
- 80 IP addresses on fabric links alone
- 40 unique /31 subnets to plan and document
- 80 neighbor statements referencing specific IPs

**20 racks, 40 leaf switches, 4 spines:**

- 160 point-to-point links
- 320 IP addresses
- 160 /31 subnets
- 320 neighbor statements

That's 320 IP addresses that serve no purpose other than establishing BGP sessions. They don't carry user traffic. They don't show up in your monitoring dashboards. They just exist so two switches can say hello to each other — and each one is an opportunity to fat-finger a digit during a late-night deployment push.

That's 320 perfectly good IPv4 addresses burning a hole in your IPAM for links that never leave the rack. Meanwhile, the rest of the internet is rationing addresses like it's the end times. ARIN would like a word.

This is the IP address tax, and at scale, it's brutal.

## What BGP Unnumbered Actually Does

BGP unnumbered eliminates that entire category of work. Instead of assigning IP addresses to every fabric link, you do this:

- **Fabric interfaces get no IP addresses.** They use IPv6 link-local addresses (fe80::/10) that are auto-generated from the MAC address. No planning required.
- **Neighbors are identified by interface, not IP.** Instead of `neighbor 10.1.1.5 remote-as 65100`, you configure `neighbor interface ethernet 1/1/49`. The switch discovers its peer automatically.
- **Every switch gets one loopback IP.** That's its identity — router-id, VTEP source, management anchor. One IP per switch. Done.

### The Hallway Analogy

Your loopback is your phone number. The physical links between switches are hallways in a building. You don't assign phone numbers to hallways — you assign them to the offices at the end. BGP unnumbered applies that same logic to your fabric.

## The Lab Math

Let's compare a 10-rack build (20 leaves, 2 spines):

**Traditional numbered BGP:**

- 40 link addresses + 22 loopback addresses = **62 IPs to manage**
- 80 neighbor statements with hard-coded IPs
- 40 /31 subnets to allocate and document
- Each leaf config is unique (different /31s on each uplink)

**BGP unnumbered:**

- 0 link addresses + 22 loopback addresses = **22 IPs to manage**
- Neighbor statements reference interfaces, not IPs
- Zero /31 planning
- Leaf configs are nearly identical — change the loopback and the ASN

At 20 racks, the gap gets absurd. You go from 320+ link IPs down to **zero**. The only IPs in your fabric are loopbacks — one per switch, easy to plan, easy to audit, easy to remember.

## What the Config Looks Like

This is the part where it gets fun. Less config, less to break.

### Cisco NX-OS Leaf

NX-OS 10.6+ supports unnumbered interfaces with `ip unnumbered loopback0` and `medium p2p`:

```text
interface loopback0
  ip address 10.0.0.1/32

interface ethernet 1/49
  description to-spine-1
  no switchport
  medium p2p
  ip unnumbered loopback0
  no shutdown

interface ethernet 1/50
  description to-spine-2
  no switchport
  medium p2p
  ip unnumbered loopback0
  no shutdown

router bgp 65001
  router-id 10.0.0.1
  neighbor 10.0.0.100
    remote-as 65100
    update-source loopback0
    address-family ipv4 unicast
  neighbor 10.0.0.101
    remote-as 65100
    update-source loopback0
    address-family ipv4 unicast
```

No /31 on the uplinks. The interfaces borrow their identity from loopback0. The BGP sessions peer between loopbacks — stable, clean, and the same pattern on every leaf in every rack.

### Dell OS10 Leaf

Dell takes it further with interface-based neighbor discovery:

```text
interface loopback0
  ip address 10.0.0.1/32

interface ethernet 1/1/49
  no switchport
  no shutdown

interface ethernet 1/1/50
  no switchport
  no shutdown

router bgp 65001
  router-id 10.0.0.1
  neighbor interface ethernet 1/1/49
    no shutdown
  neighbor interface ethernet 1/1/50
    no shutdown
```

That's it. No IP address on the uplinks. No neighbor IP to configure. The switch discovers the remote peer using IPv6 link-local and establishes the session automatically.

## Why This Matters at Scale

Any environment running spine-leaf with more than a handful of racks benefits from BGP unnumbered. Labs, staging environments, production data centers — the operational wins are the same:

### The Network Doesn't Need to Be the Bottleneck

Whether you have a dedicated network team or you're wearing that hat yourself, the /31 planning step is dead weight. BGP unnumbered removes it. You assign loopbacks, template the configs, and move on to the work that actually matters.

### Infrastructure Changes Constantly

Environments aren't static. You add racks, decommission racks, repurpose racks for different workloads. With numbered BGP, every change means IP planning — new /31s for the uplinks, updated neighbor statements on the spines, updated documentation. With unnumbered, you assign a loopback, cable the uplinks, and the fabric absorbs the new leaf automatically.

### Templates Are Your Friend

When every leaf config follows the same pattern — change the loopback, change the ASN, done — you can template the entire thing. Generate configs from a simple YAML file listing switch names and loopbacks. Ansible, Cisco NSO, Terraform, Python scripts — whatever your tool, the config generation becomes trivial because there are no per-link unique values.

### Mismatched /31s Are a Troubleshooting Nightmare

Here's what actually happens with numbered BGP: someone transposes two digits in a /31, the BGP session doesn't come up, and now you're spending an hour staring at `show bgp neighbors` trying to figure out why a session is stuck in Active. It's not a catastrophic failure — it's worse. It's a subtle, annoying, time-wasting troubleshooting exercise that never should have existed. BGP unnumbered eliminates that entire class of problem. No point-to-point IPs, no mismatches, no nonsense.

## The Simplification Cascade

Removing link IPs isn't just one less thing. It cascades:

- **IPAM** — no /31 allocation requests, no subnet tracking for fabric links
- **Config management** — fewer unique values per switch means fewer merge conflicts, fewer drift issues
- **Troubleshooting** — `show bgp neighbors` maps to physical interfaces. No more "which /31 was on this link?"
- **Documentation** — network diagrams drop the IP labels on fabric links. Runbooks get shorter. Onboarding new engineers is faster.
- **Day 2** — adding a leaf is cable + loopback + template. No coordination with IPAM. No spine config changes if you're using dynamic peers.

## The Trade-Offs

It's not magic. Know the edges:

- **Platform support varies.** Cisco NX-OS 10.6+ and Dell OS10 handle it well. Older firmware may not. If you're running Nexus 9Ks with NX-OS 9.x, check your release notes before planning around unnumbered.
- **IPv6 is involved.** The mechanism uses IPv6 link-local for neighbor discovery. If your environment has IPv6 disabled at a firmware level, you'll need to enable it on fabric interfaces. This doesn't mean you're "deploying IPv6" — it's just the signaling mechanism.
- **Troubleshooting is different.** Engineers used to `ping 10.1.1.1` to verify a link need to adapt. The primary troubleshooting tool becomes `show bgp neighbors` by interface. It's not harder — it's just different.
- **Vendor interop needs testing.** If you're mixing vendors (Dell leaves + Cisco spines, or adding Cumulus/FRR into the mix), test the unnumbered interop in your specific firmware combination. `link-local-only-nexthop` behavior can vary.
- **Not for every topology.** This works on point-to-point links in a spine-leaf design. Multi-access segments, legacy three-tier, or hub-and-spoke topologies still need numbered peers.

## When to Use It

If you're typing `router bgp`, use unnumbered. This isn't a scale question — it's a complexity question. BGP unnumbered isn't more complex than numbered. It's actually simpler. Even with 2 switches and a single point-to-point link, the unnumbered config is cleaner: no /31 to plan, no neighbor IP to match, no opportunity to fat-finger. The only reason to choose numbered on a new build is legacy firmware that doesn't support it.

Whether you're building 2 racks or 20, the benefits are the same:

- You want **repeatable, templatized configs** that scale without per-link customization
- You're running **VXLAN/EVPN** and need a clean underlay that stays out of the way
- You value **less complexity** over doing it the traditional way

## The Bottom Line

If you're staring down a 10-rack build and dreading the IP planning spreadsheet for the fabric underlay, BGP unnumbered is the answer. One loopback per switch, zero IPs on fabric links, templatized configs that scale from 5 racks to 20 without changing the approach.

The switches don't care about the IPs on those links. Your monitoring doesn't query them. Your users never see them. So why are you spending hours planning them?

Sometimes the best engineering is removing things.

---

*For vendor-specific BGP and VXLAN configuration guides, check out the [network switch knowledgebase](https://github.com/microsoft/network-switch-knowledgebase) covering Cisco NX-OS and Dell OS10.*
