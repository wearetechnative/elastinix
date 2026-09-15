---
# elastinix-p2ku
title: expose-oauth2-proxy-options-elastinix-wrapper
status: completed
type: feature
priority: high
created_at: 2026-09-04T09:08:57Z
updated_at: 2026-09-04T10:19:53Z
parent: elastinix-wx2c
---

Surface the new auth options through the elastinix wrapper
`elastinix.services.grafana-prometheus` (service-grafana.nix): an `auth`/
`oauth2Proxy` submodule with `enable`, `oidcIssuerUrl`, `clientId`,
`clientSecretFile`, `cookieSecretFile`, and `allowedGroups`. Pass through to the
monitoring module's `services.grafana-prometheus`.

Repo: wearetechnative/elastinix (modules/nixos/services/service-grafana.nix).

## Summary of Changes

Added the `elastinix.services.grafana-prometheus.oauth2Proxy` submodule (enable, oidcIssuerUrl, clientId, clientSecretFile, cookieSecretFile, allowedGroups, groupsClaim) in service-grafana.nix and passed it through to services.grafana-prometheus.oauth2Proxy. Verified via nix eval against the local monitoring module (enabled + disabled).
