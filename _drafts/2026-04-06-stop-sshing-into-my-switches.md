---
layout: post
title: "Stop SSHing Into My Switches"
date: 2026-04-06
categories: [networking, ai]
tags: [sonic, gnmi, telemetry, grpc, openconfig, networking, data-center]
author: ebmarquez
image:
  path: https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=1200&q=80
  alt: "Glowing fiber optic strands representing real-time data streaming through a network"
---

There's a moment every network engineer eventually hits: you're trying to log in to a switch to debug something, and you get hit with "maximum sessions reached." Somewhere, a monitoring script has been squatting on your SSH sessions like a bad houseguest. The switch is fine — you just can't get in to prove it.

This happened to me with our Dell S5248F-ON switches running SONiC. The fix wasn't configuration tuning. It was rethinking the whole approach to monitoring. Enter **gNMI** — gRPC Network Management Interface — and the moment I discovered that Dell Enterprise SONiC ships it ready to go on port 8080, no extra setup required.

This is Post 3 in a series about deploying SONiC switches with AI assistance. [Post 1](/posts/hey-copilot-can-you-ssh-into-a-switch) covered initial discovery, [Post 2](/posts/heres-a-25-figure-out-the-address-plan) covered IP planning and BGP. This one is where we get into the telemetry architecture — and it's the most technically dense of the bunch. Grab a coffee.

---

## The SSH Problem Is Real

Let me be specific about what happened, because this is worth understanding before we get to solutions.

SONiC switches have a limited number of concurrent SSH sessions. On our S5248F-ON switches, that's a small number — on the order of one or two concurrent connections. When a monitoring process holds an SSH session open (polling `show` commands, parsing text output, doing it again in 30 seconds), it's occupying one of those slots permanently.

The moment you actually need to log in and do something — check a BGP flap, review interface errors, look at a log — you might find yourself locked out. The monitoring tool is "working," burning your admin access in the process.

Beyond the lockout problem, SSH-based monitoring is just fundamentally the wrong tool:

| Approach | Transport | Streaming | Session Cost | Data Format |
|---|---|---|---|---|
| SSH/CLI | SSH | ❌ Polling only | **High — holds shell session** | Unstructured text |
| SNMP | UDP | ⚠️ Traps only | Low | Structured but limited |
| RESTCONF | HTTPS | ❌ Polling only | Low | Structured JSON |
| **gNMI** | **gRPC/HTTP2** | **✅ Native streaming** | **None — separate process** | **Structured protobuf** |

gNMI's `telemetry` process on SONiC runs completely independently from the SSH/CLI session manager. It can handle multiple simultaneous subscribers without touching your admin session count. One persistent HTTP/2 connection to the switch carries everything.

That's the headline. Now let's talk about how it actually works.

---

## What is gNMI?

gNMI stands for **gRPC Network Management Interface**. It's a protocol defined by the [OpenConfig](https://www.openconfig.net/) consortium for network device management and telemetry. Under the hood, it's gRPC (Google Remote Procedure Call) running over HTTP/2, using protobuf for encoding.

If you've never worked with gRPC before: think of it as a framework for defining typed remote procedure calls, where the wire format is binary protobuf instead of text JSON. It's faster and more efficient than REST, and crucially, it supports **bidirectional streaming** — the server can push data to the client continuously, not just in response to requests.

### The Four RPCs

gNMI defines exactly four remote procedure calls in its `gnmi.proto` service definition:

**1. Capabilities** — Discovery. Ask the device what YANG models it supports, what encodings it can use, what gNMI version it's running. Always start here when connecting to a new device.

**2. Get** — One-shot read. Send a list of paths, get back the current state. Stateless, like a REST GET. Great for on-demand queries: "give me the current BGP neighbor table" or "what firmware version is this running?"

**3. Set** — Configuration push. Update, replace, or delete configuration subtrees. We're not using this yet (read-only for now), but this is how gNMI replaces Jinja2 templates + SSH config push.

**4. Subscribe** ⭐ — **This is the star.** A bidirectional streaming RPC where you send a list of paths and modes, and the server pushes state updates to you indefinitely. BGP session goes from ESTABLISHED to IDLE? You know immediately. Interface counter sampled every 10 seconds? It flows to you on schedule. The stream stays open on a single HTTP/2 connection.

### HTTP/2 and Why Multiplexing Matters

gRPC's use of HTTP/2 isn't just a transport detail — it's what makes the whole thing efficient at scale.

HTTP/2 multiplexes multiple logical streams over a single TCP connection. That means your dashboard can have a Subscribe stream for BGP state, a Subscribe stream for interface counters, and fire off an independent Get request for platform info — all over **one TCP connection** to the switch, with no blocking between them.

```
Dashboard ──── single TCP connection ────▶ ToR Switch (:8080)
               │
               ├── HTTP/2 stream 1: Subscribe RPC
               │     Client → Switch: subscribe(BGP neighbors, ON_CHANGE)
               │     Switch → Client: notification (BGP state changed) ← immediate
               │     Switch → Client: notification (counter sample) ← every 10s
               │     Switch → Client: ...  (stream stays open)
               │
               └── HTTP/2 stream 3: Get RPC (runs concurrently, doesn't block stream 1)
                     Client → Switch: get(platform info)
                     Switch → Client: GetResponse
```

Contrast this with SSH: each SSH session is a dedicated TCP connection holding an interactive shell. It doesn't multiplex. It doesn't stream. It blocks while the CLI processes your command and formats output as human-readable text that your code has to parse.

---

## Dell SONiC Ships gNMI Out of the Box

Here's the thing that surprised me when I started digging into this: **Dell Enterprise SONiC doesn't require any extra configuration to enable gNMI**. It's running on port 8080 by default, waiting for connections.

```bash
$ ps aux | grep telemetry
root  34778  /usr/sbin/telemetry -logtostderr --port 8080 ...
```

The `telemetry` process is part of the SONiC container architecture. It handles gNMI independently from `sshd` — separate process, separate port, separate connection management. Authentication is via gRPC metadata headers (username/password in the request, not TLS client certificates).

For a lab environment, the connection is plaintext gRPC — no TLS to wrestle with:

```typescript
import * as grpc from '@grpc/grpc-js';

// Plaintext gRPC — port 8080 on Dell SONiC
const client = new gnmiService.gNMI(
  '100.100.81.129:8080',
  grpc.credentials.createInsecure()
);

// Auth goes in metadata headers, not the connection itself
const metadata = new grpc.Metadata();
metadata.add('username', 'admin');
metadata.add('password', 'your-switch-password');
```

In production you'd enable TLS on the gNMI port — but for getting started, `createInsecure()` means you're streaming live telemetry in an afternoon, not fighting certificate management.

---

## Subscribe Modes: ON_CHANGE vs SAMPLE

The Subscribe RPC has a layered mode system. At the top level, you choose a stream type:

- **STREAM** — Persistent. Server pushes until you disconnect. This is what you want for dashboards.
- **ONCE** — Server sends current state then closes the stream. Good for one-shot snapshots.
- **POLL** — Client-driven. You send explicit poll requests, server responds. Useful when you control the polling schedule.

Within a STREAM subscription, you configure a mode **per path**:

| Mode | Behavior | Best for |
|---|---|---|
| `ON_CHANGE` | Push only when the value changes | BGP session state, interface oper-status |
| `SAMPLE` | Push at a fixed time interval | CPU utilization, memory, interface counters |
| `TARGET_DEFINED` | Device picks the best mode | System state, hostname |

The combination is powerful. In a single Subscribe request, you can say:

- "Give me BGP neighbor state changes immediately when they happen"
- "Sample interface counters every 10 seconds"
- "Sample CPU every 15 seconds"

All of these paths and modes go into one Subscribe request, and all the resulting notifications flow back on one HTTP/2 stream.

Here's what our subscription configuration looks like in practice:

```typescript
const STREAM_SUBSCRIPTIONS = [
  // BGP neighbors — ON_CHANGE: instant notification on session flap
  {
    path: '/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=bgp]/bgp/neighbors',
    mode: 'ON_CHANGE'
  },

  // Interface oper-status — ON_CHANGE: instant link-flap detection
  {
    path: '/interfaces/interface/state',
    mode: 'ON_CHANGE'
  },

  // Interface counters — SAMPLE every 10 seconds
  {
    path: '/interfaces/interface/state/counters',
    mode: 'SAMPLE',
    sampleInterval: 10_000_000_000  // ← nanoseconds. We'll get to this.
  },

  // CPU utilization — SAMPLE every 15 seconds
  {
    path: '/system/cpus/cpu[index=ALL]/state',
    mode: 'SAMPLE',
    sampleInterval: 15_000_000_000
  },

  // Memory — SAMPLE every 15 seconds
  {
    path: '/system/memory/state',
    mode: 'SAMPLE',
    sampleInterval: 15_000_000_000
  },
];
```

### The Nanosecond Gotcha

About that `sampleInterval`. Look at that number: `10_000_000_000`. That's ten billion. Ten seconds expressed in **nanoseconds**.

The gNMI spec defines `sampleInterval` in nanoseconds. Not milliseconds. Not seconds. Nanoseconds.

This is the kind of thing that costs you an hour of debugging. We initially set interval values in milliseconds thinking "10000 for 10 seconds" — and the switch started flooding us with counter updates at microsecond rates. The dashboard couldn't keep up. Logs were filling. The gNMI stream was basically a firehose.

Once we found the spec and added nine zeros, everything calmed down. But it's not intuitive, and I've seen it trip up other people too. If your SAMPLE subscription is pushing far more data than expected: check your nanoseconds.

```typescript
// WRONG — this is 10 milliseconds
sampleInterval: 10_000

// WRONG — this is 10 seconds in milliseconds
sampleInterval: 10_000_000

// RIGHT — this is 10 seconds in nanoseconds
sampleInterval: 10_000_000_000
```

---

## OpenConfig Paths That Actually Work on Dell SONiC

gNMI uses structured paths based on YANG models. With the `origin: 'openconfig'` flag, you're querying the OpenConfig vendor-neutral models. Here's what we've confirmed works on Dell Enterprise SONiC:

**BGP neighbor state** — Everything you'd want: peer AS, session state (ESTABLISHED/ACTIVE/IDLE/etc.), prefixes sent/received, message counts, established transition count, last state change. ON_CHANGE mode means BGP flaps hit your dashboard in milliseconds.

```
/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=bgp]/bgp/neighbors
```

**Interface state** — Operational status, admin status, speed, MTU for every interface. ON_CHANGE catches link flaps instantly.

```
/interfaces/interface/state
```

**Interface counters** — In/out octets, unicast packet counts, errors, discards. Great for traffic graphs at 10-second resolution.

```
/interfaces/interface/state/counters
```

**CPU utilization** — Per-CPU or aggregate stats: user time, system time, idle. We calculate `cpuPercent = (user + system) / (user + system + idle) * 100`.

```
/system/cpus/cpu[index=ALL]/state
```

**Memory** — Physical (total) and used memory in bytes. Divide, multiply by 100, you've got a percentage.

```
/system/memory/state
```

**System state** — Hostname, boot time, current datetime. Fetched once with a Get on startup rather than streamed.

```
/system/state
```

**Platform/components** — Hardware info: HwSKU, firmware version, ASIC type, serial number. Also a one-time Get, not a stream.

```
/components/component/state
```

### The 40/60 Reality

Here's an honest assessment: OpenConfig covers roughly 40% of what you need to fully manage a production data center fabric.

The 40% that works great: BGP underlay, interface state and counters, CPU/memory/system metrics, basic LLDP, ACLs. This is your monitoring core — and it works cross-vendor, which is the whole point.

The 60% that OpenConfig can't reach: EVPN/VXLAN configuration and state, PFC and ECN settings for lossless Ethernet (critical for RoCE workloads), buffer management, MCLAG/multi-chassis LAG, port breakout configuration, hardware resource utilization (ASIC CRM tables).

For those things, you need **vendor-native YANG models**. On SONiC, that means the `sonic-*` model family — `sonic-vxlan.yang`, `sonic-pfc.yang`, `sonic-mclag.yang`, etc. These map directly to SONiC's Redis CONFIG_DB and STATE_DB tables. They're more powerful and more complete than OpenConfig for SONiC-specific features. They're also not portable — a `sonic-pfc` path means nothing on a Cisco switch.

The right approach: use OpenConfig for everything it covers (monitoring, common state, cross-vendor consistency), and reach for native models when you need to go deeper. This isn't an either/or choice — the SubscriptionManager can mix both in the same session.

---

## Parsing Notifications: The Prefix+Path Trap

When gNMI sends you a notification, it looks like this:

```typescript
interface Notification {
  timestamp: string;        // nanoseconds since epoch (yes, nanoseconds again)
  prefix?: Path;            // common prefix shared by all updates in this notification
  update: Update[];         // list of path+value pairs
  delete?: Path[];          // paths that were deleted (e.g., BGP neighbor removed)
}

interface Update {
  path: Path;               // RELATIVE to the prefix
  val: {
    jsonIetfVal?: string;   // JSON string that needs parsing — most common on SONiC
    stringVal?: string;
    intVal?: string;
    uintVal?: string;
    boolVal?: boolean;
  };
}
```

The part that bites people: **you must combine `prefix` + each update's `path` to get the full OpenConfig path**. The prefix is a common ancestor shared by all updates in a notification batch. The individual update paths are relative to that prefix.

If you only look at the update path and ignore the prefix, you'll misclassify events — an interface counter update looks like just `state/counters` when it's actually `/interfaces/interface[name=Ethernet38]/state/counters`.

```typescript
function getFullPath(prefix: Path | undefined, updatePath: Path): string {
  const prefixElems = prefix?.elem ?? [];
  const pathElems = updatePath.elem ?? [];
  return '/' + [...prefixElems, ...pathElems]
    .map(e => e.key ? `${e.name}[${Object.entries(e.key).map(([k,v]) => `${k}=${v}`).join(',')}]` : e.name)
    .join('/');
}
```

### The syncResponse Signal

When you first open a Subscribe STREAM, the device sends an initial burst of notifications — the current state of everything you subscribed to. After that initial dump is complete, it sends a special `syncResponse: true` message. This is your "ready" signal.

Before `syncResponse`: you're receiving initial state. Don't show the dashboard as "streaming live" yet — it's still loading.

After `syncResponse`: everything that arrives is a real-time change. Now you're streaming.

```typescript
stream.on('data', (response) => {
  if (response.update) {
    processNotification(response.update);
  }
  if (response.syncResponse) {
    // Initial state dump is complete
    // Switch UI from "Loading..." to "🟢 Streaming"
    store.setStreamingStatus('connected');
  }
});
```

---

## Building the Pipeline: gNMI → Node.js → SSE → React

gRPC is a server-side protocol — browsers don't speak it natively. The dashboard lives in a browser. So we need a bridge.

The architecture looks like this:

```
ToR A ──gRPC/HTTP2──▶ ┌─────────────────────┐ ──SSE/HTTP──▶ Browser
ToR B ──gRPC/HTTP2──▶ │    Next.js Server    │               │
                      │                      │               │
                      │  SubscriptionManager │         EventSource
                      │  (gNMI streams per   │               │
                      │   device)            │          Zustand store
                      │                      │               │
                      │  RESTCONF client     │         React components
                      │  (on-demand queries) │
                      └─────────────────────┘
```

**Why SSE instead of WebSocket?** Server-Sent Events is a browser API for one-way server→client streaming. It's simpler than WebSocket for our use case (we only need server-to-browser push — config changes go through regular REST API calls). SSE supports automatic reconnection out of the box, works through proxies, and has a clean native `EventSource` API in every modern browser.

### The SubscriptionManager

The `SubscriptionManager` is a singleton that owns all gNMI connections. It starts on server startup, opens gNMI Subscribe streams to each device, and keeps them alive with reconnection logic.

```typescript
class SubscriptionManager {
  private clients = new Map<string, GnmiClient>();
  private streams = new Map<string, grpc.ClientDuplexStream<...>>();
  private sseClients = new Set<SSEClient>();

  async startDevice(device: DeviceConfig) {
    const client = new GnmiClient(device);
    const stream = client.subscribe(STREAM_SUBSCRIPTIONS);

    stream.on('data', (response) => {
      if (response.syncResponse) {
        this.broadcast({ type: 'sync', deviceId: device.id });
        return;
      }
      if (response.update) {
        const events = parseNotification(device.id, response.update);
        events.forEach(event => this.broadcast(event));
      }
    });

    stream.on('error', (err) => {
      // Reconnect with exponential backoff
      this.scheduleReconnect(device);
    });
  }

  broadcast(event: TelemetryEvent) {
    const data = JSON.stringify(event);
    this.sseClients.forEach(client => client.send(data));
  }
}
```

### The SSE Endpoint

Next.js App Router makes SSE straightforward:

```typescript
// app/api/stream/route.ts
export async function GET(request: Request) {
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      const client = {
        send: (data: string) => {
          controller.enqueue(encoder.encode(`data: ${data}\n\n`));
        }
      };
      subscriptionManager.addSseClient(client);
      request.signal.addEventListener('abort', () => {
        subscriptionManager.removeSseClient(client);
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

### The Zustand Store

On the browser side, a Zustand store receives SSE events and maintains reactive state:

```typescript
const useNetworkStore = create<NetworkState>((set) => ({
  devices: {},
  streamStatus: 'connecting',

  applyTelemetryEvent: (event: TelemetryEvent) => set((state) => {
    switch (event.type) {
      case 'bgp-update':
        return mergeBgpUpdate(state, event);
      case 'cpu-update':
        return mergeCpuUpdate(state, event);
      case 'interface-update':
        return mergeInterfaceUpdate(state, event);
      case 'sync':
        return { ...state, streamStatus: 'streaming' };
      default:
        return state;
    }
  }),
}));

// In a component or layout:
const eventSource = new EventSource('/api/stream');
eventSource.onmessage = (e) => {
  const event = JSON.parse(e.data);
  useNetworkStore.getState().applyTelemetryEvent(event);
};
```

React components just subscribe to the Zustand slices they need. When a BGP neighbor state changes, only the BGP table component re-renders. When CPU updates arrive every 15 seconds, only the CPU gauge updates. No full-page refreshes, no polling loops.

---

## RESTCONF: The Complement, Not the Competition

gNMI Subscribe is great for live monitoring, but it's not always the right tool. RESTCONF (HTTPS to port 443 on Dell SONiC) stays in the stack as a complement for two scenarios:

**On-demand detail queries.** When a user clicks "expand" to see the full BGP route table for a specific neighbor, we fire a RESTCONF GET rather than maintaining a persistent stream of route data we might never look at. Stateless, immediate, complete.

**Fallback and initial load.** If the gNMI stream is reconnecting, RESTCONF can fill in current state so the dashboard isn't staring at stale data. On page load, before the SSE connection is established, RESTCONF provides the initial snapshot.

```typescript
// RESTCONF for on-demand BGP route detail
async function getBgpRoutesForNeighbor(deviceIp: string, neighbor: string) {
  const url = `https://${deviceIp}/restconf/data/` +
    `network-instances/network-instance=default/` +
    `protocols/protocol=BGP,bgp/bgp/neighbors/neighbor=${neighbor}/` +
    `adj-rib-in-post`;

  const response = await fetch(url, {
    headers: {
      'Authorization': `Basic ${btoa('admin:password')}`,
      'Accept': 'application/yang-data+json',
    }
  });

  return response.json();
}
```

The paths are the same OpenConfig YANG paths — RESTCONF just uses them as URL segments instead of gNMI path elements. If you know one, you mostly know the other.

---

## What the Dashboard Actually Looks Like

The end product is a Next.js application with two device cards — one per ToR switch — each showing:

- **CPU utilization** — Live bar from gNMI SAMPLE (15s interval)
- **Memory used/total** — Live bar from gNMI SAMPLE (15s interval)
- **BGP neighbors** — Table with session state, peer AS, prefixes. ON_CHANGE means flaps appear instantly.
- **Interface summary** — Active interfaces with counters. ON_CHANGE for status, SAMPLE for traffic.
- **Stream status** — Text+color indicator: "🟢 Streaming", "🔵 Connecting...", "🔴 Error". Always a word, never just a color.

The network topology sits above both cards — a visual graph of spine and ToR nodes, with edges colored by BGP session state. When a BGP link goes down, the edge turns red within milliseconds. No polling. No waiting.

---

## Lessons Learned

**gNMI is purpose-built for monitoring. SSH is not.** The session limit problem is a symptom of using the wrong tool. gNMI exists precisely to solve this — separate process, separate port, no impact on interactive access.

**The nanoseconds thing will get you.** Write it on a sticky note. Put it somewhere you'll see it. `sampleInterval` is in nanoseconds. 10 seconds = `10_000_000_000`.

**Combine prefix + path.** Always. Every time. It's easy to get this wrong and silently misclassify events.

**Don't show "streaming" until syncResponse.** The initial state dump is loading, not live. Respect the distinction.

**OpenConfig is 40% of the story.** It's the right 40% — the portable, cross-vendor core. But if you want PFC counters, EVPN VTEP state, or buffer utilization, you're going to need native YANG models alongside it.

**RESTCONF and gNMI are teammates.** Subscribe for live monitoring, RESTCONF for on-demand detail. Each has its place.

---

## What's Next

The dashboard is in good shape for read-only monitoring. The next evolution is state validation — defining "intended state" as a document and querying gNMI Get to check whether the network matches it. After that, gNMI Set for config push: structured, validated, idempotent, without an SSH session in sight.

The SSH lockout that started this whole journey turned out to be a gift. It pushed us toward a better architecture than we'd have built otherwise. Sometimes the right path starts with a door that's already closed.

---

*Post 4 will cover the multi-vendor abstraction layer — building a `DeviceProvider` interface that speaks gNMI equally to SONiC and Cisco NX-OS, so the dashboard doesn't have to know which switch it's talking to.*
