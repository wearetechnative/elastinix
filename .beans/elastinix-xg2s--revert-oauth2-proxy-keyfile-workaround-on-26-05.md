---
# elastinix-xg2s
title: revert-oauth2-proxy-keyfile-wip-keep-two-file-design
status: completed
type: task
priority: high
created_at: 2026-09-04T12:07:11Z
updated_at: 2026-09-04T13:05:07Z
parent: elastinix-sfmm
---

On 26.05 the original two-file oauth2-proxy secret design is valid (clientSecretFile + cookie.secretFile via LoadCredential, plus trustedProxyIP). Discard the uncommitted keyFile WIP in the monitoring working tree and keep the committed two-file design; re-verify the oauth2-proxy chain (monitoring module + elastinix wrapper + consumer) against the 26.05-locked nixpkgs. This resolves the concern behind monitoring-qf95.

Repo: wearetechnative/monitoring (module/oauth2-proxy, module/default.nix) + elastinix wrapper re-verify.

## Summary of Changes

Reverted the uncommitted keyFile WIP in the monitoring working tree (module/default.nix, module/oauth2-proxy/default.nix); restored the committed two-file design (clientSecretFile + cookie.secretFile + trustedProxyIP), which is correct on 26.05. monitoring main (0d47245) already carries it; no monitoring commit needed.
