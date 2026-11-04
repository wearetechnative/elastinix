# Design

## Context

- `service-zammad.nix` defaults `package` to `pkgs.callPackage ../../../pkgs/zammad/package.nix { }` (vendored 7.2.2, see `zammad-package` spec). nixos-26.05 ships Zammad 7.1.1, nixpkgs-unstable 7.1.2.
- `service-vaultwarden.nix` defaults `package` to `pkgs.vaultwarden`. With the current `flake.lock`: nixos-26.05 → 1.36.0, nixpkgs-unstable → 1.37.2. Current upstream heads: nixos-26.05 → 1.37.4, nixpkgs-unstable → 1.37.5. Production (vaultwarden.technative.eu `/api/version`) runs **1.37.2**.
- The locked nixos-26.05 has rustc 1.95.0. Vaultwarden 1.37.5 declares `rust-version = "1.97.1"` (toolchain file: 1.99.1) and targets web-vault `v2026.10.1`. Current nixos-26.05 carries Rust 1.98.
- `nixpkgs-unstable` is already a flake input, consumed per service by documenso via `inputs.nixpkgs-unstable.legacyPackages.${system}` (no overlay). Modules receive `inputs` as a module argument.
- The project rule "prefer flake inputs over fetchFromGitHub" is deliberately set aside here, as it was for zammad. The requirement is one version-pinning data file per package, editable without touching `flake.lock`.

## Goals / Non-Goals

**Goals:**
- One identical `source` contract for both services, implemented with the same few lines in each module.
- Pinned Vaultwarden fully independent of the `vaultwarden` attribute of any nixpkgs input.
- No downgrade of production Vaultwarden (1.37.2) by default.

**Non-Goals:**
- A generic library function or module factory for "vendored packages". Two services do not justify the abstraction yet.
- Rolling the `source` option out to other services (documenso, attic, …).
- Changing Elasticsearch selection for zammad. `elasticsearchPackage` stays vendored regardless of `source`.
- Automating database backups before a downgrade. The module only warns.

## Decisions

### D1: Selection inside the module, keyed by an attrset

Each module builds:

```nix
unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
packages = {
  pinned   = pkgs.callPackage ../../../pkgs/<name>/package.nix { };
  nixpkgs  = pkgs.<name>;
  unstable = unstable.<name>;
};
```

and sets `package.default = packages.${cfg.source}` with a `defaultText` describing the mapping. Attrsets are lazy, so only the selected package is evaluated and built. The `source` default differs per service (`"nixpkgs"` for vaultwarden, `"pinned"` for zammad), so existing zammad behavior is preserved.

*Alternative*: a module-global overlay exposing `pkgs.<name>-pinned`. Rejected: both specs forbid changing `pkgs` for other modules, and the documenso precedent is per-service.

*Alternative*: drop `package` and only keep `source`. Rejected: `package` is the existing public API and the escape hatch for custom builds.

### D2: Minimum version, not pinned version, as the warning threshold

Each module defines `minimumVersion` in its `let` block (vaultwarden `"1.37.2"`, zammad `"7.2.2"`): the oldest release allowed against the production database. The warning is `lib.optional (lib.versionOlder cfg.package.version minimumVersion) "…"`.

*Alternative*: compare against the pinned version in `source.json`. Rejected: with `nixpkgs` as vaultwarden default, nixpkgs (1.37.4) is routinely a little behind the pin (1.37.5), so the warning would fire on every host and be ignored. The minimum is raised by hand when production is upgraded past it; this is documented.

A warning, not an assertion: deliberate rollbacks with a restored backup must remain possible.

### D3: Vendored Vaultwarden as an own recipe, not `overrideAttrs`

`pkgs/vaultwarden/package.nix` is a copy of the nixpkgs recipe (`buildRustPackage`, `dbBackend` argument, `env.VW_VERSION`), reading `version`, `src` and `cargoHash` from `source.json`. The upstream NixOS module applies `.override { dbBackend }` to whatever package it receives, so the argument must exist.

It builds with `rustPackages_1_98.rustPlatform` from the main nixpkgs. Even after the lock update, the default `rustc` of nixos-26.05 is 1.95.0, below Vaultwarden's `rust-version` 1.97.1. nixos-26.05 also carries `rustPackages_1_97` and `rustPackages_1_98`, so `nixpkgs-unstable` is not needed for the toolchain.

*Alternative*: `pkgs.vaultwarden.overrideAttrs { src; cargoHash; }`. Rejected: it couples the pinned build to whatever recipe nixos-26.05 carries, which the spec requires to be independent, and cargo vendor overrides through `overrideAttrs` are brittle.

### D4: Web-vault from the upstream prebuilt release tarball

`pkgs/vaultwarden/webvault.nix` fetches `bw_web_v<version>.tar.gz` from the `dani-garcia/bw_web_builds` GitHub releases (`fetchzip`) and installs it to `$out/share/vaultwarden/vault`, the layout the NixOS module expects for `WEB_VAULT_FOLDER`. It is exposed as `passthru.webvault`. The releases are not published under `vaultwarden/vw_web_builds` (404), which is where nixpkgs takes its source.

The upstream NixOS module takes the web vault from its own option `services.vaultwarden.webVaultPackage`, which defaults to `pkgs.vaultwarden.webvault`, not from `package`. The elastinix module sets it to `cfg.package.webvault or pkgs.vaultwarden.webvault`, so server and web vault follow `source` together.

*Alternative*: rebuild the web-vault from `bitwarden/clients` plus the bw_web_builds patches with `buildNpmPackage`, as nixpkgs does. Rejected for now: a large npm build whose result is what upstream already publishes.

### D5: `source.json` shape for Vaultwarden

```json
{
  "owner": "dani-garcia", "repo": "vaultwarden",
  "rev": "1.37.5", "hash": "sha256-…",
  "cargoHash": "sha256-…",
  "version": "1.37.5",
  "webvault": { "version": "2026.10.1", "hash": "sha256-…" }
}
```

The recipe passes only `owner/repo/rev/hash` to `fetchFromGitHub`, using the same `removeAttrs` approach as zammad.

### D6: `update.sh` for Vaultwarden

Same shape as zammad's. It takes a tag, uses `nix-prefetch-github` for `rev/hash`, reads `vault_version` from `docker/DockerSettings.yaml` at that tag, prefetches the web-vault tarball hash, and writes `source.json` atomically. It then tells the operator to set `cargoHash = ""`, run `nix build .#vaultwarden` and paste the `got:` hash. `update.nix` wraps it with its runtime dependencies (curl, jq, yq, nix-prefetch-github).

### D7: Update the `nixpkgs` lock in this change

`nix flake update nixpkgs` is part of this change. It is required for two reasons: the new vaultwarden default must yield ≥ 1.37.2 (the lock gives 1.36.0, head gives 1.37.4), and the pinned 1.37.5 needs rustc ≥ 1.97.1 (the lock gives 1.95.0). It is done first, so later tasks build against the new lock.

*Alternative*: a separate change for the lock update. Rejected: without it this change would downgrade production by default.

## Risks / Trade-offs

- [The `nixpkgs` lock update touches every service and host] → run `nix flake check`, all VM tests (attic, zammad, …) and build each `nixosConfigurations` / product package before merging; review the nixos-26.05 changelog range for breaking module changes.
- [Rust 1.98 is below Vaultwarden's toolchain file (1.99.1)] → only `rust-version` (1.97.1) is binding for cargo. The update procedure says to raise `rustPackages_1_98` when a release needs more.
- [The nixpkgs lock update changed the pnpm fetcher output, so zammad's `pnpmDeps.hash` changed] → hash updated in `pkgs/zammad/package.nix`; the zammad VM test covers the result.
- [`minimumVersion` goes stale when production is upgraded] → documented in the service docs as a step of every production upgrade.
- [Pinned builds are not on cache.nixos.org, so every host compiles Vaultwarden when `source = "pinned"`] → push `packages.x86_64-linux.vaultwarden` to the `technative:tn-infra` attic cache.
- [`source = "nixpkgs"` or `"unstable"` for zammad yields 7.1.x, below the minimum 7.2.2 and possibly incompatible with the vendored Elasticsearch 8] → minimum-version warning; documented; not blocked.
- [`unstable` follows whatever `nixpkgs-unstable` is locked to, shared with documenso] → updating that input for one service moves the other; documented.

## Migration Plan

1. Update `nixpkgs` in `flake.lock` and confirm `pkgs.vaultwarden.version` is ≥ 1.37.2.
2. Merge `overlay/vaultwarden` into `nixos-26.05` once all checks pass.
3. Deploy: vaultwarden hosts go 1.37.2 → 1.37.4 (default `nixpkgs`). Zammad hosts need no change.
4. Rollback: revert the merge. Vaultwarden 1.37.2 can only run against the database if 1.37.4 did not migrate the schema; otherwise restore the psqldump backup taken before the deploy.
