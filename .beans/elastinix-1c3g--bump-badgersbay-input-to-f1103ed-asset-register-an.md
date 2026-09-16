---
# elastinix-1c3g
title: Bump badgersbay input to f1103ed - asset register and inventory
status: completed
type: task
priority: high
tags:
    - badgersbay
created_at: 2026-09-16T09:48:19Z
updated_at: 2026-09-16T09:48:19Z
---

`flake.lock` pinned badgersbay at `cd3db88` (2026-09-15). The module now passes
`--asset-register`, an argument that commit does not accept, and the whole point
of the register - matching submissions against the ISO asset sheet - only exists
from `f1103ed`.

Bumped to `f1103ed` (origin/main), which brings:

- `--asset-register` and the `AssetRegister` fail-fast loader
- the round view and fleet view built on the register as denominator
- `parse_asset_inventory()`, so `asset-inventory.json` from the client is read
  rather than only stored

    nix flake lock --update-input badgersbay --refresh

`--refresh` is not optional: without it nix serves a cached fetch and the lock
appears unchanged.

## Checked that nothing moved backwards

Overriding or re-locking an input replaces that flake's whole lock, and a branch
trailing its base has silently moved sibling inputs backwards here before
(recorded in `technative-awsaccounts-workloads-dfpw`). The diff is three lines in
one node: `lastModified`, `narHash`, `rev` of badgersbay. nixpkgs,
grafana-prometheus and optscale are untouched.

This branch is also three commits ahead of `origin/nixos-26.05` and nothing
behind, so consumers locking against it do not inherit an older base.
