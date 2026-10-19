# Proposal

Epic: [elastinix-do0e — Build Zammad from upstream GitHub source in elastinix](../../../.beans/elastinix-do0e--build-zammad-from-upstream-github-source-in-elasti.md)

## Why

The Zammad version elastinix deploys is whatever the pinned `nixos-26.05` nixpkgs ships (currently 7.1.1). The only way to move it so far has been bumping the whole nixpkgs lock on a side branch (`update-zammad`, which ships 7.1.3). compute3 in workloads consumes that branch as a second flake input. Every Zammad bump therefore drags along an unrelated nixpkgs bump, and consumers have to wire in a second elastinix input. We want to choose the Zammad tag ourselves, inside elastinix, without touching the main nixpkgs pin.

## What Changes

- Vendor the nixpkgs Zammad recipe (`package.nix`, `source.json`, `gemset.nix`, `fix-sendmail-location.diff`, `update.sh`, `update.nix`) into a new top-level `pkgs/zammad/` directory in elastinix.
- `source.json` becomes the single source of truth for the Zammad version: owner, repo, rev, hash and an explicit `version` field. `package.nix` reads `version` from it instead of hardcoding it.
- The vendored recipe starts at **Zammad 7.1.3**, the version compute3 already runs through the `update-zammad` branch. Switching it over is then a no-op upgrade, with no data migration and no downgrade.
- Adapt `update.sh` to take an explicit tag argument (`update.sh <tag>`) instead of scraping the latest version from ftp.zammad.com, and fix its stale yarn references (Zammad now uses pnpm).
- Expose the package as a flake output (`packages.<linux-system>.zammad`) so it can be built and pushed to attic on its own.
- Change the default of `elastinix.services.zammad.package` from `pkgs.zammad` to the vendored build. It is built per service with `pkgs.callPackage` inside the zammad module, not through a global overlay, so no other service or package changes.
- Document the update procedure (run `update.sh <tag>`, refresh the pnpm deps hash, build, push to attic) in `docs/services/zammad.md`.

No breaking changes. The `package` option stays, and consumers can still override it.

## Capabilities

### New Capabilities

- `zammad-package`: how elastinix builds and provides the Zammad package. Covers the vendored source-pinned recipe, where its version comes from, how it becomes the default package of the zammad service, its flake output, and the documented update procedure.

### Modified Capabilities

<!-- none: no existing spec covers the zammad service -->

## Impact

- **New files**: `pkgs/zammad/{package.nix,source.json,gemset.nix,fix-sendmail-location.diff,update.sh,update.nix}`.
- **Modified**: `modules/nixos/services/service-zammad.nix` (default of `package`), `flake.nix` (`packages` output), `docs/services/zammad.md` (new), `docs/README.md` (link), `CHANGELOG.md`.
- **Build cost**: Zammad is no longer served from cache.nixos.org. The first build compiles the asset pipeline (pnpm + rake `assets:precompile`) and the Ruby gem env, and should be pushed to the attic cache.
- **Maintenance**: elastinix now owns Zammad security bumps. Pair this with `zammad-advisory-monitor` to know when to run `update.sh`.
- **Follow-up in workloads (out of scope here)**: compute3 drops the `zammad-elastinix` input and the `package = zammadPkgs.zammad` override, then re-pins elastinix. After that the `update-zammad` branch in elastinix can be deleted.
