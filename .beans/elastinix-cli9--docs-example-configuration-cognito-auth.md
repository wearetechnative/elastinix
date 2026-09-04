---
# elastinix-cli9
title: docs-example-configuration-cognito-auth
status: completed
type: task
priority: normal
created_at: 2026-09-04T09:08:57Z
updated_at: 2026-09-04T10:19:53Z
parent: elastinix-wx2c
---

Update `example-configuration.nix` and the module README to document the
oauth2-proxy option surface, the required Cognito app client + callback URLs
(`https://{prometheus,alertmanager}.<domain>/oauth2/callback`), and the two
secret files. Note SSO behaviour and group-based authorization.

Repos: wearetechnative/monitoring + elastinix (docs).

## Summary of Changes

Added docs/services/grafana-prometheus.md (option surface, Cognito app client + two callback URLs, the two secret files, SSO/group authorization, troubleshooting) and a services index entry in docs/README.md. Example configuration and secrets documented in the monitoring repo (example-configuration.nix + README.md).
