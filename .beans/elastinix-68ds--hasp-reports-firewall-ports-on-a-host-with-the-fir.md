---
# elastinix-68ds
title: HASP reports firewall ports on a host with the firewall disabled
status: completed
type: bug
priority: critical
created_at: 2026-08-28T07:58:56Z
updated_at: 2026-08-28T08:02:59Z
parent: elastinix-p9gu
---

network.firewallOpenPorts is derived from config.networking.firewall.allowed{TCP,UDP}Ports without checking config.networking.firewall.enable.

compute5-prod has networking.firewall.enable = false. Verified live: systemctl is-active firewall -> inactive, no nixos-fw chain. HASP nonetheless reports "firewall open ports: 22, 3333, 9200", which reads as a restrictive control.

Impact: the ISO review report UNDERSTATES exposure for that host. An auditor who discovers the firewall was off has grounds to distrust the whole document. This is the one error class that must not ship.

Fix: add a network.firewallEnabled derived fact and make consumers unable to read the port list without it.
