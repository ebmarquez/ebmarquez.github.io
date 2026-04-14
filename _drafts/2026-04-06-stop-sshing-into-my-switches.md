---
layout: post
title: "Stop SSHing Into My Switches"
date: 2026-04-06 12:00:00 -0700
categories: [networking, ai]
tags: [sonic, gnmi, telemetry, grpc, openconfig, networking, data-center]
author: ebmarquez
description: "Dell SONiC ships with gNMI telemetry running out of the box on port 8080. Here's what that means for how you monitor your fabric — and why SSH was never meant for this job."
image:
  path: https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=1200&q=80
  alt: "Abstract digital network visualization with glowing blue connections"
---

*This is Part 3 of a series about deploying SONiC switches with AI assistance. [Part 1](/posts/hey-copilot-can-you-ssh-into-a-switch/) covered discovery — pointing Copilot at two factory-blank Dell S5248F-ON switches. [Part 2](/posts/heres-a-25-figure-out-the-address-plan/) covered IP addressing and BGP. Now we monitor the thing.*

---

Picture this: you've built a beautiful little two-switch iBGP fabric. BGP sessions are up, routes are being exchanged, life is good. And then someone — maybe a monitoring tool, maybe a well-intentioned script, maybe past-you — opens an SSH session to one of the switches and just... leaves it there. Polling `show interfaces` every 30 seconds. Parsing text output like it's 2004.

Then you try to SSH in to check something.

Denied. Session limit reached.

Congratulations, your monitoring tool has locked you out of your own switch. This is not a hypothetical. This happened. And it's the most preventable kind of pain, because Dell Enterprise SONiC ships with a proper telemetry solution already running — on port 8080, right now, waiting for you to notice it.

Let me tell you about gNMI.

---

## SSH Is Not a Monitoring Protocol

This feels obvious in retrospect, but it took getting locked out of a switch to really drive it home.

SSH was designed for interactive administration. It's great for that. You connect, you type commands, you get answers, you disconnect. The problem is that it holds a *session* — a shell process on the switch, a connection counted against a hard limit. Dell SONiC switches aren't servers with 256 concurrent sessions available. Depending on the platform, you might have two or three SSH sessions maximum before new connections start getting refused.

Now imagine a monitoring tool that opens an SSH session, runs `show interface status`, parses the ASCII table output, closes the connection — and does this every 30 seconds for every interface, across multiple switches. You've just created:

- **Session churn** — constant connect/disconnect cycles that stress the switch's SSH daemon
- **Text parsing fragility** — one firmware update changes the column widths and your monitoring breaks
- **Admin lockout risk** — if the tool holds sessions open or hits the limit during a polling cycle, you're locked out right when you most want to be in

The comparison table from the gNMI spec makes this stark:

| | gNMI | RESTCONF | SSH/CLI |
|---|---|---|---|
| **Streaming** | ✅ Native | ❌ Polling only | ❌ Screen scraping |
| **Concurrent sessions** | Many (multiplexed on one TCP) | Many (HTTP pooling) | **Limited (often 1-2)** |
| **Admin lockout risk** | None | None | **High** |
| **Data format** | Structured protobuf/JSON | Structured JSON | Unstructured text |

There's a better way. It's been running on your SONiC switch this whole time.

---

## What Even Is gNMI?

**gNMI** — gRPC Network Management Interface — is a network management protocol from the OpenConfig project. It uses gRPC (Google Remote Procedure Call) over HTTP/2 for both configuration and telemetry. Think of it as the modern, purpose-built replacement for SNMP that doesn't require you to hate your life.

The key properties:

- **Transport:** gRPC over HTTP/2 — binary framing, multiplexed streams, persistent connections
- **Encoding:** Protobuf (binary wire format) with JSON_IETF for the actual data payloads
- **Data model:** OpenConfig YANG — a vendor-neutral, tree-structured schema for network state
- **Auth:** Username/password via gRPC metadata headers (simple, no SNMP community strings)

On Dell Enterprise SONiC, gNMI runs as the `telemetry` process:

```bash
$ ps aux | grep telemetry
root  34778  /usr/sbin/telemetry -logtostderr --port 8080 ...
```

Port 8080, plaintext gRPC, no TLS, no extra configuration required. It's just there. I found it by accident while exploring what processes were listening on the switch. That accidental discovery fundamentally changed how I thought about monitoring this fabric.

---

## The Four RPCs (But Really You Want One of Them)

gNMI defines four operations — RPCs in gRPC terminology:

**Capabilities** — "What do you support?" Returns the YANG models and encodings the device understands. Useful for discovery, rarely needed in day-to-day operation.

**Get** — "Give me this data, right now." A stateless, one-shot query. Send a list of OpenConfig paths, get back the current state. Similar to a RESTCONF GET but over gRPC. Good for on-demand queries: what firmware are you running, what's your hostname, what's your HwSKU.

**Set** — "Change this config." The gNMI way to push configuration changes. We're not using this for monitoring, but it's how gNMI can eventually replace CLI-driven config management.

**Subscribe** — ⭐ This one. This is the whole point.

Subscribe is a bidirectional streaming RPC. You send a `SubscribeRequest` with a list of OpenConfig paths and subscription modes. The switch starts pushing `SubscribeResponse` messages containing data updates — and keeps pushing them, forever, until you disconnect. One persistent HTTP/2 connection. Multiple paths. Real-time data.

This is the architecture SSH can never replicate.

---

## The Subscribe Modes (This Is Where It Gets Good)

Subscribe isn't just "stream everything constantly." It gives you fine-grained control over *how* each path is delivered:

**`ON_CHANGE`** — Only send an update when the value actually changes. This is perfect for state-driven data like BGP session status or interface operational state. Your monitoring system gets notified the instant a BGP neighbor goes from `ESTABLISHED` to `IDLE`. Not on the next polling cycle — *the instant it happens*.

**`SAMPLE`** — Send an update at a fixed interval regardless of whether the value changed. Perfect for counters and utilization metrics. Interface traffic, CPU utilization, memory usage — things you want to graph over time.

**`TARGET_DEFINED`** — Let the device decide which mode makes more sense. Useful for system state paths where you don't care about the specifics.

Here's how our subscription configuration looks in practice:

```typescript
const STREAM_SUBSCRIPTIONS = [
  // BGP neighbor state — push immediately on any state change
  {
    path: '/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=bgp]/bgp/neighbors',
    mode: 'ON_CHANGE'
  },

  // Interface operational state — push on link flap
  {
    path: '/interfaces/interface/state',
    mode: 'ON_CHANGE'
  },

  // Interface counters — sample every 10 seconds
  {
    path: '/interfaces/interface/state/counters',
    mode: 'SAMPLE',
    sampleInterval: 10_000_000_000  // nanoseconds!
  },

  // CPU utilization — sample every 15 seconds
  {
    path: '/system/cpus/cpu[index=ALL]/state',
    mode: 'SAMPLE',
    sampleInterval: 15_000_000_000
  },

  // Memory utilization — sample every 15 seconds
  {
    path: '/system/memory/state',
    mode: 'SAMPLE',
    sampleInterval: 15_000_000_000
  },
];
```

You probably noticed `sampleInterval: 10_000_000_000` for a 10-second interval. That's not a typo. We'll get to that.

---

## The HTTP/2 Advantage

gRPC runs over HTTP/2, and that matters more than it sounds. HTTP/2 supports *multiplexed streams* on a single TCP connection — meaning you can have multiple concurrent RPCs (a Subscribe stream, a Get request, another Get request) all running simultaneously on one connection without blocking each other.

For monitoring two switches, the connection model looks like this:

```
Dashboard ──── single TCP connection ────► ToR Switch (:8080)
                    │
                    ├─ HTTP/2 stream 1: Subscribe RPC (stays open forever)
                    │   ├─ client → server: SubscribeRequest (paths + modes)
                    │   ├─ server → client: Notification (BGP state)
                    │   ├─ server → client: Notification (CPU sample)
                    │   ├─ server → client: Notification (counter sample)
                    │   └─ ... ongoing stream
                    │
                    └─ HTTP/2 stream 3: Get RPC (concurrent, on-demand)
                        ├─ client → server: GetRequest (platform info)
                        └─ server → client: GetResponse
```

One TCP connection per switch handles everything. The switch's `telemetry` process manages this completely independently from the SSH/CLI session manager. You're not competing with admins for sessions. You're not touching the session limit at all.

---

## Connecting to gNMI From Node.js

The gNMI proto definition lives at [openconfig/gnmi](https://github.com/openconfig/gnmi). Once you have that, connecting from Node.js with `@grpc/grpc-js` is straightforward:

```typescript
import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';

// Load the gnmi.proto definition
const packageDefinition = protoLoader.loadSync('gnmi.proto', {
  keepCase: false,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});
const proto = grpc.loadPackageDefinition(packageDefinition);
const gnmiService = (proto as any).gnmi;

// Create insecure channel — Dell SONiC runs plaintext gRPC on port 8080
const client = new gnmiService.gNMI(
  '100.100.81.129:8080',
  grpc.credentials.createInsecure()
);

// Auth via metadata headers
const metadata = new grpc.Metadata();
metadata.add('username', 'admin');
metadata.add('password', 'your-switch-password');
```

`grpc.credentials.createInsecure()` — yes, it's plaintext. In a lab environment that's fine. In production you'd configure TLS on the switch and use proper certificates. For internal lab networks where you trust the L2 segment, plaintext avoids the certificate management overhead and gets you running immediately.

---

## OpenConfig Paths That Actually Work

The OpenConfig YANG tree is extensive, and not all of it is implemented on every device. Here are the paths we've validated on Dell Enterprise SONiC, and what they return:

**BGP Neighbors:**
```
/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=bgp]/bgp/neighbors
```
Returns all BGP neighbor state — peer AS, session state (`ESTABLISHED`, `IDLE`, `ACTIVE`, etc.), prefixes received/sent, established transitions, message counts. With `ON_CHANGE`, you get instant notification when a BGP session flaps. No polling lag, no "I wonder if that was transient" ambiguity.

**Interface State:**
```
/interfaces/interface/state
```
Returns `oper-status`, `admin-status`, speed, and MTU for all interfaces. `ON_CHANGE` gives you real-time link-flap detection. The moment Ethernet38 goes down, your dashboard knows.

**Interface Counters:**
```
/interfaces/interface/state/counters
```
In-octets, out-octets, unicast packets, errors, discards. Sampled at 10-second intervals, these are your traffic graphs. Convert octets-per-interval to bits-per-second and you have bandwidth utilization without any SNMP community strings.

**CPU Utilization:**
```
/system/cpus/cpu[index=ALL]/state
```
Returns per-CPU stats: user time, system time, idle time. We calculate `cpuPercent = (user + system) / (user + system + idle) * 100`. The `[index=ALL]` key gives you aggregate stats across all cores.

**Memory:**
```
/system/memory/state
```
Returns `physical` (total) and `used` in bytes. Simple, clean, no parsing required.

**System State (Get, not Subscribe):**
```
/system/state
```
Hostname, boot-time, current-datetime, switching-mode. Fetched once at startup via a Get RPC — this doesn't change frequently enough to warrant streaming.

---

## The Nanosecond Gotcha

I promised we'd get back to this:

```typescript
sampleInterval: 10_000_000_000  // 10 seconds
```

The `sampleInterval` field in a gNMI SubscriptionList is specified in **nanoseconds**. Not milliseconds. Not seconds. Nanoseconds.

10 seconds = 10,000,000,000 nanoseconds.

When we first wired this up, I set `sampleInterval: 10000` thinking I was setting 10 seconds (because everything else in the JS ecosystem is milliseconds). Instead I was requesting samples every 10 *microseconds*. The switch obliged, enthusiastically. Counter updates flooded in at rates that made the Node.js event loop very unhappy.

The fix is obvious once you know. The diagnosis was not fun. Put it in a constant:

```typescript
const NANOSECONDS_PER_SECOND = 1_000_000_000;
const TEN_SECONDS = 10 * NANOSECONDS_PER_SECOND;
```

Your future self will thank you.

---

## Parsing What Comes Back

gNMI Notifications have a specific structure you need to understand to extract data correctly:

```typescript
interface Notification {
  timestamp: string;    // nanoseconds since epoch
  prefix?: Path;        // common path prefix for all updates
  update: Update[];     // list of path+value pairs
}

interface Update {
  path: Path;           // relative path (combined with prefix for full path)
  val: {
    jsonIetfVal?: string;  // JSON string that needs parsing (most common on SONiC)
    stringVal?: string;
    intVal?: string;
    boolVal?: boolean;
  };
}
```

Two things trip people up here:

**1. The prefix+path combination.** Notifications use a `prefix` (common path prefix) plus per-update `path` (relative path). You must combine both to get the full OpenConfig path. If you only look at the update path, you'll misclassify events — a BGP update and an interface update might look similar if you're ignoring the prefix.

**2. `syncResponse`.** After you open a Subscribe stream, the switch sends a burst of Notifications representing the current state of everything you subscribed to. Then it sends `syncResponse: true`. This is your signal that you now have a complete snapshot of current state — everything after this is real-time changes. Don't show "streaming live data" in your UI until you've received `syncResponse`. Before that, you're in "initial state dump" mode.

```typescript
stream.on('data', (response) => {
  if (response.update) {
    // Parse the notification, extract updates
    processNotification(response.update);
  }
  if (response.syncResponse) {
    // Initial sync done — switch UI to "live" indicator
    setStreamingState(true);
  }
});
```

---

## Building the Pipeline: gNMI → SSE → Browser

gNMI is a server-side gRPC connection. Browsers don't speak gRPC natively. So the pipeline needs a bridge, and Server-Sent Events (SSE) is the right tool for this leg of the journey.

The architecture:

```
ToR A (:8080) ──gRPC── Next.js Server ──SSE──► Browser (React)
ToR B (:8080) ──gRPC──┘                        (Zustand store)
                │
                └── RESTCONF (:443) ──HTTPS── (on-demand only)
```

**On the server side:** A singleton `SubscriptionManager` opens gNMI streams to both switches at startup. When Notifications arrive, it parses them into typed events (`bgp-update`, `cpu-update`, `interface-update`, etc.) and forwards them to any connected SSE clients.

**The SSE endpoint** (`/api/stream`) is a long-lived HTTP response that keeps the connection open and writes events as they arrive:

```typescript
// Simplified SSE endpoint
export async function GET() {
  const stream = new ReadableStream({
    start(controller) {
      subscriptionManager.on('event', (event) => {
        const data = `data: ${JSON.stringify(event)}\n\n`;
        controller.enqueue(new TextEncoder().encode(data));
      });
    }
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    }
  });
}
```

**In the browser:** The `EventSource` API connects to `/api/stream` and gets automatic reconnection for free. Events feed into a Zustand store, which triggers React re-renders for the affected components only.

Why SSE instead of WebSockets? Because we only need server→client pushes. Browsers don't need to send data to the server asynchronously — when a user clicks "refresh," that's a regular REST API call. SSE is simpler, works through more proxies and firewalls, and the native `EventSource` API handles reconnection without any library code.

---

## RESTCONF as the Complement

gNMI streaming is great for live monitoring, but it's not the right tool for *every* query. RESTCONF (HTTPS to port 443 on Dell SONiC) fills the gaps:

- **Initial page load:** Fetch the complete current state without waiting for the first streaming update
- **On-demand refresh:** When a user clicks a refresh button, a stateless RESTCONF GET is simpler than temporarily adjusting subscription modes
- **Detail queries:** Some data is better fetched on-demand rather than streamed — hardware inventory, full route tables, specific neighbor details

Think of gNMI as your always-on monitoring stream and RESTCONF as your reference library. They complement each other. The streaming protocol handles the reactive "tell me when something changes" use case; the stateless protocol handles the imperative "tell me about this specific thing right now" use case.

---

## The 40/60 Reality Check

Here's the thing nobody tells you when you start with OpenConfig: it doesn't cover everything.

In our experience, OpenConfig YANG paths cover roughly **40% of what a production data center fabric actually needs**. The paths we've talked about in this post — BGP state, interface counters, CPU, memory — those work great. OpenConfig is excellent for the fundamentals.

The other **60%** requires vendor-native YANG models or just... not being available via gNMI at all. Specifically:

- **EVPN/VXLAN state** — BGP EVPN neighbor state, VNI membership, VTEP mappings
- **QoS and PFC** — Priority-based flow control counters (critical for RoCEv2/RDMA workloads)
- **MCLAG** — Multi-Chassis LAG status, keepalive state, consistency checker output
- **SONiC-specific tables** — APP_DB and STATE_DB entries that expose internal state not modeled in OpenConfig

For vendor-native paths, you use `origin: ''` (or omit origin) instead of `origin: 'openconfig'` in your path encoding, and navigate the vendor's YANG tree instead of the OpenConfig one. It's more work — you need to know the specific path structure — but it's still structured gNMI, still streaming, still not SSH.

The takeaway: OpenConfig gives you a solid, vendor-neutral foundation. Plan for native YANG extensions if you need the full picture.

---

## The SSH Tunnel Saga (And Why It's Gone)

One more thing worth sharing because it illustrates how these pieces fit together architecturally.

Our initial design for reaching the gNMI endpoints was... convoluted. The ToR switches' loopback addresses weren't reachable from the corporate network directly. BGP was up between the ToRs and the upstream spine switches, but the spines weren't advertising the point-to-point link networks. So you could reach the spines, but not the ToRs behind them.

The workaround was SSH tunnels — connect to a spine, tunnel through to the ToR. Fragile, slow, prone to authentication issues, and entirely defeating the purpose of building a clean programmatic monitoring system.

The actual fix was straightforward once we understood the problem: the spine BGP configuration needed `network` statements for the P2P link subnets under the correct address family. Once those routes were advertised, the ToR loopbacks were reachable directly from the corporate VPN — and the entire SSH tunnel layer was deleted. Three files removed, one config change on the spines, everything works.

The lesson: sometimes the obstacle to your elegant monitoring architecture is an upstream BGP config issue that has nothing to do with monitoring.

---

## What This Looks Like in Practice

The end result is a Next.js dashboard that maintains persistent gNMI streams to both Dell S5248F-ON switches. Here's what it can show, live, without a single SSH session:

- **BGP neighbor state** for all sessions — peer AS, session state, prefix counts — updating the instant anything changes
- **Interface operational status** across all ports — link state, speed — instant notification on flaps
- **Interface traffic counters** — in/out octets and packets, sampled every 10 seconds
- **CPU utilization** per switch, sampled every 15 seconds
- **Memory usage** per switch, sampled every 15 seconds
- **Network topology** with BGP state coloring — green for established, red for down

The whole thing runs on one TCP connection per switch. Admin SSH sessions are available whenever you need them. And when a BGP session drops at 2 AM, you find out immediately — not on the next polling cycle.

That's the promise of purpose-built telemetry protocols. They exist so you don't have to abuse SSH.

---

## Getting Started

If you have a Dell Enterprise SONiC switch and want to verify gNMI is available:

```bash
# From the switch CLI
show runningconfiguration all | grep -i telemetry

# Or check the process directly
ps aux | grep telemetry

# From your workstation — gnmic is a great CLI client
gnmic -a <switch-ip>:8080 --insecure -u admin -p <password> capabilities
```

The `gnmic` CLI tool (from Nokia, open-source) is excellent for exploration before you write any code. Use `gnmic get` to explore OpenConfig paths, `gnmic subscribe` to see streaming updates, and `gnmic capabilities` to see what YANG models the device supports.

Once you know the paths work, wiring them into Node.js with `@grpc/grpc-js` is a few hundred lines of TypeScript — and then you have real-time switch telemetry in your browser without touching SSH session limits.

---

## What's Next

The gNMI foundation is solid. What comes next:

- **Vendor-native YANG paths** for EVPN and QoS state — the other 60%
- **Historical metrics** — storing the time-series data in SQLite for trend analysis
- **gNMI Set** — pushing config changes via the same protocol we use for monitoring
- **LLDP neighbor discovery** — auto-building the topology instead of hardcoding it

There's also a deeper post waiting about the gap between OpenConfig's promise and production reality — where the standard models end and vendor extensions begin. That one has opinions.

For now: if you have SONiC switches, check port 8080. Something interesting is already running there.

---

*Posts in this series:*
- *[Part 1: Hey Copilot, Can You SSH Into a Switch?](/posts/hey-copilot-can-you-ssh-into-a-switch/)*
- *[Part 2: Here's a /26 — Figure Out the Address Plan](/posts/heres-a-25-figure-out-the-address-plan/)*
- *Part 3: Stop SSHing Into My Switches (you're here)*
