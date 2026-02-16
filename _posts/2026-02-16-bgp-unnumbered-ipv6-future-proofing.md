---
layout: post
title: "Future-Proofing Your Fabric: How BGP Unnumbered Makes IPv6 a Config Change, Not a Redesign"
date: 2026-02-16 00:00:00 -0800
categories: [networking]
tags: [bgp, unnumbered, ipv6, dual-stack, rfc-5549, enhe, spine-leaf, data-center, future-proofing]
author: ebmarquez
description: "BGP unnumbered already uses IPv6 under the hood. Adding IPv6 routes to your fabric is activating one address family — not redesigning your network."
image:
  path: https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=1200&q=80
  alt: "Digital network connections illuminating a dark globe — representing the bridge between IPv4 and IPv6 in modern data center fabrics"
---

In [BGP Unnumbered: The Network Simplification You Didn't Know You Needed](/posts/bgp-unnumbered-network-simplification/), we killed the /31 spreadsheet. We talked about eliminating the IP address tax on fabric links and how link-local IPv6 makes BGP peering trivial.

But we glossed over something interesting.

**BGP unnumbered already uses IPv6 on every fabric link.** Every unnumbered session you're running right now has an IPv6 TCP connection. Every BGP OPEN happens over an IPv6 link-local address. And most engineers running it have no idea they're already halfway to full IPv6 support.

Here's the thing nobody tells you: adding IPv6 routes to your fabric isn't a redesign. It's activating one address family on a session that's already running over IPv6.

Let's talk about how this works, why it matters, and what it means for your IPv6 readiness.

## The IPv6 You Didn't Know You Were Running

Quick reminder from Part 1: BGP unnumbered uses **IPv6 link-local addresses** (fe80::/10) for neighbor discovery and TCP sessions.

When you configure `neighbor interface ethernet 1/1/49`, the switch:

- Finds the neighbor via IPv6 Neighbor Discovery (NDP)
- Establishes the BGP TCP session to fe80::something
- Exchanges routes

Most engineers mentally file this as "just the signaling mechanism" and move on. It's how the control plane works. It's not *real* IPv6. Right?

Wrong.

**The BGP TCP session itself is running over IPv6.** That's not a trick or a workaround — it's native IPv6 transport. And once you have that transport up, the only question left is: what routes do we exchange over it?

The answer is: **whatever address families you activate.**

## RFC 5549: The Bridge Between Two Worlds

Here's where it gets good.

Your fabric is carrying IPv4 routes today. Loopbacks, VTEPs, server subnets — all IPv4 prefixes. Those routes are being advertised over a BGP session that runs on IPv6. How does that work?

**RFC 5549: Extended Next-Hop Encoding (ENHE).**

During the BGP OPEN handshake, both peers negotiate capabilities. One of those capabilities is BGP Capability Code 5, which says: "I can accept IPv4 routes with an IPv6 next-hop."

Check the output from your switch:

```text
Capabilities received from neighbor for IPv4 Unicast:
  Multiproto_Ext(1)
  Route_Refresh(2)
  4_Octet_As(65)
  Extended Next Hop Encoding (5)    ← This is the magic
```

That last line is doing all the work.

Without ENHE, BGP assumes the next-hop address family matches the route's address family. IPv4 route? IPv4 next-hop. IPv6 route? IPv6 next-hop.

ENHE breaks that assumption.

It lets you advertise an **IPv4 prefix** (like 10.0.0.1/32) with an **IPv6 next-hop** (like fe80::a00:27ff:fe4e:66a1). That's how your fabric carries IPv4 routes over an IPv6-only session.

Here's the key insight: **the next-hop is really just answering one question: what MAC address do I put in the Ethernet frame?**

Whether you look up that MAC via IPv4 ARP or IPv6 Neighbor Discovery, you get the same answer — a 48-bit hardware address. The packet doesn't care how you found the mailbox. It just cares that the frame gets sent out the right interface with the right destination MAC.

ENHE is the translation layer. It's the adapter that lets your IPv4 data plane ride on an IPv6 control plane.

And because it's negotiated at session setup, it's completely transparent to the rest of the network. Your routing tables still show IPv4 prefixes. Your forwarding ASICs still forward IPv4 packets. The only thing that changed is how you resolved the next-hop MAC address.

## Adding IPv6 Is One Command Away

Here's where this gets practical.

ENHE was invented for the **cross-protocol case** — IPv4 routes with IPv6 next-hops. It's a workaround. A clever one, but still a workaround.

IPv6 routes with IPv6 next-hops? **That's just normal Multiprotocol BGP.** No translation. No capabilities negotiation beyond the standard MP-BGP extensions. It's native.

To add IPv6 route support to an existing unnumbered session, you literally just activate the address family:

```bash
# On Dell OS10 — add to existing unnumbered neighbor
router bgp 65001
  neighbor interface ethernet 1/1/49
    address-family ipv6 unicast
      activate
```

That's it.

Show your BGP session details, and you'll see both address families active on the same peer:

```text
For address family: IPv4 Unicast     ← Carried via ENHE (RFC 5549)
  Next hop set to self

For address family: IPv6 Unicast     ← Native — no translation needed
  Next hop set to self
```

The same single BGP session, over the same link-local peering, can now carry:

- **IPv4 unicast routes** (via ENHE)
- **IPv6 unicast routes** (natively)
- **L2VPN EVPN routes** (if you activate that AF too)

All on one session. All over the same unnumbered interface. No new IP addressing. No new peer config. Just `activate`.

Compare that to numbered BGP. If you built your fabric with /31s and IPv4-only peers, adding IPv6 means:

- Allocating new IPv6 /127s for every fabric link
- Configuring new IPv6 neighbor statements
- Establishing parallel BGP sessions
- Managing two separate peering topologies

You're essentially building a second fabric on top of the first one.

With BGP unnumbered, you're just turning on a feature that was already there.

## Your Loopback Stays IPv4 — And That's Fine

One question always comes up: "If I'm running IPv6, doesn't my Router-ID need to be IPv6?"

No.

**Router-ID is always 32-bit A.B.C.D format.** It's a BGP protocol requirement. Even OSPFv3 — which is an IPv6-only routing protocol — uses IPv4-format router IDs. It's just a unique identifier. It doesn't have to be routable. It doesn't even have to be a real IP address (though it should be, for sanity).

In practice, your loopback stays IPv4 because:

- VXLAN VTEP source addresses need to be IPv4
- Your monitoring, SSH, IPAM, and NTP are all anchored to an IPv4 loopback
- Every automation tool you have assumes there's an IPv4 management address

You **can** dual-stack the loopback if you want IPv6 reachability to the device itself:

```text
interface loopback0
  ip address 10.0.0.1/32
  ipv6 address 2001:db8::1/128
```

But that's optional. The practical design looks like this:

| Layer | Configuration |
| ----- | ------------- |
| **Fabric links** | No IPs (link-local only) |
| **Loopback0 (IPv4)** | 10.0.0.1/32 → Router-ID, VTEP, management |
| **Loopback0 (IPv6)** | 2001:db8::1/128 → Optional, for IPv6 device reachability |
| **BGP session** | fe80:: link-local transport |
| **Carries** | IPv4 + IPv6 + EVPN |

The loopback provides stability and identity. The fabric links provide transport. BGP exchanges the routes. Everything works.

## The Progression Nobody Plans But Everyone Needs

Here's the roadmap nobody talks about but everyone ends up following:

**Phase 1:** Deploy BGP unnumbered for operational simplicity. No more /31 spreadsheets. No more fat-fingered peer IPs at 2am. You get a clean, scalable underlay that just works.

**Phase 2:** Activate the IPv6 address family on your existing unnumbered sessions. One command per neighbor group. No new peerings. No new topology. Just `address-family ipv6 unicast; activate`.

**Phase 3:** Advertise IPv6 prefixes on your overlay networks. Tenant VLANs, server subnets, application endpoints — wherever your business needs IPv6, you redistribute it into BGP. The fabric carries it the same way it carries IPv4.

**Phase 4:** Go IPv6-primary when (or if) the business requires it. Maybe that's next year. Maybe it's five years from now. Either way, the fabric is ready. You're not scrambling to retrofit IPv6 support because it's already there.

The point: **each phase is additive.** No forklift. No re-architecture. No "migration project" with a Gantt chart and a steering committee. Just progressive activation of features on the same clean underlay.

This is what future-proofing actually looks like. Not predicting what you'll need in five years and over-engineering for it. Building a foundation that can adapt when requirements change.

BGP unnumbered is that foundation.

## The Trade-Offs

Let's be honest: this isn't perfect.

**Not all vendors support ENHE equally.** Test your firmware combinations before you commit. FRRouting/Cumulus and Dell OS10 have slightly different interpretations of how the IPv6 next-hop field should be encoded. Some vendors use the global IPv6 address as next-hop. Others use link-local-only. It usually works, but there are interop quirks.

**If you need IPv6-only** (no IPv4 at all), the loopback and VTEP story gets more complex. VXLAN historically expects IPv4 VTEP addressing. There are workarounds, but they're not standard. That's fine — most environments don't need IPv6-only. They need dual-stack, which is what this design gives you.

**This is about readiness, not migration.** You're not ripping out IPv4 and replacing it with IPv6. You're making it trivial to add IPv6 when your application teams, your security team, or your CIO finally says "we need this."

And when that day comes, you activate an address family and move on with your life.

## The Punchline

In Part 1, we removed the /31 spreadsheet. Today, we removed the excuse for not being IPv6-ready.

The hardest part of IPv6 adoption in the data center isn't the protocol. It's not the addressing plan. It's not even the training.

It's the **migration planning.** The project kickoff. The impact analysis. The parallel infrastructure. The cutover windows. The rollback plans. The "what if this breaks production" conversations that kill momentum before you even start.

BGP unnumbered eliminates the migration.

You're already running IPv6 on every fabric link. The session is up. The transport is there. The capability is negotiated. Adding IPv6 routes is activating one address family on infrastructure you deployed months ago.

It's not a project. It's a config change.

And that's the difference between being ready and being stuck.
