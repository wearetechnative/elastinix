---
# elastinix-b5rr
title: HASP firewall port fact merges TCP and UDP into one list
status: completed
type: bug
priority: high
created_at: 2026-08-28T07:58:56Z
updated_at: 2026-08-28T08:02:59Z
parent: elastinix-p9gu
---

network.firewallOpenPorts unions allowedTCPPorts and allowedUDPPorts, so a consumer cannot tell whether port 68 is open for UDP or 8080 for TCP.

That distinction is load-bearing when cross-referencing observed listening sockets (which carry a proto) against the firewall to decide real reachability.

Fix: emit protocol-specific facts instead of the union.
