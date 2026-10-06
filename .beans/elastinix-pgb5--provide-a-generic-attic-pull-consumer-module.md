---
# elastinix-pgb5
title: Provide a generic Attic pull-consumer module
status: completed
type: feature
priority: normal
created_at: 2026-09-30T07:22:18Z
updated_at: 2026-09-30T10:11:25Z
openspec-link: openspec/changes/archive/2026-09-30-attic-pull-consumer
---

Move the Attic pull-consumer logic out of `technative-awsaccounts-workloads` into elastinix, as a generic NixOS module next to the existing atticd module.

Origin: review comment on technative-awsaccounts-workloads PR #222 ("Can and should this be moved to elastinix?") on `lib/ec2nix/nix-lib/attic-pull.nix`.

## What the module does today (in workloads)

`workloads.atticPull` makes a host a pull consumer of a private Attic cache. Three settings have to move together, and getting one wrong fails quietly (a deploy that is merely slower):

- `nix.settings.substituters` — `mkAfter` the cache URL (`<endpoint>/<cache>`); a bare assignment drops cache.nixos.org
- `nix.settings.trusted-public-keys` — `mkAfter` the cache's public key
- `nix.settings.netrc-file` — points at an age-decrypted secret that already contains a ready-made netrc (`machine <host>` / `password <JWT>`), owner root, mode 400

Endpoint, cache name and public key currently come from `tfvars` (`infra_environments/<env>/<env>.tfvars.json`), which is workloads-specific.

## Target

- New option set, e.g. `elastinix.attic.pull` with `enable`, `endpoint`, `cache`, `publicKey`, `netrcFile` (a path to an already decrypted file, so the module stays agenix-agnostic, or an age file option — decide during design)
- Assertions for missing values, as in the current module
- No knowledge of tfvars or of the workloads repository; the workloads stacks keep only the glue that fills the options from tfvars and the per-host age secret

## Follow-up in workloads

- Replace `lib/ec2nix/nix-lib/attic-pull.nix` with the elastinix module in every compute hostconf
- Re-pin elastinix in every `stack/*` flake

Out of scope: `packages_listing_deploy_wrapper.nix` and `attic-reconcile.sh` stay in workloads (workstation-side deploy wrapper and a check against the repo's own token ledger).
