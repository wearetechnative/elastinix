---
# elastinix-ytnc
title: Socket observation accumulates ephemeral client ports as listeners
status: completed
type: bug
priority: high
created_at: 2026-08-28T08:52:26Z
updated_at: 2026-08-28T08:53:59Z
parent: elastinix-p9gu
---

The in-use sampler records every socket ss reports as bound, including outbound UDP client sockets. systemd-timesyncd binds a fresh random UDP port for each NTP reply, so every sample adds a new phantom "listening socket" to the cumulative observed set.

Measured on compute1-prod: 32 socket keys recorded, 23 of them single-sample UDP in the ephemeral range 32768-60999, sampleCount 23. It grows by exactly one per sample.

At the 5 minute interval that is ~288/day. Within a month the evidence annex would carry roughly 8600 phantom sockets and the review report would read "5 of 8600". Both documents become unusable, and an auditor who spots one timesyncd row concludes the socket evidence is not understood.

This is a category error, not an accumulation bug: an outbound UDP conversation is not a listening service. TCP is unaffected because LISTEN state is unambiguous.

The data separates cleanly. Every real listener on all three prod hosts is below 32768; every phantom is above it.

Fix: read /proc/sys/net/ipv4/ip_local_port_range at sample time and, for UDP only, classify sockets in that range as client sockets rather than listeners. Count them, do not accumulate them. Also purge the already-accumulated phantoms from runtime-facts.json on the deployed hosts, since they persist otherwise.

## Follow-up: elastinix-yx3a

The root cause was accumulation: a socket key recorded once stayed for the life of
the document, so a fresh ephemeral port each sample grew the set without bound. With
daily buckets a day's set is sealed when the day ends, so this class of defect
cannot recur — the classification fix here remains correct, but it stops being the
only thing standing between the evidence and unbounded growth.
