---
# elastinix-l16a
title: 'badgersbay module: settings as options, tokens and asset register through agenix'
status: completed
type: epic
priority: high
tags:
    - badgersbay
    - nixos
    - agenix
created_at: 2026-09-15T16:24:06Z
updated_at: 2026-09-16T16:55:15Z
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


## Done

Implemented across `bfe27f6` (the asset register, child `elastinix-9rd2`) and
this change: `settings` as a structured option rendered to YAML, assertions
that fail at evaluation, and the documentation. OpenSpec change
`2026-09-16-badgersbay-settings-option` archived, `badgersbay-service` spec
synced with three new requirements and one modified.

## Verified by evaluating, not by reading

The defaults render exactly what the heredoc they replace produced, plus two
keys the server already defaults to itself (`grace_weeks: 4`,
`per_class: {}` - `honeybadger_server.py:1389` and `:1394`), so the generated
file is behaviourally identical rather than byte-identical.

Each refusal was made to fire, one at a time:

| Configuration | Result |
|---|---|
| `configFile` only, as compute2 sets it | no assertion fires |
| `settings` only | no assertion fires |
| both | refused |
| `settings.networkport` diverging from `port` | refused |
| `settings.compliance.asset_register` | refused |
| a token file written into the store | refused |
| an `age.secretsDir` path with no `age.secrets` entry | refused |
| a declared secret root-owned at `0400` | refused |
| the same secret group-readable for the service group | no assertion fires |

The first row is the one that mattered most. compute2 sets `configFile`
wholesale and never touches `settings`; an assertion firing there would have
broken a production deploy on the next evaluation, and `highestPrio` had to
distinguish a host's definition from the option's own default for that to hold.

## Limits, recorded rather than glossed over

These assertions read the configuration, not the machine. The two agenix checks
need that module imported and are skipped without it. The readability check
judges numeric modes only - agenix hands `mode` to `chmod`, which also takes
symbolic forms - and leaves a numeric non-root `owner` alone rather than
guessing which user it names. A file that exists but holds the wrong thing is
invisible here. `docs/services/badgersbay.md` says so under **What fails at
evaluation**.

## Note for whoever deploys

compute2 locks this repo through a `path:` input, so this commit invalidates
`stack/ec2_compute2/flake.lock`. Re-lock with `--refresh` before deploying, or
deploy from the previous elastinix commit - nothing here is required for the
asset register or the vulnerable-package column.
