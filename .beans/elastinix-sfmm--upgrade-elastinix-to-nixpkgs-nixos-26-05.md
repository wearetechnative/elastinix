---
# elastinix-sfmm
title: port-prometheus-alertmanager-cognito-auth-to-nixos-26-05
status: in-progress
type: epic
priority: high
created_at: 2026-09-04T12:06:49Z
updated_at: 2026-09-04T13:01:21Z
---

Land the Prometheus/Alertmanager Cognito (oauth2-proxy) authentication on the
elastinix `nixos-26.05` release branch — the branch that 26.05 computes actually
consume (`elastinix.url = github:wearetechnative/elastinix/nixos-26.05`).

## Corrected model

Elastinix is not a system; it is a module library with a long-lived release
branch per nixpkgs version (`nixos-25.05`, `nixos-25.11`, `nixos-26.05`,
`nixos-unstable`). A consuming compute pins `nixpkgs/nixos-26.05` together with
`elastinix/nixos-26.05`; the modules evaluate under the compute's nixpkgs.

Reference consumer: technative-awsaccounts-workloads/stack/ec2_compute* — all on
`nixpkgs/nixos-26.05` + `elastinix/nixos-26.05`.

## Why this epic

The oauth2-proxy/Cognito feature was developed on a branch off `nixos-25.11`
(PR #32, base `nixos-25.11`, not merged). But:
- `origin/nixos-26.05` already exists (29 commits ahead of 25.11) and is what the
  compute consumes; the feature is on neither release branch.
- On `nixos-25.11` the oauth2-proxy module fails (`clientSecretFile` /
  `cookie.secretFile` / `trustedProxyIP` don't exist in that nixpkgs — bug
  `monitoring-qf95`). On `nixos-26.05` the two-file design is native and correct.

## Decision

Support this new service on **26.05 only**. Do not port it to `nixos-25.11`.
Keep the two-file secret design (`clientSecretFile` + `cookieSecretFile` +
`trustedProxyIP`); the `keyFile` workaround is unnecessary and is reverted.

## Resolves

- `monitoring-qf95` (scrapped): root cause was targeting the 25.11 branch instead
  of 26.05.

## Verification lesson

Validate modules against the release branch's own nixpkgs (the consumer's
version), not the registry (`nix eval nixpkgs#path` = unstable).
