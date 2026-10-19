---
# elastinix-do0e
title: Build Zammad from upstream GitHub source in elastinix
status: completed
type: feature
priority: normal
created_at: 2026-10-19T08:10:58Z
updated_at: 2026-10-19T09:42:53Z
openspec-link: openspec/changes/archive/2026-10-19-zammad-source-build
---

Let elastinix build Zammad from the upstream GitHub source (`zammad/zammad`) at a tag we choose, so we no longer depend on whichever Zammad version a nixpkgs pin ships.

Origin: exploration in `technative-awsaccounts-workloads` (compute3), 2026-10-19.

## Current situation

- `modules/nixos/services/service-zammad.nix` has a `package` option, default `pkgs.zammad` (commit `12f570b`).
- The only lever used so far to change the Zammad version is a `flake.lock` bump of nixpkgs on the `update-zammad` branch (commit `9d90822`).
- compute3 in workloads consumes that branch as a second input (`zammad-elastinix`) and passes `zammadPkgs.zammad` as `package`.
- No source-build overlay has ever existed; the old workloads overlay (`25758d8`, removed in `325d083`) only added a storage symlink in `postInstall`.

## Target

- Vendor the nixpkgs Zammad recipe (`pkgs/by-name/za/zammad`: `package.nix`, `source.json`, `gemset.nix`, `update.sh`, `fix-sendmail-location.diff`) into elastinix.
- `source.json` (owner/repo/rev/hash) determines the Zammad version.
- Make it the default of `elastinix.services.zammad.package`, scoped like the documenso overlay: no other service affected.
- Document the update procedure (`update.sh <tag>`, refresh yarn offline-cache hash, build, push to attic).

## Open questions

- Starting tag: the version current nixpkgs ships, or a newer one?
- Location: under `modules/nixos/services/` next to the module, or a new top-level `pkgs/`?

## Follow-up in workloads

- compute3: drop the `zammad-elastinix` input and the `package = zammadPkgs.zammad` line; re-pin elastinix.
- Delete the `update-zammad` branch in elastinix afterwards.
