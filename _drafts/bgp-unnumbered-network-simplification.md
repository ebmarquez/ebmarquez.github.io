---
layout: post
title: "BGP Unnumbered: The Network Simplification You Didn't Know You Needed"
date: 2026-02-14 12:00:00 -0800
categories: [networking, azure-local]
tags: [bgp, unnumbered, loopback, spine-leaf, azure-local, cisco, dell]
author: Eric Marquez
description: "How BGP unnumbered with loopback peering eliminates IP address management overhead and simplifies spine-leaf fabric operations at scale."
image:
  path: 
  alt: "BGP unnumbered network diagram"
---

# BGP Unnumbered: The Network Simplification You Didn't Know You Needed

<!-- Riley voice: Hook 'em early, keep it real, make networking fun -->

## The IP Address Tax Nobody Talks About

Every network engineer has been there. You're building out a spine-leaf fabric — maybe 64 nodes, maybe more — and suddenly you're staring at a spreadsheet with hundreds of point-to-point /31 links. Each one needs an IP address. Each one needs documentation. Each one is another thing to fat-finger at 2 AM.

What if I told you there's a way to just... not?

Welcome to **BGP unnumbered** — the networking equivalent of "why were we doing it the hard way this whole time?"

## What Is BGP Unnumbered?

<!-- Mike's technical context: BGP unnumbered uses IPv6 link-local addresses (fe80::/10) 
     to establish BGP sessions over point-to-point links without assigning IPv4/IPv6 
     global addresses to the interfaces. Peers are identified by interface, not IP. -->

Traditional BGP peering requires both sides to have configured IP addresses. You assign a /31 to each link, configure the neighbor statement with the remote IP, and pray you didn't transpose two digits.

BGP unnumbered flips this on its head:

- **No IP addresses on point-to-point links** — interfaces use IPv6 link-local addresses automatically
- **Neighbor by interface, not by IP** — `neighbor interface ethernet 1/1/6` instead of `neighbor 10.1.1.1`
- **Loopback-based peering** — all your real routing happens over loopback addresses that never change

### The Loopback Connection

Here's the key insight: your **loopback addresses are the only IPs that matter**. Every switch gets one loopback IP (like `10.0.0.1/32`), and that becomes its identity. The actual fabric links between switches? They're just plumbing — they don't need their own addresses.

Think of it like this: your loopback is your phone number. The physical links between switches are hallways in a building. You don't assign phone numbers to hallways.

## Why This Changes Everything at 64 Nodes

<!-- Context: Azure Local 64-node cluster with Cisco N9K spines + Dell S5248F leaves -->

Let's do some math on a 64-node Azure Local deployment:

### Traditional Numbered BGP

| Item | Count |
|------|-------|
| Leaf switches | ~32 pairs |
| Spine switches | 2-4 |
| Point-to-point links | ~128+ |
| /31 subnets needed | ~128+ |
| IP addresses to manage | ~256+ |
| Neighbor statements with IPs | ~256+ |

That's **256+ IP addresses** you need to plan, document, configure, and troubleshoot. Miss one? Enjoy your troubleshooting session.

### BGP Unnumbered

| Item | Count |
|------|-------|
| Loopback IPs needed | ~36 (one per switch) |
| Point-to-point IPs needed | **0** |
| Neighbor statements | Interface-based (auto) |
| IP planning spreadsheet rows eliminated | **220+** |

That's not a minor optimization. That's **deleting an entire category of work**.

## What You Actually Configure

### Dell OS10 Leaf (S5248F-ON)

```text
router bgp 65001
  router-id 10.0.0.1

  ! No IP address on the interface — just peer by interface name
  neighbor interface ethernet 1/1/49
    no shutdown

  neighbor interface ethernet 1/1/50
    no shutdown
```

That's it. No `neighbor 10.x.x.x remote-as 65100`. No IP address assignment on the uplinks. The switch figures it out using IPv6 link-local addresses under the hood.

### Cisco NX-OS Spine (N9K-9336C-FX2)

```text
router bgp 65100
  router-id 10.0.0.10
  
  ! Loopback for overlay peering
  neighbor 10.0.0.1
    remote-as 65001
    update-source loopback0
    address-family l2vpn evpn
      send-community both
      route-reflector-client
```

The spine peers with leaf loopbacks for the EVPN overlay — clean, stable, and the loopback never goes down unless the whole switch does.

## The Simplification Cascade

This isn't just about saving IP addresses. BGP unnumbered triggers a cascade of simplifications:

### 1. IP Address Management (IPAM) — Simplified
- No more /31 allocation spreadsheets for fabric links
- Only loopbacks need IPAM entries
- Fewer DNS records, fewer firewall rules

### 2. Configuration Templates — Cleaner
- Fabric link configs become cookie-cutter identical
- Interface-based neighbors mean less per-switch customization
- Easier to automate with NSO/Ansible

### 3. Troubleshooting — Faster
- Fewer moving parts = fewer things to break
- `show bgp neighbors` maps directly to physical interfaces
- No "which /31 goes to which link?" confusion

### 4. Day 2 Operations — Easier
- Adding a new leaf? Just cable it and configure the interface neighbor
- No IP planning required for the physical link
- Loopback is the only thing you need to allocate

### 5. Documentation — Lighter
- Network diagrams don't need IP labels on every link
- Runbooks shrink significantly
- New engineers onboard faster

## The Trade-offs (Because There Are Always Trade-offs)

<!-- Mike would insist on covering these -->

BGP unnumbered isn't magic — it has considerations:

- **Platform support**: Not all vendors/versions support it equally. Dell OS10 and Cisco NX-OS 10.6+ handle it well. Older firmware? Check your release notes.
- **IPv6 dependency**: It uses IPv6 link-local under the hood. If you've been avoiding IPv6, surprise — it's been helping you all along.
- **Troubleshooting mindset shift**: Engineers used to `ping 10.1.1.1` need to adapt to `show bgp neighbors` by interface.
- **Mixed environments**: If you're mixing unnumbered and numbered peers, the `link-local-only-nexthop` behavior needs careful attention (especially Dell OS10 ↔ Cumulus/FRR interop).

## The Bottom Line

At 64 nodes, BGP unnumbered with loopback peering isn't a nice-to-have — it's how you stay sane. You're eliminating hundreds of IP addresses, simplifying your templates, and making Day 2 operations actually manageable.

Less infrastructure to maintain. Less documentation to keep current. Less surface area for human error.

Sometimes the best engineering is removing things.

---

*Working on the Azure Local 64-node architecture? Check out the [network switch knowledgebase](https://github.com/microsoft/network-switch-knowledgebase) for Dell OS10 and Cisco NX-OS configuration guides.*

<!-- 
DRAFT NOTES:
- [ ] Add actual lab screenshots/outputs
- [ ] Include show command verification examples  
- [ ] Get specific numbers from 64-node deployment
- [ ] Add diagram (spine-leaf with loopback IPs only, no link IPs)
- [ ] Review with Mike for technical accuracy
- [ ] Consider adding NX-OS unnumbered config example
- [ ] Reference Azure Local specific requirements
-->
