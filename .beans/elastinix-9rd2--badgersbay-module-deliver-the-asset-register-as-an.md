---
# elastinix-9rd2
title: 'badgersbay module: deliver the asset register as an agenix secret'
status: completed
type: task
priority: high
tags:
    - badgersbay
    - nixos
    - agenix
created_at: 2026-09-16T09:33:24Z
updated_at: 2026-09-16T09:33:24Z
parent: elastinix-l16a
---

Badgersbay measures compliance against an asset register. Without one the
dashboard can show what arrived but never which systems are missing, and both
its views say `No asset register configured`.

## OpenSpec

Delivered through `openspec/changes/archive/2026-09-16-badgersbay-asset-register/`,
which created the `badgersbay-service` capability.

## Summary of Changes

`assetRegisterFile` added as a `nullOr path` option beside `tokenFile` and
`dashboardPasswordFile`, following the same agenix pattern. The service passes
it as `--asset-register` when set, and omits the argument entirely when not, so
a host without a register runs as it did before.

Passed as an argument rather than written into the generated configuration.
compute2 overrides `configFile` wholesale with its own agenix secret, so a
value written into the module's generated config would never reach it - and
this way that secret does not have to be reissued to gain a register.

The rendering was verified both ways. Without a register the line continuation
leaves a trailing backslash; bash joins it with the empty line that follows and
the arguments come through unchanged, confirmed by running it.

Docs record where the CSV comes from, that a register the server cannot trust
stops it from starting, and that an asset disappearing from a later register is
reported rather than silently dropped.

The secret is already in place: `technative-awsaccounts-workloads` commit
1ac4467 added `badgersbay-assets.age` for compute2 with a comment waiting on
this option. Wiring it up there is the next step.
