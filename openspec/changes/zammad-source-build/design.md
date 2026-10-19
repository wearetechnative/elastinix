# Design

## Context

See proposal.md (Why). Current state:

- `modules/nixos/services/service-zammad.nix` exposes `package` (default `pkgs.zammad`) and passes it to the upstream `services.zammad` module.
- The upstream NixOS module calls `cfg.package.override { dataDir = cfg.dataDir; }`. Any package we provide must therefore be created with `callPackage`, so that it has `.override` and accepts a `dataDir` argument.
- Service modules are loaded with `import-tree ../modules/nixos/services`, which imports **every** `.nix` file under that tree as a NixOS module. A recipe file such as `package.nix` or `gemset.nix` placed there would be imported as a module and break evaluation.
- Versions in play: main's nixpkgs (`8eeec93`) ships Zammad 7.1.1. The `update-zammad` branch's nixpkgs (`774debe`) ships 7.1.3, which compute3 runs today. Both use Ruby 3.4.9, and both 7.1.x recipes use the same pnpm deps hash.
- `service-zammad-advisory-monitor.nix` reads `config.elastinix.services.zammad.package.version`. It follows the new default automatically, as long as `version` is set correctly.
- The nixpkgs recipe now uses pnpm (`fetchPnpmDeps`), but its `update.sh`/`update.nix` still reference yarn (`yarn.lock`, `yarn.nix`, the `yarn` package), and the script scrapes the "latest" version from ftp.zammad.com.

## Goals / Non-Goals

**Goals:**

- Build Zammad from a pinned upstream revision, fully defined inside elastinix.
- Keep the recipe as close to the nixpkgs one as possible, so future upstream fixes can be diffed and ported easily.
- Make the switch a no-op for compute3: same Zammad version, same Ruby, same `dataDir` layout.

**Non-Goals:**

- Changing the Zammad NixOS module itself (`services.zammad`) or the elastinix zammad service options beyond the `package` default.
- Automating version bumps (CI or renovate). Bumps stay manual and are triggered by `zammad-advisory-monitor`.
- Upgrading to Zammad 7.2.x. It needs Elasticsearch ≥ 8.15, which nixpkgs does not ship, so it is tracked separately in [elastinix-gt7k](../../../.beans/elastinix-gt7k--upgrade-zammad-to-722-with-elasticsearch-815.md).
- The workloads follow-up (removing the `zammad-elastinix` input from compute3) and deleting the `update-zammad` branch.

## Decisions

### D1: Location `pkgs/zammad/` at the repo root

The recipe goes in `pkgs/zammad/`, not next to the module.

- *Why*: `import-tree` would import recipe files under `modules/nixos/services/` as modules. A top-level `pkgs/` also gives a natural home for future vendored packages, and can be referenced from both the module and `flake.nix`.
- *Alternative*: `modules/nixos/services/zammad/_pkg/`. import-tree skips paths containing `/_`, so this would work, but it relies on a subtle naming convention that is easy to break. Rejected.

### D2: Per-service `callPackage`, no overlay

In `service-zammad.nix`:

```nix
let
  zammadPackage = pkgs.callPackage ../../../pkgs/zammad/package.nix { };
in
  package.default = zammadPackage;
```

with `defaultText = lib.literalExpression "pkgs.callPackage <elastinix>/pkgs/zammad/package.nix { }"`, so the option docs don't evaluate the build.

- *Why*: this matches the documenso approach (resolve the package inside the module, no global overlay). `pkgs.zammad` stays untouched for everyone else, and `callPackage` provides the `.override { dataDir }` the upstream module needs.
- *Alternative*: `nixpkgs.overlays = [ (final: prev: { zammad = ...; }) ]`. This replaces `pkgs.zammad` host-wide and violates the scoping requirement. Rejected.

### D3: `version` lives in `source.json`

Add a `"version"` field to `source.json`. `package.nix` does `source = lib.importJSON ./source.json; version = source.version;` and passes `fetchFromGitHub (removeAttrs source [ "version" ])`.

- *Why*: one file decides the version, so the update script can't leave `package.nix` and `source.json` out of sync. It also gives `zammad-advisory-monitor` the correct version.
- *Alternative*: keep `version = "..."` hardcoded in `package.nix`, as nixpkgs does. That means two places to edit. Rejected.

### D4: Starting point is the nixpkgs `774debe` recipe (Zammad 7.1.3)

Copy `pkgs/by-name/za/zammad/*` from nixpkgs revision `774debe7a0d1b496e35677ad955a1011c6ff74f3`: rev `8facd925…`, gemset for 7.1.3, pnpm hash `sha256-JG1VhG56…`.

- *Why*: compute3 already runs 7.1.3. Starting from 7.1.1 (main's nixpkgs) would downgrade it, and Zammad does not support downgrades once migrations have run.
- *Alternative*: start at the newest upstream tag. This mixes an untested version bump into the plumbing change. Do it as the first `update.sh` run after this lands.

### D5: `update.sh <tag>` and pnpm hash refresh

Adapt the vendored script:

- Require exactly one argument, the tag. Print usage and exit non-zero otherwise. The target directory defaults to the script's own directory.
- `nix-prefetch-github zammad zammad --rev <tag> --fetch-submodules`, then add `version` with `jq`, then write `source.json`.
- Download the tarball for `<tag>` and run `bundix` to regenerate `gemset.nix`.
- Drop the dead yarn references from `update.sh` and from `update.nix` (`buildInputs`): `rm yarn.lock yarn.nix` and the `yarn` package. Also drop `xidel` and `common-updater-scripts`, which are no longer needed once the version comes from the argument.
- Leave the pnpm hash to a documented manual step: set the hash to `lib.fakeHash`, run `nix build .#zammad`, copy the `got:` hash. Automating it would need a nix build inside the script, which is fragile. The script prints this reminder at the end.

`update.nix` wraps the script with its tools (`bundix`, `jq`, `nix-prefetch-github`, `curl`, `gnutar`). It is exposed as `passthru.updateScript`, and the docs show it run via `nix run`/`nix-shell`. Nothing else consumes `passthru.updateScript`.

### D6: Flake output via `perSystem`

In `flake.nix` `perSystem`:

```nix
packages = lib.optionalAttrs pkgs.stdenv.isLinux {
  zammad = pkgs.callPackage ./pkgs/zammad/package.nix { };
};
```

Darwin systems get no `zammad` output (the recipe's `meta.platforms` is Linux-only, and the build needs PostgreSQL/Valkey in the sandbox). This is the same guard the existing `checks` use.

The flake output and the module default both use `callPackage` on the same file with the same nixpkgs. On a given host they evaluate to the same derivation, so a `nix build .#zammad` + attic push warms the cache for host deploys.

## Risks / Trade-offs

- [No cache.nixos.org hit; long first build (Ruby gems + `assets:precompile`)] → Build `.#zammad` once per bump and push to attic before deploying. This is part of the documented procedure.
- [The vendored recipe drifts from nixpkgs fixes (e.g. Ruby version bumps in nixos-26.05 that break the gemset)] → The recipe is kept close to nixpkgs so `diff -r` against `pkgs/by-name/za/zammad` stays readable. The postPatch `sed` already aligns Gemfile/Gemfile.lock with `${ruby.version}`. A broken build after a nixpkgs bump surfaces in `nix build .#zammad`.
- [Derivation hash differs from what compute3 gets today via `update-zammad` (different nixpkgs → different deps)] → This is expected: same Zammad version, rebuilt closure, one rebuild on deploy. There is no data or schema change.
- [Elastinix now owns Zammad security bumps] → `zammad-advisory-monitor` already alerts on advisories that affect our version. The update procedure is a single script plus a hash refresh.
- [`update.sh` depends on network tools and on bundix behaving on the new lockfile] → It runs manually by an operator, never in a build. Its failures are loud and leave the tree for `git diff`/`git checkout` review.

## Migration Plan

1. Land this change in elastinix and build `.#zammad`, then push it to attic.
2. Hosts that use the default `package` get Zammad 7.1.3 from the vendored recipe on their next elastinix re-pin.
3. compute3 (workloads, separate change): remove the `zammad-elastinix` input and the `package = zammadPkgs.zammad` line, re-pin elastinix, deploy. The version stays 7.1.3.
4. Delete the `update-zammad` branch in elastinix.

Rollback: set `elastinix.services.zammad.package = pkgs.zammad;` (or the previous override) on the host, or revert the elastinix pin. The data stays compatible as long as the version is not lower than 7.1.3.
