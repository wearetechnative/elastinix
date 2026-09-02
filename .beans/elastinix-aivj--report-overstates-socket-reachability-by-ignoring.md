---
# elastinix-aivj
title: Report overstates socket reachability by ignoring the host firewall
status: completed
type: bug
priority: high
created_at: 2026-08-28T07:58:56Z
updated_at: 2026-08-28T08:02:59Z
parent: elastinix-p9gu
---

The report generator states that wildcard-bound sockets are "reachable subject to the security group" and never consults the host firewall.

Measured against the 2026-08-28 run:
  compute1-prod: 10 wildcard sockets, only 5 in the firewall allow-list
  compute2-prod: 12 wildcard sockets, only 10 allowed
  compute5-prod:  8 wildcard sockets, firewall disabled so all reachable

So the claim overstates compute1 and compute2, and understates compute5. Cross-referencing bind class against the firewall gives the stronger and correct claim: bound wildcard, firewall-blocked, security-group-blocked are three independent barriers.

Fix: cross-reference sockets against the protocol-specific firewall facts, and treat firewall-disabled as all ports open.
