---
layout: post
title: "Understanding DCBX in Azure Local: Telemetry, Not Negotiation"
date: 2026-01-30 12:00:00 -0800
categories: [Azure, Networking]
tags: [azure-local, dcbx, rdma, storage-networking, roce]
author: ebmarquez
description: "DCBX appears in Azure Local's switch requirements, but its role differs from traditional data center deployments. Here's how Azure Local actually uses DCBX for environment validation."
image:
  path: /assets/img/dcbx-telemetry.jpg
  alt: "DCBX telemetry collection diagram"
---

During a recent conversation with a customer about an Azure Local deployment, we spent a bit of time discussing the DCBX configuration—specifically "willing" versus "not willing" modes and how hosts and switches negotiate Priority Flow Control settings.

The discussion revealed a common misconception: **DCBX appears in Azure Local's supported switch requirements, but it serves a different purpose than traditional data center deployments.**

Understanding this distinction is important for planning and troubleshooting Azure Local networks.

---

## Traditional DCBX: Active Negotiation

To understand how Azure Local differs, it helps to review how DCBX traditionally operates.

**DCBX (Data Center Bridging Exchange)** is a protocol built on LLDP (Link Layer Discovery Protocol) that negotiates lossless Ethernet settings between network endpoints. It handles three key functions:

- **Priority Flow Control (PFC)**: Determines which traffic classes receive lossless treatment
- **Enhanced Transmission Selection (ETS)**: Allocates bandwidth between traffic classes
- **Application Priority**: Maps applications to specific priority classes

In traditional deployments, DCBX enables the switch and host to **actively negotiate** these settings. Each endpoint advertises its configuration, and they agree on compatible settings.

DCBX operates in two modes:

| Mode            | Behavior                                                                         |
| --------------- | -------------------------------------------------------------------------------- |
| **Willing**     | The endpoint accepts settings advertised by its peer                             |
| **Not Willing** | The endpoint maintains its local configuration regardless of peer advertisements |

This negotiation capability allows networks to dynamically configure lossless settings across heterogeneous environments.

---

## Azure Local's Approach: DCBX as Telemetry

Azure Local uses DCBX differently. Rather than negotiating settings, Azure Local uses DCBX to collect telemetry from the switch. This telemetry allows Azure Local to **validate** that the switch is configured correctly for lossless Ethernet, rather than relying on negotiation to set those parameters.

When you see DCBX in Azure Local's switch requirements, it serves these purposes:

1. **Pre-deployment validation**: Verify switch configurations before deployment begins
2. **Environment health checks**: Confirm settings during updates and ongoing operations
3. **Configuration verification**: Ensure manual QoS settings are correctly applied

Azure Local reads DCBX information to validate that your switch is properly configured. It does not use DCBX to push or negotiate settings.

### How Environment Validation Works

During deployment validation, Azure Local's Environment Checker queries DCBX telemetry to answer questions such as:

- Is PFC enabled on the correct priority?
- Are ETS bandwidth allocations configured as expected?
- Do VLAN settings match requirements?

If the validation detects incorrect configurations, it sends an informational notification alerting the administrator to the potential issue. Importantly, **these notifications do not block deployment**—they serve as warnings that something may need attention. The network administrator remains responsible for reviewing these alerts and ensuring proper switch configuration.

---

## Why This Design Choice

Azure Local's approach reflects a deliberate design decision: **the Azure Local nodes are the source of truth.**

Azure Local relies on **Network ATC** (Automatic Traffic Classification) to automate and manage network configuration on the host side. The QoS values configured by Network ATC are static and do not change over time. This provides a consistent, predictable baseline that Azure Local expects the network infrastructure to support.

Rather than using DCBX to negotiate settings dynamically, Azure Local:

1. Configures static QoS settings on the nodes via Network ATC
2. Uses DCBX telemetry to verify the switch configuration aligns with those expected values
3. Alerts administrators when discrepancies are detected

This approach offers several advantages:

- **Predictable behavior**: Node configuration is static and consistent across the cluster
- **Clear responsibility**: Network ATC manages host settings; network teams configure switches to match
- **Simplified troubleshooting**: Static values mean fewer variables when diagnosing issues
- **Reduced complexity**: No need to manage negotiation states or worry about configuration drift

---

## Practical Implications

### Manual Switch Configuration Required

DCBX telemetry does not replace manual switch configuration. Your switches need to be configured to match the static QoS values that Network ATC applies on the Azure Local nodes:

- Enable PFC on the appropriate priority (typically priority 3 for SMB Direct)
- Configure ETS bandwidth allocation for storage traffic
- Set up correct VLANs for storage networks
- Follow your switch vendor's DCB/lossless configuration guidelines

The goal is alignment: your switch configuration should support what Network ATC has configured on the nodes.

### Validation, Not Configuration

Pre-deployment checks identify misconfigurations and notify administrators, but they do not block deployment or correct issues automatically. If Environment Checker reports a DCBX telemetry alert, the resolution is to review and correct the switch configuration as needed.

### "Willing" Mode Is Not Relevant

Since Azure Local uses DCBX for reading telemetry rather than negotiation, the traditional "willing versus not willing" configuration choice does not affect Azure Local's behavior. Configure your switch according to your vendor's recommendations; Azure Local will read the result.

---

## Common Misconceptions

**Misconception**: DCBX handles QoS negotiation in Azure Local  
**Reality**: Azure Local reads DCBX telemetry; it does not negotiate settings

**Misconception**: Setting "willing" mode allows Azure Local to configure switch settings  
**Reality**: Azure Local does not push settings via DCBX regardless of mode

**Misconception**: DCBX negotiation failures cause storage traffic issues  
**Reality**: DCBX telemetry affects validation reporting, not traffic flow

**Misconception**: Manual QoS configuration is optional because DCBX will handle it  
**Reality**: Manual switch configuration is required; DCBX only validates what you configure

---

## Summary

| Aspect             | Traditional DCBX                 | Azure Local DCBX                                            |
| ------------------ | -------------------------------- | ----------------------------------------------------------- |
| **Purpose**        | Negotiate lossless settings      | Collect telemetry for validation                            |
| **Direction**      | Bidirectional negotiation        | Read-only from switch                                       |
| **Configuration**  | Can be dynamic via negotiation   | Static on nodes (Network ATC); switches configured to match |
| **"Willing" mode** | Determines negotiation behavior  | Not relevant to Azure Local                                 |
| **Failure impact** | May affect traffic configuration | Generates informational alerts only                         |

DCBX in Azure Local serves as a validation mechanism that confirms your switch configuration aligns with the static QoS settings on the nodes. Network ATC manages the host-side configuration; your responsibility is ensuring the switch infrastructure supports those requirements.

---

## Additional Resources

- [Azure Local Network Requirements](https://learn.microsoft.com/en-us/azure/azure-local/plan/cloud-deployment-network-considerations)
- [Overview of Data Center Bridging](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/overview-of-data-center-bridging)
- [Azure Local Baseline Reference Architecture](https://learn.microsoft.com/en-us/azure/architecture/hybrid/azure-local-baseline)
