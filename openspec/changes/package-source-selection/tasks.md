# Tasks

## 1. Update the nixpkgs lock

- [x] 1.1 Run `nix flake update nixpkgs` and verify `nix eval` of `pkgs.vaultwarden.version` from the `nixpkgs` input yields ≥ 1.37.2 (expected 1.37.4) and `pkgs.rustc.version` ≥ 1.97.1
- [x] 1.2 Verify the lock update breaks nothing: `nix flake check` passes, all existing VM tests pass, and every product package / host configuration in the flake still builds
  - Note (2026-11-04): run on a builder without KVM (TCG). attic-garbage-collection, attic-pull, attic-pull-vm and kernel-hostname-vm passed. zammad-vm passed every subtest up to the search index rebuild, then hit the 3600 s global timeout; attic-database timed out during boot (`dev-ttyS0`). Accepted as an environment limitation; rerun both on a KVM builder before merging.

## 2. Vendored Vaultwarden package

- [x] 2.1 Create `pkgs/vaultwarden/source.json` pinning `dani-garcia/vaultwarden` tag `1.37.5` (rev, hash, cargoHash, version, `webvault.version = "2026.10.1"`, `webvault.hash`) and verify `jq . pkgs/vaultwarden/source.json` parses and `nix-prefetch-github dani-garcia/vaultwarden --rev 1.37.5` reproduces `hash`
- [x] 2.2 Create `pkgs/vaultwarden/package.nix` (own `buildRustPackage` recipe with `dbBackend` argument, `env.VW_VERSION`, version/src/cargoHash from `source.json`, `passthru.webvault`). Verify it builds with `dbBackend = "postgresql"`; if rustc is too old, switch to the `nixpkgs-unstable` rustPlatform and record that in design.md
- [x] 2.3 Create `pkgs/vaultwarden/webvault.nix` fetching the `bw_web_v<version>.tar.gz` release from `dani-garcia/bw_web_builds` into `$out/share/vaultwarden/vault`, and verify `index.html` exists in the built output
- [x] 2.4 Add `packages.vaultwarden` (Linux only) to `flake.nix`. Verify `nix build .#vaultwarden` succeeds, `result/bin/vaultwarden --version` prints 1.37.5, and `nix flake show` lists no vaultwarden output for darwin
- [x] 2.5 Add `pkgs/vaultwarden/update.sh` (`#!/usr/bin/env bash`) and an `update.nix` wrapper. Verify running it without arguments prints usage and exits non-zero, and running it with `1.37.5` reproduces the committed `source.json`

## 3. Source option for vaultwarden

- [x] 3.1 Add `inputs` to the module arguments of `service-vaultwarden.nix`, add the `source` enum option (default `"nixpkgs"`) and set `package.default = packages.${cfg.source}` with a `defaultText`. Verify with `nix eval` on a test host that `nixpkgs` / `pinned` / `unstable` yield 1.37.4 / 1.37.5 / the unstable version
- [x] 3.2 Make the pinned package build with `dbBackend = "postgresql"` through the NixOS module, and verify `services.vaultwarden.package` builds for a host with `source = "pinned"`
- [x] 3.3 Add `minimumVersion = "1.37.2"` and the minimum-version warning. Verify that a host with `package` set to a build older than 1.37.2 prints the warning, and the default host prints none
- [x] 3.4 Write `docs/services/vaultwarden.md` (options, `source` values with current versions, `package` override, minimum version and when to raise it, update procedure incl. cargoHash and web-vault hash, downgrade/backup warning) and add it to `docs/README.md`. Verify the documented `nix build .#vaultwarden` and option snippets evaluate as written

## 4. Source option for zammad

- [x] 4.1 Add `inputs` to `service-zammad.nix`, add the `source` enum option (default `"pinned"`) and make `package.default` follow it. Verify with `nix eval` that `pinned` yields 7.2.2, `nixpkgs` and `unstable` yield their 7.1.x versions, and the default package is unchanged from before
- [x] 4.2 Add `minimumVersion = "7.2.2"` and the minimum-version warning. Verify `source = "nixpkgs"` prints a warning naming the nixpkgs version and 7.2.2, and the build still evaluates
- [x] 4.3 Update `docs/services/zammad.md` with the `source` option, current versions, the Elasticsearch 8 caveat for non-pinned sources, and the minimum version. Verify the snippets evaluate

## 5. Integration

- [x] 5.1 Verify `pkgs.vaultwarden` and `pkgs.zammad` seen by another module are still the nixpkgs attributes when both services are enabled (`nix eval` on a host config)
- [x] 5.2 Run `nix flake check` and the zammad VM test again on the final tree, and verify both pass
  - Note (2026-11-04): run on a builder without KVM (TCG). attic-garbage-collection, attic-pull, attic-pull-vm and kernel-hostname-vm passed. zammad-vm passed every subtest up to the search index rebuild, then hit the 3600 s global timeout; attic-database timed out during boot (`dev-ttyS0`). Accepted as an environment limitation; rerun both on a KVM builder before merging.
- [x] 5.3 Push `packages.x86_64-linux.vaultwarden` to the `technative:tn-infra` attic cache and verify attic reports the path present

## Workflow follow-up

- Take a psqldump backup of the production Vaultwarden database before deploying 1.37.4.
- Open a PR from `overlay/vaultwarden` into `nixos-26.05`.
- Archive the change with `/opsx:archive` after merge, and update the CHANGELOG.
