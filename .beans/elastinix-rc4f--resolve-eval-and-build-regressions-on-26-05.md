---
# elastinix-rc4f
title: set-monitoring-input-and-verify-wrapper-on-nixos-26-05
status: completed
type: task
priority: high
created_at: 2026-09-04T12:07:11Z
updated_at: 2026-09-04T13:05:07Z
parent: elastinix-sfmm
---

On the `nixos-26.05` branch, set the grafana-prometheus flake input (flake.lock) to a wearetechnative/monitoring revision that carries the two-file oauth2-proxy design (monitoring main after the keyFile revert). Then verify the wrapper evaluates against the 26.05 branch's own nixpkgs: oauth2Proxy enabled → oauth2-proxy=oidc, clientSecretFile/cookie.secretFile wired, trustedProxyIP set, prometheus/alertmanager vhosts carry auth_request; and disabled → unchanged. This is the qf95 check that was missing.

Repo: wearetechnative/elastinix (branch nixos-26.05, flake.lock).

## Summary of Changes

Set grafana-prometheus flake input to wearetechnative/monitoring 0d47245 (two-file design) on the 26.05 branch. Verified the wrapper against the branch's own nixpkgs (26.05.20260714): enabled -> provider=oidc, clientSecretFile/cookie.secretFile wired, trustedProxyIP=127.0.0.1/32, prometheus vhost has auth_request (exit 0); disabled -> oauth2-proxy off, vhost only '/', firewall=[3000]. This is the consumer-representative check that was missing in qf95.
