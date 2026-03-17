---
layout: post
title: "Why Your Azure Local VMs Can't Talk Across Hosts: A VLAN Tagging Guide"
date: 2026-03-06 00:00:00 -0800
categories: [networking, azure-local]
tags: [azure-local, hyper-v, vlan, trunking, vswitch, sriov, netintent, vm-networking]
author: ebmarquez
description: "Azure Local tenant VMs in VLAN trunk mode work on one host but fail cross-host. Here's why Access mode with multiple vNICs is the correct pattern for tenant workloads."
image:
  path: /assets/img/azure-local-vm-vlan-tagging/01-physical-trunk-topology.png
  alt: "Diagram showing host-to-ToR trunk topology in an Azure Local cluster"
---

You've got a tenant VM on Azure Local that needs to talk on VLAN 4. You see the ToR switch port is a trunk carrying multiple VLANs, so you configure the VM NIC in trunk mode, set up a VLAN sub-interface inside the guest, and test. It works — but only when the other VM is on the same host. The moment you try to reach a VM on a different host, nothing. ARP requests leave, but replies never come back.

This keeps coming up, specifically with **tenant workloads**. In a typical Azure Local deployment, management traffic rides the native VLAN (untagged) and just works. But when customers need tenant VMs on tagged VLANs, they see those trunk ports on the ToR and assume the VM needs to do its own VLAN tagging. It doesn't — and that assumption is where things break.

Let's fix that mental model.

## The Physical Trunk — Quick Refresher

Before we touch virtualization, let's ground ourselves in how physical trunking works. If you already live in this world, skip ahead.

In a typical Azure Local deployment, each host connects to two Top-of-Rack (ToR) switches. These links carry **multiple VLANs** — management, storage, live migration, and tenant VM traffic all share the same physical interfaces. That means the switch ports must be **trunk ports**.

The important distinction: **management traffic uses the native VLAN** (untagged on the wire), while **tenant VLANs are tagged**. The switch handles both on the same trunk port — native VLAN for management, 802.1Q tags for everything else.

![Physical trunk topology showing hosts dual-homed to two ToR switches](/assets/img/azure-local-vm-vlan-tagging/01-physical-trunk-topology.png)
_Each host is dual-homed to two ToR switches. All host-facing ports are trunks carrying multiple VLANs._

The switch configuration looks like this:

```text
interface Ethernet1/1
  switchport mode trunk
  switchport trunk allowed vlan 7,4,10,20
  switchport trunk native vlan 7
  mtu 9216
  no shutdown
```

Key points:

- **Trunk mode** means the port sends and receives 802.1Q tagged frames
- **Allowed VLANs** restrict which VLANs can traverse this link
- **Native VLAN 7** is management — this traffic is untagged on the wire and just works
- **VLANs 4, 10, 20** are tenant VLANs — these are the tagged VLANs where the tagging question matters
- The host-to-switch link is always a trunk because multiple traffic types share it

This is where the confusion starts. Admins see "trunk" on the physical port and assume tenant VMs need trunk mode too. They don't.

## The Three Hyper-V VLAN Modes

Hyper-V gives you three ways to configure VLAN tagging on a VM's network adapter using `Set-VMNetworkAdapterVlan`. Each one determines **who is responsible for adding the VLAN tag** to the frame.

![Side-by-side comparison of three VLAN modes: Untagged, Access, and Trunk](/assets/img/azure-local-vm-vlan-tagging/02-three-vlan-modes.png)
_The three VLAN modes control where tagging happens — the key difference is who adds the 802.1Q header._

### Mode 1: Untagged (Default)

```powershell
Set-VMNetworkAdapterVlan -VMName 'myVM' -Untagged
```

The VM sends plain Ethernet frames. The vSwitch passes them through without modification. On the wire, they arrive at the switch **untagged**, and the switch assigns them to whatever native VLAN is configured on that trunk port.

This is how **management traffic** works on Azure Local — it rides the native VLAN without any VLAN configuration on the VM. For tenant workloads that need a specific VLAN, you need one of the next two modes.

### Mode 2: Access (Recommended for Azure Local)

```powershell
Set-VMNetworkAdapterVlan -VMName 'myVM' -Access -VlanId 4
```

The VM still sends plain Ethernet frames — it has no idea about VLANs. But the **vSwitch adds a VLAN 4 tag** to every outbound frame before sending it to the physical NIC. On the return path, the vSwitch strips the VLAN 4 tag before delivering the frame to the VM.

The VM thinks it's on a simple network. The vSwitch handles all the VLAN complexity.

> **Important:** The word "Access" here does **not** mean the physical switch port is in access mode. The physical port stays in trunk mode. "Access" refers to the VM's experience — it acts like it's connected to an access port, while the vSwitch translates between the VM's untagged world and the physical trunk's tagged world.

### Mode 3: Trunk (Breaks on Azure Local)

```powershell
Set-VMNetworkAdapterVlan -VMName 'myVM' -Trunk `
  -NativeVlanId 1 -AllowedVlanIdList '4'
```

The VM itself sends **802.1Q tagged frames**. Inside the guest OS, you configure a VLAN sub-interface (like `eth0.4` on Linux) that adds the tag. The vSwitch is supposed to pass these tagged frames straight through to the physical NIC.

- `-NativeVlanId 1` — untagged frames from the VM are treated as VLAN 1
- `-AllowedVlanIdList '4'` — only VLAN 4 tagged frames are allowed through

In theory, this is the virtual equivalent of plugging a router into a trunk port. In practice on Azure Local, **this is where things break**.

## The Two-Layer Model

The key to understanding this is recognizing that there are **two separate networking relationships**, with the vSwitch sitting in the middle:

1. **VM ↔ vSwitch** — a virtual relationship
2. **vSwitch ↔ Physical Switch** — a physical relationship

![Access mode traffic flow showing both outbound and return paths](/assets/img/azure-local-vm-vlan-tagging/03-access-mode-flow.png)
_In Access mode, the vSwitch manages all tagging. Both outbound and return paths work correctly._

In Access mode, this is clean:

- **Outbound:** VM sends an untagged frame → vSwitch adds VLAN 4 tag → frame goes out the physical NIC tagged → arrives at the ToR trunk port
- **Return:** ToR sends a VLAN 4 tagged frame → physical NIC receives it → vSwitch strips the tag → delivers a clean untagged frame to the VM

The vSwitch is the translator between these two worlds. The VM never sees tags. The switch always sees tags. Everyone is happy.

In Trunk mode, the VM tries to be its own translator — and that's where Azure Local's architecture gets in the way.

## Why Trunk Mode Breaks on Azure Local

On a standalone Hyper-V server, trunk mode on a VM NIC works fine. The vSwitch passes tagged frames between the VM and the physical NIC without interference. But Azure Local is not a standalone Hyper-V server. It adds several layers that fundamentally change how the vSwitch processes traffic.

![Trunk mode failure showing outbound success but return path failure at the vSwitch](/assets/img/azure-local-vm-vlan-tagging/04-trunk-mode-failure.png)
_In Trunk mode, outbound traffic works but return traffic is dropped at the vSwitch. ARP replies never make it back to the VM._

### SR-IOV Changes the Data Path

Azure Local enables **SR-IOV** (Single Root I/O Virtualization) on the vSwitch by default for performance. SR-IOV creates a hardware-accelerated path between VMs and the physical NIC, bypassing much of the vSwitch's software processing.

The SR-IOV hardware offload path is designed for the vSwitch to manage VLAN tagging — it expects **Access mode** behavior. When a VM in trunk mode injects its own 802.1Q tags, the hardware offload doesn't know how to handle tagged frames on the return path. The result: outbound traffic works (the tagged frame makes it to the switch), but **return traffic gets dropped** because the offload path can't correctly route tagged reply frames back to the trunk-mode VM.

### NetIntent Manages the vSwitch

Azure Local uses **NetIntent** to configure and manage the virtual switch. NetIntent sets up VLAN filtering rules, VMQ queues, and SR-IOV offload paths based on the network intents you define during cluster deployment.

When you manually configure a VM NIC in trunk mode using `Set-VMNetworkAdapterVlan`, you're operating **outside of what NetIntent knows about**. NetIntent's VLAN filtering tables may not include the VM-initiated tags, and the VMQ queue mappings won't account for trunk-mode traffic patterns.

### The Evidence

The failure pattern is consistent and diagnostic:

- ARP requests from the trunk-mode VM **reach** the remote host ✅
- ARP replies are **generated** by the remote host ✅
- ARP replies **never arrive back** at the trunk-mode VM ❌

This is a classic unidirectional return-path failure. The outbound path works because the vSwitch can passively forward a tagged frame. The return path fails because the vSwitch's optimized data plane (SR-IOV + NetIntent filtering) doesn't expect to deliver tagged frames to a VM.

This isn't a switch problem. The switch is doing its job correctly. It's a **vSwitch data plane constraint** on Azure Local.

## The Correct Pattern: Access Mode with Multiple vNICs

If your VM needs to communicate on multiple VLANs, the answer isn't trunk mode — it's **multiple virtual NICs, each in Access mode**.

![Recommended multi-vNIC pattern with each vNIC in Access mode on a different VLAN](/assets/img/azure-local-vm-vlan-tagging/05-multi-vnic-pattern.png)
_One vNIC per VLAN, each in Access mode. The vSwitch handles all tagging, and the guest OS routing table determines traffic paths._

### PowerShell Configuration

```powershell
# Create a vNIC for each VLAN
Add-VMNetworkAdapter -VMName 'myVM' `
  -Name 'VLAN4' -SwitchName 'ConvergedSwitch'
Set-VMNetworkAdapterVlan -VMName 'myVM' `
  -VMNetworkAdapterName 'VLAN4' -Access -VlanId 4

Add-VMNetworkAdapter -VMName 'myVM' `
  -Name 'VLAN10' -SwitchName 'ConvergedSwitch'
Set-VMNetworkAdapterVlan -VMName 'myVM' `
  -VMNetworkAdapterName 'VLAN10' -Access -VlanId 10

Add-VMNetworkAdapter -VMName 'myVM' `
  -Name 'VLAN20' -SwitchName 'ConvergedSwitch'
Set-VMNetworkAdapterVlan -VMName 'myVM' `
  -VMNetworkAdapterName 'VLAN20' -Access -VlanId 20
```

### Guest OS Configuration

Inside the VM, each vNIC appears as a separate network interface. Configure IP addresses and routing normally:

```bash
# Linux example
ip addr add 10.240.1.100/24 dev eth0    # VLAN 4 (default gateway)
ip addr add 10.240.10.100/24 dev eth1   # VLAN 10
ip addr add 10.240.20.100/24 dev eth2   # VLAN 20

# Default route via VLAN 4
ip route add default via 10.240.1.1 dev eth0
```

No VLAN sub-interfaces needed. No guest-side VLAN awareness required. The vSwitch handles all the tagging, and the guest OS routing table determines which NIC — and therefore which VLAN — carries each traffic flow.

### Switch Configuration

The switch configuration doesn't change. The trunk port already allows all the VLANs you need:

```text
interface Ethernet1/1
  switchport mode trunk
  switchport trunk allowed vlan 7,4,10,20
  switchport trunk native vlan 7
  mtu 9216
  no shutdown
```

The switch sees tagged frames for VLANs 4, 10, and 20 arriving on the same trunk port. It doesn't know or care whether the vSwitch or the VM added those tags. The frames are properly tagged, and the switch forwards them correctly.

## Quick Reference

| Mode | VM Sees Tags? | Who Tags? | Switch Port | Works on Azure Local? |
| ------ | -------------- | ----------- | ------------- | ---------------------- |
| **Untagged** | No | Nobody — uses native VLAN | Trunk or Access | ✅ Yes |
| **Access** | No | vSwitch | Trunk | ✅ Yes (recommended) |
| **Trunk** | Yes | VM itself | Trunk | ❌ No — return path fails |

## The Takeaway

If your Azure Local VMs need to communicate on multiple VLANs, **don't use trunk mode on the VM NIC**. Instead:

1. Create **one vNIC per VLAN**, each configured in **Access mode**
2. Let the **vSwitch handle all VLAN tagging** — it's what SR-IOV and NetIntent are optimized for
3. Use **guest OS routing** to direct traffic to the appropriate interface

Trunk mode works on standalone Hyper-V where you fully control the vSwitch. On Azure Local, the combination of SR-IOV hardware offload, NetIntent management, and VMQ optimizations creates a data plane that expects the vSwitch to own VLAN tagging. When a VM tries to inject its own tags, the return path breaks.

This isn't a misconfiguration. It's a platform constraint. And once you understand the two-layer model — VM talks to vSwitch, vSwitch talks to physical switch — the correct pattern is obvious. Let the vSwitch do its job.
