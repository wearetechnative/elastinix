## 1. Module: per-service unstable sourcing

- [x] 1.1 Add an `unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}` binding in the module's `let` in `modules/nixos/services/documenso/default.nix`
- [x] 1.2 Set the `services.documenso.package` option default to `unstable.documenso` (stock, no override) and update `defaultText`/`description` accordingly
- [x] 1.3 Point the build-time Playwright `runCommand` bridge at `unstable.playwright-driver.browsers` instead of `pkgs.playwright-driver.browsers`
- [x] 1.4 Remove the `config.nixpkgs.overlays = [ … ]` block (the `documenso` + `playwright-driver` overlay)
- [x] 1.5 Remove the `documenso.overrideAttrs` license-symlink `postFixup`

## 2. Documentation

- [x] 2.1 Document in `docs/services/documenso.md` that the boot-time `EROFS` license-write log line is expected and harmless (community edition, `NOT_FOUND`)

## 3. Verification

> Note: elastinix is a library flake (no `nixosConfigurations`). Tasks 3.1–3.4
> must be run from the downstream deployment repo that consumes this module,
> against the non-prod host — this is a major 1.12.x → 2.14.0 upgrade, so take a
> DB backup/snapshot before the first `prisma migrate deploy`.

- [ ] 3.1 Build the service on a cache-connected host and confirm `documenso` is substituted from the binary cache (not compiled locally) — *downstream repo*
- [ ] 3.2 Confirm host-wide `pkgs.documenso` / `pkgs.playwright-driver` remain on the pinned `nixos-26.05` channel (no overlay leakage) — *downstream repo*
- [ ] 3.3 Deploy to a non-prod host; confirm `documenso.service` reaches `active (running)` and logs `Derived Status: NOT_FOUND` — *downstream repo*
- [ ] 3.4 Confirm the port is honored and a document uploads + signs (chromium found, PDF renders) — *downstream repo*
- [x] 3.5 Run `openspec validate documenso-per-service-unstable --strict` and confirm it passes
