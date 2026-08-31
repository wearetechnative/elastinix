## Why

The Documenso module currently forks `documenso` via `overrideAttrs` (a `postFixup` that symlinks the license cache into `stateDir`, commit `8549ae5`) purely to silence a cosmetic `EROFS` log line. Forking the derivation changes its hash, so the prebuilt `documenso-2.14.0` in the binary cache is never used and the entire pnpm/Node build is compiled locally on every rebuild. The same module also injects `documenso` and `playwright-driver` through a module-global `nixpkgs.overlays` block, which replaces those packages host-wide rather than only for the service that needs them. Sourcing both packages per-service straight from the `nixpkgs-unstable` input and dropping the override restores the cache hit and narrows the scope, at the cost of one non-fatal log line.

Epic bean: [.beans/elastinix-wxy7--make-documenso-nixos-module-compatible-with-2140.md](../../../.beans/elastinix-wxy7--make-documenso-nixos-module-compatible-with-2140.md)

## What Changes

- **Source Documenso 2.14.0 per-service from `nixpkgs-unstable`, not via an overlay.** Bind `unstable = inputs.nixpkgs-unstable.legacyPackages.${system}` in the module and set `services.documenso.package` to `unstable.documenso`. Remove the `config.nixpkgs.overlays = [ … ]` block. `pkgs.documenso` and `pkgs.playwright-driver` on the host stay on `nixos-26.05`; only the service references the unstable packages.
- **Remove the license-file `overrideAttrs`.** Documenso is used unmodified, so its derivation hash matches Hydra's and the package is fetched prebuilt from `cache.nixos.org` instead of being rebuilt locally.
- **Playwright browser bridge draws from the same unstable input.** The build-time `runCommand` bridge references `unstable.playwright-driver.browsers` so the chromium-headless-shell revision Documenso expects and the one nixpkgs ships come from a single, mutually-consistent release.
- **Accept and document the EROFS license-write log line (ms7p Option B).** On boot Documenso logs a non-fatal `EROFS: read-only file system` when its license client tries to cache `.documenso-license.json` into the read-only store (the bundled `bin/documenso` wrapper `cd`s into the store). The license check itself succeeds (`Derived Status: NOT_FOUND` = community edition) and the service works normally. Document this line in `docs/services/documenso.md` as expected and harmless instead of forking the package to suppress it.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `nixos-documenso-service`: How the Documenso and Playwright packages are sourced changes from a module-global `nixpkgs.overlays` override (forked `documenso` via `overrideAttrs`) to a per-service reference into the `nixpkgs-unstable` input using the stock, unmodified packages. A requirement is added that the cosmetic EROFS license-write log line is accepted and documented rather than suppressed by patching the package.

## Impact

- **Code**: `modules/nixos/services/documenso/default.nix` — remove `nixpkgs.overlays` block and the `documenso.overrideAttrs` license symlink; add an `unstable` let-binding; point `package` default and the Playwright `runCommand` bridge at `unstable.*`.
- **Docs**: `docs/services/documenso.md` — document the expected, harmless EROFS license-write log line.
- **Dependencies**: reuses the existing `nixpkgs-unstable` flake input; no new inputs. `flake.lock` already pins the unstable revision. Main `nixpkgs` stays on `nixos-26.05`; no other service is affected.
- **Build/deploy**: `documenso` is fetched prebuilt from the binary cache (no local pnpm/Node build). Runtime behaviour is unchanged except the EROFS log line reappears; PDF signing/rendering and license status (`NOT_FOUND`, community) are unaffected.
