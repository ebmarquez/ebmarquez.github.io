---
layout: post
title: "Stop SSHing Into My Switches"
date: 2026-04-07 00:00:00 -0700
categories: [networking, ai]
tags: [sonic, gnmi, telemetry, grpc, openconfig, networking, data-center]
author: ebmarquez
description: "SSH is not a monitoring protocol. Dell SONiC ships with gNMI telemetry out of the box — persistent streaming, structured data, and zero admin lockout. Here's how it works."
image:
  path: https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=1200&q=80
  alt: "Abstract digital network visualization with glowing blue connections"
---

*This is Part 3 of a series about deploying SONiC switches with AI assistance. [Part 1](/posts/hey-copilot-can-you-ssh-into-a-switch/) covered discovery. [Part 2](/posts/heres-a-25-figure-out-the-address-plan/) covered IP planning and BGP deployment. Now we monitor.*

---

## We Built the Network. Now We Can't See It.

If you've been following along, you know the drill by now. In [Part 1](/posts/hey-copilot-can-you-ssh-into-a-switch/), we let an AI loose on a pile of blank SONiC switches and watched it figure out how to talk to them over SSH. In [Part 2](/posts/heres-a-25-figure-out-the-address-plan/), we handed it an address plan problem and a BGP deployment — and it actually nailed it. Routes were flowing. Neighbors were up. Life was good.

So naturally, I wanted to monitor the thing.

You know, like a responsible network engineer. Check BGP session states, watch for interface flaps, maybe graph some counters. Basic operational hygiene. The kind of stuff you set up on day two so you're not flying blind on day three.

My first instinct was the same one every network person has: SSH in, run some show commands, parse the output. It's how we've done it for twenty years. It's comfortable. It's familiar. It's also, as I was about to find out, a terrible idea at scale.

### The Two-Session Wall

Here's something fun about the Dell S5248F-ON running SONiC: it lets you have roughly two concurrent SSH sessions. That's it. Two.

Now, two sessions is fine when you're a human poking around a switch. You open a terminal, check some stuff, close it, move on. But the moment you introduce any kind of automated monitoring — a script that connects every sixty seconds to scrape `show bgp summary` and `show interfaces status` — you've permanently parked one of those sessions.

Congratulations, you now have one SSH session left for actual administration. And if someone else on your team logs in? Or if your monitoring tool hiccups and opens a second connection without closing the first? You're locked out of your own switch.

This isn't a hypothetical. This happened. I set up a quick polling script, walked away to grab coffee, came back, and couldn't SSH into the switch. The monitoring tool was squatting on both sessions like a college roommate who never leaves the couch.

### Screen-Scraping Is Not a Strategy

Even when SSH worked, the experience was... painful. Every show command returns a wall of unstructured text. Want to know if a BGP neighbor is established? You're parsing human-readable tables with regex. Want interface counters? Same deal — screen-scraping output that was designed for eyeballs, not automation.

It's brittle. A firmware update changes the column spacing, and your parser breaks. A hostname is longer than expected, and the table wraps weirdly. You end up spending more time maintaining your parsing logic than actually monitoring the network.

And here's the thing — I knew all of this going in. Every network engineer knows SSH-and-show-commands is held together with duct tape and prayer. We just keep doing it because it's what we know.

### The Realization

Sitting there, locked out of my own switch by my own monitoring script, staring at a terminal that refused to connect — that was the moment it clicked. **SSH is not a monitoring protocol.** It was never designed for persistent, automated data collection. It's a remote shell. Using it for monitoring is like using a screwdriver as a hammer: it technically works until it doesn't, and then you've got a dent in the wall and a broken screwdriver.

There had to be a better way. Something designed for exactly this problem — structured data, no session limits, built for machines to consume. And as it turns out, these SONiC switches already had it. I just hadn't turned it on yet.

## Enter gNMI: The Protocol That Doesn't Hog the Remote

So if SSH monitoring is the networking equivalent of hogging the TV remote while everyone else wants to change the channel, what's the alternative? Meet **gNMI** — the gRPC Network Management Interface — and honestly, once you see what it does, you'll wonder why we ever tolerated screen scraping in the first place.

gNMI was defined by **OpenConfig**, the vendor-neutral consortium that looked at how we manage networks and collectively said, "We can do better." And they weren't wrong.

### The Basics: What's Under the Hood

At its core, gNMI rides on **gRPC over HTTP/2**. If that sounds like alphabet soup, here's the short version: it's a modern, high-performance transport that was built for exactly this kind of machine-to-machine communication. Data gets encoded as **Protobuf binary** with **JSON_IETF payloads** — structured, efficient, and parseable without writing a single regex. Authentication happens through gRPC metadata headers (username and password), keeping it clean and separate from the device's CLI session.

That last part matters more than it sounds. gNMI traffic never touches the SSH subsystem. Your monitoring can hum along 24/7 and your admin can still SSH in at 3 AM to troubleshoot a flapping peer. No lockouts. No contention. No drama.

### The Head-to-Head: gNMI vs. RESTCONF vs. SSH/CLI

Let's put these three approaches side by side, because the differences are stark:

| Feature | gNMI | RESTCONF | SSH/CLI |
|---|---|---|---|
| **Transport** | gRPC / HTTP/2 | HTTPS | SSH |
| **Streaming** | Native Subscribe | Polling only | Screen scraping |
| **Connection** | Persistent, bidirectional | Stateless request/response | Session-based (holds a shell) |
| **Concurrency** | Many streams multiplexed on one TCP connection | Many via HTTP pooling | Limited — 1 to 2 max |
| **Admin lockout risk** | None — separate from CLI | None — separate from CLI | **HIGH** — blocks admin SSH |
| **Data format** | Structured Protobuf/JSON | Structured JSON | Unstructured text |

RESTCONF is a solid step up from CLI scraping — structured data, no shell lockout — but it's still a polling model. You ask, the device answers, the connection closes. If something changes between polls, you don't know until the next cycle.

gNMI flips that on its head with **persistent, bidirectional streaming**. The device tells *you* when something changes. It's the difference between refreshing your email every five minutes and getting push notifications.

### The Four RPCs: gNMI's Toolkit

gNMI defines exactly four operations, and each one earns its keep:

- **Capabilities** — "Hey switch, what do you support?" The handshake. Your client discovers which YANG models, encodings, and gNMI version the device speaks. It's like checking the menu before you order.

- **Get** — A one-shot, stateless query. Ask for a specific path (say, `/interfaces/interface[name=Ethernet1]/state/counters`), get structured data back, done. No persistent connection needed. Think of it as a polite knock on the door.

- **Set** — Push configuration changes. Create, update, replace, or delete config at specific paths. This is your write operation, and it's atomic — the whole Set either succeeds or fails, no half-applied configs haunting you at 2 AM.

- **Subscribe** ⭐ — And here's the star of the show. This is gNMI's killer feature and the reason we're having this conversation. Subscribe opens a **persistent, bidirectional stream** between your collector and the device. Once it's up, data flows continuously without repeated requests, without holding a shell, and without anyone getting locked out.

### Subscribe Modes: Picking Your Flavor

Subscribe isn't one-size-fits-all. It comes in layers, and mixing them is where the real power lives.

**At the top level**, you choose your subscription type:

- **STREAM** — Long-lived, persistent. The connection stays open and data flows as long as both sides are up. This is the workhorse for production monitoring.
- **ONCE** — Fire and forget. Get one batch of updates, then the stream closes. Handy for inventory snapshots or one-time audits.
- **POLL** — Client-initiated. The stream stays open, but updates only come when the client explicitly asks. A middle ground if you want control over timing.

**At the per-path level**, each subscription path gets its own trigger mode:

- **ON_CHANGE** — The device sends an update only when the value actually changes. Perfect for BGP session state: the instant a peer flaps from Established to Idle, you know. No polling delay. No wasted bandwidth when things are stable.
- **SAMPLE** — Updates at a fixed interval regardless of change. Ideal for counters — interface throughput, CPU utilization, memory usage — where you want a regular time series even if values barely moved.
- **TARGET_DEFINED** — The device picks the most appropriate mode for each leaf. Some vendors use this as their default, letting the switch decide whether a path is better served by on-change or sampling.

The magic is in combining them. One subscription can carry BGP state on ON_CHANGE *and* interface counters on a 30-second SAMPLE interval, all flowing through the same stream.

### One Connection to Rule Them All

Here's the HTTP/2 advantage that ties everything together: **one TCP connection per device carries all your subscriptions**. HTTP/2 multiplexes multiple logical streams over a single connection, so whether you're subscribing to five paths or fifty, it's all flowing through one socket. No connection explosion. No file descriptor exhaustion. No frantic rate-limiting.

Compare that to SSH, where monitoring two things often means two shell sessions consuming two of your precious concurrent connection slots. With gNMI, your monitoring footprint is essentially *one connection per device*, period — and that connection never interferes with operational access.

That's not an incremental improvement. That's a fundamentally different architecture for how we observe our networks.

## Dell SONiC: gNMI That's Already Running

Here's the thing nobody tells you about Dell SONiC — gNMI is just *there*. No package installs, no feature flags, no "please consult your TAC engineer." The `telemetry` process runs on port 8080 by default, serving up plaintext gRPC like a diner that's open 24/7.

No TLS? For a lab, that's perfectly fine. Auth happens through gRPC metadata headers, and the whole thing requires exactly zero extra configuration. Boot the switch, and gNMI is ready to chat. After years of wrestling vendor CLI wizards just to enable basic telemetry, this felt almost suspicious.

## The Nanosecond Trap (We Fell Right In)

Let me save you the debugging session we didn't enjoy: **sampleInterval is measured in nanoseconds**. Not milliseconds. Not seconds. *Nanoseconds.*

Want counters every 10 seconds? That's `10,000,000,000`. Ten billion. The kind of number that makes you double-count zeros.

Eric's team initially set the interval to something that *looked* reasonable — and promptly watched interface counters flood in at microsecond intervals. The switch was fine (SONiC is surprisingly chill about this), but the collector on the other end was drowning in data like it'd opened a fire hydrant. Quick fix once you know the unit, but it's the kind of gotcha that burns an afternoon if you don't.

**Pro tip:** Count your zeros. Then count them again.

## OpenConfig Paths That Actually Work

Not all YANG paths are created equal, and not every one listed in the OpenConfig spec actually returns data on real hardware. Here's what we validated on Dell SONiC — paths that work, what they return, and how to subscribe:

**ON_CHANGE subscriptions** (push updates only when something happens):

- **`/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=bgp]/bgp/neighbors`** — BGP neighbor state changes. Peer goes down? You know instantly, not at the next polling interval.
- **`/interfaces/interface[name=*]/state`** — Interface oper-status, admin-status, the works. This is your instant link-flap detection. A cable gets pulled, and your collector knows before the NOC engineer's coffee hits the desk.

**SAMPLE subscriptions** (periodic polling at your chosen interval):

- **`/interfaces/interface[name=*]/state/counters`** — In-octets, out-octets, errors, discards. The bread and butter of network monitoring. We run this at **10-second intervals** (that's `10000000000` nanoseconds — you're welcome).
- **`/system/cpus/cpu[index=ALL]/state`** — CPU utilization across all cores. **15-second samples** give you enough granularity without drowning in data.
- **`/system/memory/state`** — Physical memory usage. Same **15-second** cadence works well here.

**One-shot Gets** (grab once, cache locally):

- **`/system/state`** — Hostname, boot-time, software version. The stuff that doesn't change unless someone's having a very exciting maintenance window.
- **`/components/component[name=*]/state`** — Hardware SKU, firmware versions, serial numbers. Great for inventory, terrible for real-time monitoring.

## The Honest 40/60 Split

Here's where I level with you: **OpenConfig covers about 40% of what a production fabric actually needs for monitoring.** And that 40% is genuinely useful — interface stats, BGP state, system health. The fundamentals.

But the other 60%? EVPN route tables, QoS and PFC watchdog counters, MCLAG state — that's all hiding behind vendor-native YANG models. SONiC has its own YANG paths for these, and they work fine, but they're not the portable, vendor-neutral dream that OpenConfig promises.

Is that a dealbreaker? Not really. OpenConfig gives you a consistent monitoring baseline across any switch that supports it. The vendor-specific stuff layers on top for the deep operational data. Think of OpenConfig as the dashboard gauges everyone agrees on, and native YANG as the OBD-II port where the real diagnostics live.

For a monitoring stack, that 40% gets you surprisingly far.

## From gNMI Stream to Browser: The Real-Time Pipeline

Getting gNMI data into a terminal is cool. Getting it into a live dashboard that updates while you sip coffee? That's the dream.

Here's how the pipeline works: a Node.js server (using `@grpc/grpc-js`) maintains persistent gNMI subscriptions to each switch. As telemetry updates arrive — BGP neighbor state changes, CPU spikes, interface counters — the server processes them and pushes typed events to the browser via **Server-Sent Events (SSE)**.

Why SSE instead of WebSockets? Three reasons:

- **Simplicity.** This is a one-way data flow — switches talk, the browser listens. SSE is purpose-built for server-to-client pushes, and the native `EventSource` API gives you auto-reconnect for free. No heartbeat logic, no ping-pong frames, no connection state machine to debug at 2 AM.
- **Proxy-friendly.** SSE is just HTTP. It passes through corporate proxies and load balancers without the upgrade-handshake drama that WebSockets sometimes struggle with.
- **Typed events.** Each SSE event gets a type — `bgp-update`, `cpu-update`, `interface-counters` — and the React frontend routes them into the right Zustand store slice. Clean separation, minimal parsing.

The gNMI streams run entirely server-side. The browser never touches gRPC. It just consumes a clean event stream that says "hey, this BGP neighbor on leaf-03 just went Established" and the UI updates accordingly.

One detail that tripped us up: **syncResponse**. When you first open a gNMI subscription, the device dumps its current state — every BGP neighbor, every interface, the works. After that initial burst, it sends a notification with `syncResponse: true`. That's your "ready" signal. Before sync, you're loading. After sync, you're live. Miss that distinction and your dashboard shows incomplete data with no indication that it's still catching up.

## RESTCONF: The Reliable Sidekick

gNMI handles the streaming, but not everything needs to be a persistent subscription. Sometimes you just want to ask a switch "what's your current BGP table?" and get an answer.

That's where RESTCONF comes in. Plain HTTPS to port 443 on the SONiC switches, stateless request-response. It's perfect for:

- **Initial state loads** when the dashboard first connects
- **Refresh button clicks** (the manual "I don't trust the stream, show me reality" moments)
- **Fallback** if a gNMI subscription drops and you need data while it reconnects

gNMI for the firehose, RESTCONF for the spot checks. They complement each other beautifully — structured YANG data either way, just different delivery mechanisms.

## The SSH Tunnel Saga (A Cautionary Tale)

Before the routing was fixed, reaching the SONiC leaf switches meant SSH tunneling through the Cisco spine switches. The Node.js server would open an SSH tunnel through a spine, forward a local port to the leaf's gNMI endpoint, and subscribe through that tunnel.

It was... fragile. Keyboard-interactive authentication prompts. TACACS+ timeouts. Session limits on the spines (because of course there are session limits). Every tunnel was another thing that could silently die, and when it did, the dashboard just stopped updating with no obvious error.

Here's the irony: the SSH tunnels were easily the worst part of the entire monitoring setup. And fixing the spine BGP configuration — the work from the previous post — gave us direct IP reachability to every leaf loopback. The tunnels just... went away. Deleted the tunnel code, pointed the gNMI client directly at the loopback addresses, and everything got simpler overnight.

Sometimes the best monitoring fix is a routing fix.

## Lessons Learned (The Hard Way)

A few things we burned time on so you don't have to:

- **SSH is not a monitoring protocol.** It's an access protocol. The moment you're maintaining SSH tunnels for telemetry, you've taken a wrong turn.
- **sampleInterval is in nanoseconds.** Not seconds. Not milliseconds. *Nanoseconds.* We set `10` thinking "ten seconds" and got a firehose that nearly melted the server. `10000000000` is ten seconds. Write it down.
- **Insecure gRPC is fine for lab.** TLS adds complexity. In a controlled lab environment, `grpc.credentials.createInsecure()` saves you hours of certificate wrangling. Production is a different conversation.
- **Prefix + path combination matters.** gNMI notifications split the YANG path between `prefix` and individual `update` paths. You need to concatenate them to get the full path. Ignore the prefix and your data ends up in the wrong bucket.
- **syncResponse is your "ready" signal.** Don't render the dashboard as "live" until you've received it. Your users will thank you.
- **Direct loopback access beats SSH tunnels every single time.** Fix your routing first. Then build your monitoring.

## What's Next

We've got gNMI streaming, RESTCONF queries, and a pipeline that turns raw YANG data into browser events. But we haven't talked about the dashboard itself — the React components, multi-vendor support across different NOS platforms, or using gNMI Set to push configuration changes back to the switches.

That's where this is heading: a Network Environment Manager that doesn't just watch the network but actively participates in it. One tool to monitor, configure, and troubleshoot — all built on the same structured telemetry foundation.

But the real shift is simpler than any of that. We went from "SSH into each switch and run show commands" to "one persistent stream per device, structured data, zero admin impact." No screen-scraping. No regex. No prayer-based parsing.

Just open a subscription and let the network tell you what's happening.
