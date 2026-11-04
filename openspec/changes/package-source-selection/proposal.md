# Proposal

## Why

The Vaultwarden version that elastinix deploys is whatever the main `nixpkgs` input carries, and there is no documented way to choose another build per host. Zammad has the opposite problem: it is locked to its source-pinned recipe, with no simple fallback to the stock nixpkgs or nixpkgs-unstable build. We want one uniform, documented switch per service to choose where the package comes from, plus a source-pinned upstream build for Vaultwarden to use when nixpkgs lags behind a release we need.

The `nixpkgs` lock is also stale: it yields Vaultwarden 1.36.0, while production (vaultwarden.technative.eu) already runs 1.37.2. Deploying the current default would downgrade production.

## What Changes

- New `source` option on `elastinix.services.vaultwarden` and `elastinix.services.zammad`: `lib.types.enum [ "pinned" "nixpkgs" "unstable" ]`.
  - `"pinned"`: build from upstream GitHub via `fetchFromGitHub`, at the revision recorded in `pkgs/<name>/source.json`.
  - `"nixpkgs"`: `pkgs.<name>` from the main `nixpkgs` input (nixos-26.05).
  - `"unstable"`: `<name>` from the `nixpkgs-unstable` flake input.
- Per-service defaults: Vaultwarden `"nixpkgs"`, Zammad `"pinned"` (Zammad behavior unchanged).
- The existing `package` option stays as the explicit escape hatch; its default becomes the package selected by `source`.
- Each service declares a minimum version: the oldest release allowed to run against its production database (Vaultwarden 1.37.2, Zammad 7.2.2). The module emits a NixOS warning when the effective package is older (database migrations are forward-only).
- New vendored Vaultwarden recipe in `pkgs/vaultwarden/` following the zammad pattern: `source.json` (owner, repo, rev, hash, cargoHash, version, web-vault version and hash) pinning **1.37.5** with web-vault **v2026.10.1**, a tag-driven `update.sh`, and a flake output `packages.<system>.vaultwarden`.
- Update the `nixpkgs` input in `flake.lock` so that `source = "nixpkgs"` yields Vaultwarden 1.37.4 (≥ production's 1.37.2) and a rustc that satisfies Vaultwarden 1.37.5's minimum (1.97.1).

## Capabilities

### New Capabilities
- `package-source-selection`: the `source` option contract shared by elastinix services that vendor a package: allowed values, how each maps to a package, per-service defaults, interaction with `package`, and minimum-version warnings.
- `vaultwarden-package`: the source-pinned Vaultwarden recipe (server and web-vault), its single source of truth, flake output and update procedure.

### Modified Capabilities
- `zammad-package`: the "Default package of the zammad service" requirement changes. The default of `package` now follows `source` (default `"pinned"`) instead of always being the vendored build.

## Impact

- Code: `modules/nixos/services/service-vaultwarden.nix`, `modules/nixos/services/service-zammad.nix`, new `pkgs/vaultwarden/`, `flake.nix` (`packages.vaultwarden`), `flake.lock` (`nixpkgs`).
- Inputs: reuses the existing `nixpkgs` and `nixpkgs-unstable`; no new flake inputs. Both modules need the `inputs` module argument (already used by documenso).
- The `nixpkgs` lock update affects every service and every host built from elastinix. It must be checked with `nix flake check` and the existing VM tests.
- Hosts: Vaultwarden hosts move from the stale 1.36.0 to 1.37.4 (an upgrade relative to production's 1.37.2). Zammad hosts are unchanged.
- Docs: new `docs/services/vaultwarden.md`, updated `docs/services/zammad.md`, `docs/README.md` index.
- Binary cache: the pinned Vaultwarden is not on cache.nixos.org; push it to the `technative:tn-infra` attic cache when it is used.
- Work happens on branch `overlay/vaultwarden`.
