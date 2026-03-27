---
layout: post
title: "EVPN and VRFs: The Security Architecture Your Data Center Actually Needs"
date: 2026-03-27 13:00:00 -0700
categories: [networking]
tags: [evpn, vrf, vxlan, azure-local, security, data-center, hyper-v, dell-os10, cisco]
author: ebmarquez
description: "How EVPN with VRF isolation extends from the physical fabric to the Windows Hyper-V virtual switch — and why it's a real security upgrade over VLANs."
image:
  path: https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=1200&q=80
  alt: "Abstract digital security visualization — representing layered network isolation from fabric to virtual machine"
---

*Part 2 of a series on network isolation in modern data centers — read [Part 1: What Are VRFs and How They Work](/posts/what-are-vrfs-and-how-they-work/) first if VRFs are new to you.*

---

If you've been running multi-tenant workloads on traditional VLANs and feeling pretty good about your "isolation," I've got some uncomfortable news. VLANs were designed for traffic management, not security boundaries. They're the drywall between hotel rooms — technically separating spaces, but one determined guest with a drill changes everything.

EVPN with VRF-based isolation is the concrete wall upgrade. And if you're running Azure Local (formerly Azure Stack HCI), the way this integrates with the Windows Hyper-V virtual switch is genuinely elegant — once you understand the full stack.

I've been building these architectures at scale using Dell S5248F-ON leaf switches with VXLAN/EVPN overlay, Cisco C9336C-FX3 border/spine switches, and Windows Server hosts running Hyper-V with Switch Embedded Teaming (SET). Here's how it all connects and why it matters for security.

---

## What Are EVPN and VRFs? (The 60-Second Version)

**VRF (Virtual Routing and Forwarding)** is essentially multiple independent routing tables on the same physical switch. Think of it like running several completely separate routers inside one box. Traffic in VRF-A has zero visibility into VRF-B's routing table. They don't know each other exists. It's not a filter or an ACL — it's a fundamentally separate forwarding plane.

**EVPN (Ethernet VPN)** is the control plane that makes VRFs work across your entire fabric. It's a BGP address family (L2VPN EVPN) that distributes MAC addresses, IP addresses, and VRF membership information between switches. Instead of flooding unknown traffic everywhere like traditional Layer 2, EVPN learns exactly where every endpoint lives and builds precise forwarding entries.

**VXLAN** is the data plane — the tunnel that carries isolated traffic between switches across a shared IP underlay. Each tenant segment gets a unique VNI (VXLAN Network Identifier), which maps to a VLAN locally on each switch.

Put them together: EVPN tells your fabric *where* things are and *who* they belong to. VRFs enforce *isolation* between tenants. VXLAN *carries* the traffic. Three layers, one architecture, actual security.

---

## Why VRFs Are a Security Upgrade Over VLANs

Here's where network engineers sometimes push back: "I already have VLANs separating my tenants. How is this different?"

It's different in ways that matter when you're defending against lateral movement:

### 1. Routing Table Isolation (Not Just L2 Segmentation)

A VLAN is a Layer 2 broadcast domain. A VRF is a Layer 3 routing instance. VLANs share the same routing table — if something goes wrong (misconfigured trunk, VLAN hopping, a rogue device), traffic can leak between segments because the router *knows about all of them*.

With VRFs, the routing table for tenant A literally doesn't contain routes for tenant B. You can't route to what doesn't exist in your forwarding table. It's isolation by architecture, not by policy.

### 2. Control Plane Precision

EVPN uses BGP to distribute MAC/IP bindings with route targets (RTs) that scope advertisements to specific VRFs. When a switch learns a new MAC address in VRF `AZLOCAL`, it advertises that binding with a route target like `10201:10201`. Only switches importing that RT will install the route.

Compare this to traditional flooding: broadcast a frame, every switch in the VLAN sees it, every host in the VLAN processes it. EVPN replaces this with targeted, control-plane-driven forwarding. Less broadcast traffic, less attack surface.

### 3. No More VRRP Sprawl

Traditional HA gateway designs (VRRP/HSRP) require multiple IPs per VLAN per switch — a virtual IP, plus unique self-IPs on each peer. In a fabric with dozens of VLANs, that's a lot of exposed IPs, each one a potential target.

EVPN anycast gateway eliminates all of this:

```
Traditional VRRP:                    EVPN Anycast Gateway:
  .1 = VRRP VIP (shared)              .1 = Anycast GW (ALL leaves)
  .2 = TOR1 self-IP (unique)          No self-IPs needed
  .3 = TOR2 self-IP (unique)          No VRRP, no VRIDs
  3 IPs consumed per VLAN             1 IP consumed per VLAN
```

Every leaf switch in the fabric advertises the **same gateway IP and MAC** (`00:01:01:01:01:01` in our deployment). Hosts always route to the nearest leaf. No VRRP state to attack, no self-IPs to probe, no gratuitous ARP storms during failover.

### 4. MAC/IP Binding Enforcement

EVPN Type-2 routes bind MAC addresses to IP addresses at the control plane level. The fabric knows that MAC `aa:bb:cc:dd:ee:ff` belongs to IP `100.78.108.50` on VNI `10201`, reachable via VTEP `100.71.93.148`. Spoofing becomes significantly harder when the fabric maintains authoritative bindings distributed via BGP.

---

## The Architecture: Spine-Leaf with VXLAN/EVPN

Here's the physical topology I'm working with — a single-rack Azure Local deployment that scales to multi-rack:

```
              ┌──────────────────────────────────────┐
              │     Border/Spine Rack                 │
              │  ┌───────────────┐ ┌───────────────┐ │
              │  │  Border-1     │ │  Border-2     │ │
              │  │  C9336C-FX3   │ │  C9336C-FX3   │ │
              │  │  ASN 64841    │ │  ASN 64841    │ │
              │  └───────┬───────┘ └───────┬───────┘ │
              └──────────┼─────────────────┼─────────┘
                         │  eBGP           │  eBGP
                         │  unnumbered     │  unnumbered
              ┌──────────┼─────────────────┼─────────┐
              │  ┌───────┴───────┐ ┌───────┴───────┐ │
              │  │  TOR1 (Leaf)  │ │  TOR2 (Leaf)  │ │
              │  │  S5248F-ON    │ │  S5248F-ON    │ │
              │  │  ASN 64789    │ │  ASN 64789    │ │
              │  │  VLT Pair     ├─┤  VLT Pair     │ │
              │  └───────┬───────┘ └───────┬───────┘ │
              │          │                 │         │
              │     ┌────┴─────────────────┴────┐    │
              │     │     20 Azure Local Nodes  │    │
              │     │  Card1 A→TOR1  B→TOR2     │    │
              │     │  Card2 A→TOR1  B→TOR2     │    │
              │     │  (SET trunk)  (Cluster)    │    │
              │     └───────────────────────────┘    │
              │              Compute Rack             │
              └──────────────────────────────────────┘
```

**Key design elements:**

- **eBGP unnumbered** between leaves and spines — no IP addresses to manage on fabric links, no numbered /30s to track
- **Dual-loopback model** — Loopback0 is the shared VTEP IP (same on both VLT peers: `100.71.93.148/32`), Loopback1 is the unique BGP router-ID (`100.71.93.149/32` and `.150/32`)
- **VLT between TOR peers** — presents a single logical switch to the hosts while maintaining independent BGP sessions
- **EVPN overlay sessions** ride loopback-to-loopback (`ebgp-multihop 2`) to the border switches for route exchange

### VNI-to-VLAN Mapping

Each VLAN maps to a unique VXLAN Network Identifier. Traffic entering a leaf switch on VLAN 201 gets encapsulated with VNI 10201 before traversing the fabric:

| VLAN | VNI   | Purpose          | Subnet          | Anycast GW     |
|------|-------|------------------|-----------------|----------------|
| 7    | 10007 | Infrastructure   | 100.68.12.0/24  | 100.68.12.1    |
| 6    | 10006 | HNVPA            | 100.71.189.0/24 | 100.71.189.1   |
| 201  | 10201 | Tenant           | 100.78.108.0/23 | 100.78.108.1   |
| 301  | 10301 | Logical Tenant   | 100.78.110.0/23 | 100.78.110.1   |
| 500  | 10500 | L3 Forwarding    | 100.68.13.0/24  | 100.68.13.1    |
| 600  | 10600 | Public VIP       | 100.64.72.0/23  | 100.64.72.1    |
| 650  | 10650 | GRE              | 100.76.34.0/25  | 100.76.34.1    |
| 711  | 10711 | Cluster Path 1   | 10.71.1.0/24    | 10.71.1.1      |
| 712  | 10712 | Cluster Path 2   | 10.71.2.0/24    | 10.71.2.1      |

All VNIs for tenant-facing traffic live inside VRF `AZLOCAL`. The cluster VNIs (711/712) can stay in the default VRF or be placed in their own — they're isolated by design since cluster ports are dedicated access ports, not trunked.

### Manual EVI: The Cisco Interop Tax

When your leaves are Dell and your spines are Cisco, auto-EVI won't cut it. You need manual EVI configuration with explicit Route Distinguishers and Route Targets:

```
evpn
  evi 10201
    rd 100.71.93.149:10201
    route-target both 10201:10201
```

Each EVI maps 1:1 to a VNI. The RD uses the leaf's unique router-ID (Loopback1) to ensure uniqueness across the fabric. The RT (`10201:10201`) controls which switches import/export routes for that segment. This is where VRF isolation is actually *enforced* at the control plane — only switches configured to import RT `10201:10201` will have reachability to that segment.

---

## Where Windows Virtual Switch Enters the Picture

Here's the part that makes Azure Local interesting: the isolation model doesn't stop at the physical switch. It extends into the host through the **Hyper-V Virtual Switch** running in **Switch Embedded Teaming (SET)** mode.

### How the Host Connects

Each Azure Local node has three NIC cards with specific roles:

| Card | Function | Connection | Teaming |
|------|----------|------------|---------|
| Card 1 (OCP) | Compute + Management | Port A → TOR1, Port B → TOR2 (trunk) | Windows SET |
| Card 2 (PCIe) | Cluster | Port A → TOR1 (VLAN 711), Port B → TOR2 (VLAN 712) | None (dedicated) |
| Card 3 | Storage (FC/iSCSI/PowerFlex) | Fabric A + B | MPIO |

**Card 1** is where the magic happens for workload isolation. Both ports connect as trunks carrying the management VLAN (native, untagged) plus all compute VLANs (6, 201, 301, 500, 600, 650). The Windows SET virtual switch bonds these two physical NICs into one logical uplink.

### The SET Virtual Switch: Bridge Between Physical and Virtual

The Hyper-V virtual switch in SET mode does something clever — it presents a single virtual switch to the OS and VMs while load-balancing traffic across both physical NICs connected to different TOR switches. If TOR1 goes down, all traffic flows through TOR2 seamlessly.

But here's the security-relevant part: **the virtual switch enforces VLAN tagging on VM traffic**. When you create a VM network adapter and assign it to VLAN 201, the virtual switch tags that traffic with 802.1Q VLAN 201 before it hits the physical NIC. The TOR switch only allows VLANs explicitly configured in the trunk allowed list.

The isolation chain looks like this:

```
VM (VLAN 201) → vSwitch tags 802.1Q → Physical NIC → TOR Switch
    → VLAN 201 → VNI 10201 → VXLAN tunnel → VRF AZLOCAL
```

At every hop, the traffic is constrained:
1. **Virtual switch** — only configured VLANs are permitted on VM adapters
2. **Physical NIC** — SET trunk carries only allowed VLANs
3. **TOR switch port** — trunk allowed list restricts to VLANs 6,7,201,301,500,600,650
4. **VXLAN encapsulation** — maps to specific VNI
5. **VRF** — routing table isolation in the fabric
6. **EVPN RT** — control plane scoping of route advertisements

A VM on VLAN 201 can't reach VLAN 301 resources unless the VRF is explicitly configured to route between those VNIs. And even then, you can apply route-map policies at the VRF level for granular control.

### Cluster Isolation: Belt and Suspenders

The cluster network (Card 2) takes isolation further. These ports are **dedicated access ports** — not trunked, not teamed. Port A on every node connects to TOR1 on VLAN 711, Port B connects to TOR2 on VLAN 712. Two completely separate Layer 2 domains for cluster heartbeat and CSV (Cluster Shared Volume) traffic.

Why two separate VLANs instead of one? Fault isolation. If VLAN 711 has an issue, cluster traffic still flows on VLAN 712. Each path is independently monitorable. And because these are access ports (not trunks), there's no VLAN tag manipulation possible — the switch assigns the VLAN, period.

QoS on these ports prioritizes what matters:

| Priority | Traffic | Bandwidth | Why |
|----------|---------|-----------|-----|
| 3 | SMB (CSV + Live Migration) | 50% | Storage I/O can't be starved |
| 7 | Cluster Heartbeat | 1% | Small packets, but must never drop |
| 0 | Everything else | 49% | Default bucket |

No PFC, no ECN needed here — this is TCP-based traffic (not RoCE/RDMA), so standard TCP retransmission handles occasional drops just fine.

---

## What This Means for Multi-Tenant Security

When you combine EVPN/VRF on the physical fabric with Windows virtual switch enforcement, you get defense in depth that traditional VLAN designs simply can't match:

**1. No single point of policy enforcement.** Isolation is enforced at the VM, the virtual switch, the physical switch port, the VXLAN encapsulation, and the VRF. Compromising one layer doesn't compromise the others.

**2. Control plane integrity.** EVPN distributes MAC/IP bindings via BGP with cryptographic session establishment (MD5/TCP-AO). Route targets ensure advertisements stay within their VRF scope. This isn't broadcast-based discovery — it's deterministic, verifiable forwarding.

**3. Reduced blast radius.** In a VLAN-only design, a compromised host in VLAN 201 can ARP scan the entire broadcast domain. With EVPN, the switch only has forwarding entries for endpoints it learned via BGP. Unknown unicast flooding is suppressed by default — the fabric won't forward traffic to destinations it hasn't learned.

**4. Scalable isolation.** VLANs cap out at 4094. VNIs go to 16 million. VRFs scale with your routing table capacity. When you need to add a new tenant, it's a VNI mapping and an RT import — not a prayer that your VLAN ID space hasn't been exhausted.

**5. Consistent policy from edge to edge.** The same VRF that isolates traffic on the leaf switch is the same VRF context applied in the spine. The anycast gateway means every leaf looks identical to hosts. There's no asymmetry in the forwarding path to exploit.

---

## Practical Takeaways for Network Engineers

If you're designing multi-tenant environments on Azure Local (or any VXLAN/EVPN fabric), here's what I'd prioritize:

**Start with VRF design, not VLAN design.** Think about your isolation domains first. Which workloads need to talk to each other? Which absolutely must not? Map VRFs to business requirements, then map VNIs and VLANs to VRFs.

**Use anycast gateway everywhere.** If you're still running VRRP or HSRP on your leaf switches, you're carrying unnecessary complexity and attack surface. Anycast gateway is simpler, faster (no failover delay), and more secure (no self-IPs to probe).

**Manual EVI for multi-vendor fabrics.** If your leaves and spines are from different vendors (Dell + Cisco, for example), don't trust auto-EVI. Explicit RD/RT configuration is more work upfront but eliminates interop surprises.

**Don't forget the host layer.** The best fabric security means nothing if the virtual switch is misconfigured. Ensure trunk allowed lists match between the physical switch and the SET virtual switch config. Audit VM VLAN assignments against your VRF design.

**Separate cluster traffic physically.** Dedicated NICs on dedicated access ports with dedicated VLANs. No trunking, no teaming. Cluster heartbeat and storage replication are the nervous system of your cluster — don't share that nervous system with tenant traffic.

**Document your VNI-to-VLAN-to-VRF mapping.** This is your source of truth. When something breaks at 2 AM, you need to trace from a VM's VLAN tag through the VNI to the VRF and out to the RT. Make that path obvious.

---

## Wrapping Up

EVPN with VRF isolation isn't just a networking upgrade — it's a security architecture. When you pair it with the Windows Hyper-V virtual switch in SET mode, you get isolation that runs from the VM all the way through the physical fabric, enforced at every layer.

Traditional VLANs gave us segmentation. EVPN/VRF gives us isolation. There's a meaningful difference, and if you're running multi-tenant workloads on Azure Local, that difference is worth the migration effort.

The best part? Once the fabric is built, adding new tenants is clean and repeatable — a VNI mapping, an EVI, a route target, and a VLAN on the virtual switch. No VRRP groups to configure, no IP addresses to allocate per switch, no broadcast domains to worry about flooding.

Build the foundation right, and the rest is configuration management.

---

*This is Part 2 of a series on network isolation. Read [Part 1: What Are VRFs and How They Work](/posts/what-are-vrfs-and-how-they-work/) if you haven't already.*

*This post is based on production architecture work with Azure Local single-rack and multi-rack deployments. The configurations shown use Dell OS10 on S5248F-ON leaf switches and Cisco NX-OS/IOS-XE on C9336C-FX3 border/spine switches. Your mileage may vary with different vendors, but the EVPN/VRF principles are universal.*
