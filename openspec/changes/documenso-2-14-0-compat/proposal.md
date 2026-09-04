## Why

The `services.documenso` NixOS module was written against Documenso 1.12.x and is not compatible with Documenso 2.14.0. Verified against the real `documenso-2.14.0` package: as-is the module does not even *build* against 2.14.0, and with that blocker bypassed PDF rendering breaks at runtime. Bumping nixpkgs to a revision carrying 2.14.0 (a major upgrade already needed for the wider platform) is blocked until the module is made compatible.

Epic bean: [.beans/elastinix-wxy7--make-documenso-nixos-module-compatible-with-2140.md](../../../.beans/elastinix-wxy7--make-documenso-nixos-module-compatible-with-2140.md)

## What Changes

- **BREAKING (build): Remove the PORT `postFixup` patch.** The module's `pkgs.documenso.overrideAttrs` runs `substituteInPlace ... --replace-fail` against a string that no longer exists in 2.14.0, so the package build fails. 2.14.0 honours `PORT` natively (verified), so the override is both broken and unnecessary. The module will use `pkgs.documenso` directly.
- **Playwright browser provisioning moves from runtime to build time.** The runtime `ExecStartPre` symlink dance (`mkdir`/`chown`/`ls | grep | head`/`ln` into `stateDir`) is replaced by a pure `pkgs.runCommand` derivation that mirrors the stock `pkgs.playwright-driver.browsers` and adds a correctly-named `chromium_headless_shell-<rev>` entry, where `<rev>` is read at build time from the packaged `playwright-core/browsers.json`. `PLAYWRIGHT_BROWSERS_PATH` points directly at that read-only store path. The build fails loudly if the driver contains no chromium-headless-shell. This fixes the hardcoded `1169` revision (2.14.0's Playwright 1.56.1 expects 1194) and makes the bridge self-correcting across future nixpkgs/Playwright bumps.
- **EROFS license-write log line: accepted and documented.** On every boot Documenso logs a non-fatal `EROFS` error trying to write `.documenso-license.json` into the read-only store (the bundled `bin/documenso` wrapper `cd`s into the store). The license check itself succeeds (community edition). We keep the supported bundled start wrapper and document that this log line is expected and harmless, rather than forking `ExecStart` into a hand-rolled wrapper.
- **2.14.0 sourced from a scoped `nixpkgs-unstable` input.** `documenso-2.14.0` exists only in `nixpkgs-unstable`; the platform is pinned to `nixos-26.05`, which carries only 1.12.6 and will not backport a major version. So rather than a same-channel bump (impossible) or moving the whole platform to unstable (huge blast radius), a dedicated `nixpkgs-unstable` input + overlay pulls **only** `documenso` (and the `playwright-driver` the browser bridge consumes) from unstable. `flake.lock` pins the unstable revision; the module is verified end to end (build, migrate, boot, port, signed-PDF render).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `nixos-documenso-service`: Playwright browser availability and version-compatibility requirements change from a runtime `ExecStartPre` symlink into `stateDir` (hardcoded revision 1169) to a build-time derivation whose revision is derived from the packaged Playwright, with `PLAYWRIGHT_BROWSERS_PATH` pointing at the store. New requirements are added for using the stock `pkgs.documenso` package (no `postFixup`), 2.14.0 runtime compatibility (native `PORT`), and the accepted-and-documented EROFS license-write behaviour.

## Impact

- **Code**: `modules/nixos/services/documenso/default.nix` (package option, `ExecStartPre`, service `environment`, new `runCommand` derivation).
- **Docs**: `docs/services/documenso.md` (document the expected EROFS log line).
- **Dependencies**: new `nixpkgs-unstable` input in `flake.nix` + overlay selecting `documenso` (and `playwright-driver`) from it; `flake.lock` committed pinning that revision. Main `nixpkgs` stays on `nixos-26.05`; all other services are unaffected. Relies on stock `playwright-driver.browsers` (no custom driver *build*, just the unstable source), renamed by the build-time bridge.
- **Deployment**: Major upgrade 1.12.x → 2.14.0. Requires a DB backup/snapshot before the first `prisma migrate deploy` on an existing instance. Signing/rendering correctness must be verified on a test host before production (the original nixpkgs pin was introduced because documents were not signed correctly).
