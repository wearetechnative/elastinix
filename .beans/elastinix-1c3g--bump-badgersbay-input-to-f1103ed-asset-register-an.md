---
# elastinix-1c3g
title: Bump badgersbay input to f1103ed - asset register and inventory
status: completed
type: task
priority: high
tags:
    - badgersbay
created_at: 2026-09-16T09:48:19Z
updated_at: 2026-09-17T14:12:56Z
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


## Bumped again: f1103ed -> 47e6cb6

badgersbay PR #9 added the **Vulnerable pkgs** column and raised
`INVENTORY_SCHEMA_VERSION` to 2, so the pin set above was one release behind
within the hour.

Re-locked the same way, with `--refresh`. The diff is again three lines in the
badgersbay node alone - `lastModified`, `narHash`, `rev`. nixpkgs,
grafana-prometheus and optscale untouched, nothing moved backwards.

The count this renders is emitted by honeybadger from `23f7d8e`, merged as its
PR #17. Server and client generations line up.


## Bumped again: 47e6cb6 -> 3c15254

badgersbay `3c15254` makes `/health` count what the server reads. It walked one
of two storage layouts chosen by a configuration flag, and the serial-keyed tree
the server actually writes was in neither, so it reported zero submissions on a
server that was receiving them - visible only since the pre-serial archive was
moved aside and stopped supplying the numbers.

No merge of `nixos-26.05` was needed for this. That base has moved ahead on
optscale, but compute2 consumes this branch rather than the base, so nothing
falls back - optscale simply stays where it is. The `dfpw` trap is about
`--override-input` against a trailing branch, which is not the situation here.

The diff is three lines in the badgersbay node alone.
