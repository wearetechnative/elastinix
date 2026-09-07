---
# elastinix-v515
title: port-oauth2-proxy-wrapper-and-docs-to-nixos-26-05
status: completed
type: task
priority: high
created_at: 2026-09-04T12:07:11Z
updated_at: 2026-09-04T13:05:07Z
parent: elastinix-sfmm
---

Cherry-pick the oauth2-proxy/Cognito work from feature/prometheus-alertmanager-cognito-auth onto the elastinix `nixos-26.05` branch:
- service-grafana.nix oauth2Proxy option group (two-file: clientSecretFile + cookieSecretFile + groupsClaim/allowedGroups) passed through to services.grafana-prometheus.oauth2Proxy
- docs/services/grafana-prometheus.md + docs/README.md index entry
- CHANGELOG entry

Keep the two-file design; NO keyFile. 26.05-only — do not touch nixos-25.11.

Repo: wearetechnative/elastinix (branch nixos-26.05).

## Summary of Changes

Cherry-picked 41459ba (service-grafana.nix oauth2Proxy two-file option group + passthrough, docs/services/grafana-prometheus.md, docs/README.md entry, CHANGELOG, archived openspec change) from the 25.11 feature branch onto a branch off origin/nixos-26.05 (commit 7117f24). Resolved CHANGELOG conflict (kept both the 26.05 vuln-scan entries and the Cognito entry); updated the stale flake.lock note to '26.05-only'. Two-file design kept; no keyFile.
