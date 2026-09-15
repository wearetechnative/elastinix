---
# elastinix-l16a
title: 'badgersbay module: settings as options, tokens and asset register through agenix'
status: todo
type: epic
priority: high
tags:
    - badgersbay
    - nixos
    - agenix
created_at: 2026-09-15T16:24:06Z
updated_at: 2026-09-15T16:24:06Z
---

`service-badgersbay.nix` half-manages the badgersbay configuration. The module
should own the shape; agenix should own the values.

## Current state

    configFile            types.path, default = writeText with a hardcoded
                          heredoc
    tokenFile             types.path, points at an agenix secret
    dashboardPasswordFile types.path, points at an agenix secret

Three problems.

**The configuration is a string, not options.** The compliance block sits
literally in the module, so changing the audit months means overriding
`configFile` in full and losing the rest of the generation. There is no
`mkOption` for anything inside the block.

That is not theory. `technative-awsaccounts-workloads`, compute2, does exactly
that:

    configFile = config.age.secrets.badgersbay-config.path;

Consequence: when the module default moved from `neofetch` to `fastfetch`
(elastinix-22iq), that change did not reach the production host. The real
configuration lives in an agenix secret that had to be updated separately. A
module that only exposes the whole config file as one option cannot roll out its
own defaults once anyone needs to deviate.

**A third file is coming.** badgersbay `asset-register-identity` adds
`assets.csv`, the asset register exported from the ISO reporting sheet. It pairs
full names with hardware serials, so it belongs on the agenix track, not in the
repository.

## Scope

1. `settings` as a structured option rendered to YAML, instead of a heredoc. At
   minimum `compliance.enabled`, `audit_months`, `grace_weeks`,
   `required_reports` and the per-platform-class requirements badgersbay gained.
2. Add `assetRegisterFile` alongside `tokenFile` and `dashboardPasswordFile`,
   using the same agenix pattern.
3. Assertions: missing or unreadable secret files fail at evaluation, not when
   the service starts.
4. Update `docs/services/badgersbay.md`.

## Boundary: secrets do not go in the nix store

`pkgs.writeText` writes to the nix store, which is world-readable. Tokens and
the dashboard password must never end up there as values - not even through a
friendly-looking `tokens = [ ... ]` option.

The split this epic holds to:

    the module owns    the structure: which keys, what shape, which defaults
    agenix owns        the values: tokens, password, asset register

So `settings` does become a real option, because no secrets live in it.
`tokenFile`, `dashboardPasswordFile` and the new `assetRegisterFile` stay paths.
If the module ever needs to compose the contents of a secret, that happens at
activation from an agenix file, never through the store.

## Dependencies

- badgersbay `use-fastfetch-system-info` - determines the correct default (done)
- badgersbay `asset-register-identity` - introduces `assets.csv` (done)
- badgersbay `register-administration` - delivers the register through agenix
