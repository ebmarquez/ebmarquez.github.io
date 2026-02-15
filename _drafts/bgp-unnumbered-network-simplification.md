---
layout: post
title: "BGP Unnumbered: The Network Simplification You Didn't Know You Needed"
date: 2026-02-15 12:00:00 -0800
categories: [networking]
tags: [bgp, unnumbered, loopback, spine-leaf, cisco, dell]
author: Eric Marquez
description: "How BGP unnumbered with loopback peering eliminates IP address management overhead and simplifies spine-leaf fabric operations."
image:
  path: 
  alt: "BGP unnumbered network diagram"
---

Every network engineer has been there. You're building out a spine-leaf fabric and suddenly you're staring at a spreadsheet with dozens of point-to-point /31 links. Each one needs an IP address. Each one needs documentation. Each one is another thing to fat-finger at 2 AM.

What if you could just... not?

Welcome to **BGP unnumbered** — the networking equivalent of realizing you've been doing it the hard way this whole time.

## The IP Address Tax

Traditional spine-leaf fabrics charge an invisible tax. Every point-to-point link between a leaf and a spine needs a /31 subnet. Two IP addresses per link, one on each side. That's the deal.

For a modest fabric — say 4 leaf switches and 2 spines — that's 8 point-to-point links and 16 IP addresses just for the underlay. Scale it up to 16 leaves and you're managing 64+ link addresses before you've even configured a single tenant.

Now multiply that by the human cost:

- **Planning** — IP allocation spreadsheets, subnet reservations, IPAM entries
- **Configuration** — neighbor statements referencing specific IPs on both sides
- **Documentation** — diagrams labeling every link with addresses
- **Troubleshooting** — "which /31 goes to which link again?"
- **Fat-finger risk** — transpose two digits and enjoy your 3 AM troubleshooting session

That's the tax. And BGP unnumbered eliminates most of it.

## What Is BGP Unnumbered?

Traditional BGP peering requires both sides to have configured IP addresses. You assign a /31 to each link, configure the neighbor statement with the remote IP, and pray you didn't transpose two digits.

BGP unnumbered flips this:

- **No IP addresses on point-to-point links** — interfaces use IPv6 link-local addresses (fe80::/10) that are auto-generated
- **Neighbor by interface, not by IP** — the switch discovers its peer automatically
- **Loopback-based identity** — each switch gets one loopback IP, and that's its identity in the fabric

### The Loopback Is the Only IP That Matters

Here's the key insight: your **loopback addresses are the only IPs that matter**. Every switch gets one loopback (like `10.0.0.1/32`), and that becomes its router-id, its VTEP source, its management identity. The physical links between switches? They're just plumbing.

Think of it like this: your loopback is your phone number. The physical links between switches are hallways in a building. You don't assign phone numbers to hallways.

## The Math

Let's compare a fabric with 8 leaf switches and 2 spines (16 point-to-point links):

**Traditional numbered BGP:**

- 16 point-to-point links × 2 IPs each = **32 link addresses**
- 10 loopback addresses (one per switch)
- 16+ explicit neighbor statements with specific IPs
- Total IPs to manage: **42**

**BGP unnumbered:**

- Point-to-point link addresses: **0**
- 10 loopback addresses (one per switch)
- Neighbor statements: interface-based (no IPs needed)
- Total IPs to manage: **10**

That's not a minor optimization. That's **deleting an entire category of work**. And it scales linearly — the bigger the fabric, the more you save.

## What You Actually Configure

### Cisco NX-OS (N9K Spine or Leaf)

NX-OS 10.6+ supports BGP unnumbered via prefix-based peers on point-to-point interfaces. The interfaces run with `medium p2p` and `ip unnumbered loopback0`:

```text
! Loopback — the only IP this switch needs
interface loopback0
  ip address 10.0.0.1/32

! Fabric uplink — no IP address assigned
interface ethernet 1/49
  description to-spine-1
  no switchport
  medium p2p
  ip unnumbered loopback0
  no shutdown

router bgp 65001
  router-id 10.0.0.1

  ! Peer with spine loopback — clean, stable
  neighbor 10.0.0.10
    remote-as 65100
    update-source loopback0
    address-family ipv4 unicast
```

No /31 on the link. No `neighbor 10.1.1.x`. The physical interface borrows its identity from the loopback.

### Dell OS10 (S5248F-ON Leaf)

Dell OS10 takes it a step further with interface-based neighbor discovery:

```text
! Loopback
interface loopback0
  ip address 10.0.0.1/32

! Fabric uplink — peer by interface name
interface ethernet 1/1/49
  no switchport
  no shutdown

router bgp 65001
  router-id 10.0.0.1

  ! Neighbor by interface — no IP needed at all
  neighbor interface ethernet 1/1/49
    no shutdown
```

That's it. No IP address assignment on the uplinks. The switch figures it out using IPv6 link-local addresses under the hood.

## The Simplification Cascade

Removing link IPs triggers a cascade of operational wins that extends well beyond address management:

### Configuration Templates Become Cookie-Cutter

With numbered BGP, every link is unique — different /31, different neighbor IP. With unnumbered, fabric link configs are **identical across switches**. Change the loopback and the AS number, and you're done. This makes automation with tools like Ansible or Cisco NSO dramatically simpler.

### Troubleshooting Gets Faster

Fewer moving parts, fewer things to break. `show bgp neighbors` maps directly to physical interfaces — no more cross-referencing IP addresses against your spreadsheet. When a peer drops, you know exactly which cable to look at.

### Day 2 Operations Get Easier

Adding a new leaf switch? Cable it to the spines, assign a loopback, configure the interface neighbors. No IP planning for the physical links. No updating the allocation spreadsheet. No coordinating with the IPAM team.

### Documentation Gets Lighter

Network diagrams don't need IP labels on every link. Runbooks shrink. New engineers onboard faster because there's less to memorize.

## The Trade-Offs

BGP unnumbered isn't magic — it has considerations worth knowing:

- **Platform support varies.** Cisco NX-OS 10.6+ and Dell OS10 handle it well. Older firmware may not support it, or may support it with caveats. Check your release notes.
- **IPv6 runs under the hood.** The mechanism uses IPv6 link-local addresses for neighbor discovery. If your environment has IPv6 disabled at the hardware level, you'll need to enable it on fabric-facing interfaces.
- **Troubleshooting mindset shift.** Engineers used to `ping 10.1.1.1` to verify a link need to adapt. `show bgp neighbors` by interface becomes the primary tool.
- **Mixed environments need care.** If you're mixing unnumbered and numbered peers in the same fabric, or interoperating between vendors (Dell OS10 ↔ Cumulus/FRR), pay attention to `link-local-only-nexthop` behavior and next-hop resolution.
- **Not for every topology.** BGP unnumbered works best on point-to-point links in a spine-leaf design. Multi-access segments or legacy topologies may still need numbered peers.

## When to Use It

BGP unnumbered is the right choice when:

- You're building a **spine-leaf fabric** with point-to-point links between tiers
- You want to **minimize configuration differences** between switches
- You're scaling beyond a handful of switches and the IP management overhead is real
- You're using **VXLAN/EVPN** and need a clean underlay that gets out of the way
- You value **operational simplicity** over familiarity with the traditional approach

It's not the right choice when:

- You need numbered peers for policy reasons (some compliance frameworks require it)
- Your hardware or firmware doesn't support it
- You're running a legacy three-tier or hub-and-spoke topology

## The Bottom Line

BGP unnumbered with loopback peering removes the largest source of configuration errors in spine-leaf fabrics: mismatched point-to-point IP addresses. What's left is a clean underlay where every switch is identified by a single loopback IP, fabric links are anonymous plumbing, and scaling means adding switches — not spreadsheet rows.

Less infrastructure to maintain. Less documentation to keep current. Less surface area for human error.

Sometimes the best engineering is removing things.

---

*For vendor-specific BGP and VXLAN configuration guides, check out the [network switch knowledgebase](https://github.com/microsoft/network-switch-knowledgebase) covering Cisco NX-OS and Dell OS10.*
