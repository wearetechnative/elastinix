## 1. Module: per-service unstable sourcing

- [ ] 1.1 Add an `unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}` binding in the module's `let` in `modules/nixos/services/documenso/default.nix`
- [ ] 1.2 Set the `services.documenso.package` option default to `unstable.documenso` (stock, no override) and update `defaultText`/`description` accordingly
- [ ] 1.3 Point the build-time Playwright `runCommand` bridge at `unstable.playwright-driver.browsers` instead of `pkgs.playwright-driver.browsers`
- [ ] 1.4 Remove the `config.nixpkgs.overlays = [ … ]` block (the `documenso` + `playwright-driver` overlay)
- [ ] 1.5 Remove the `documenso.overrideAttrs` license-symlink `postFixup`

## 2. Documentation

- [ ] 2.1 Document in `docs/services/documenso.md` that the boot-time `EROFS` license-write log line is expected and harmless (community edition, `NOT_FOUND`)

## 3. Verification

- [ ] 3.1 Build the service on a cache-connected host and confirm `documenso` is substituted from the binary cache (not compiled locally)
- [ ] 3.2 Confirm host-wide `pkgs.documenso` / `pkgs.playwright-driver` remain on the pinned `nixos-26.05` channel (no overlay leakage)
- [ ] 3.3 Deploy to a non-prod host; confirm `documenso.service` reaches `active (running)` and logs `Derived Status: NOT_FOUND`
- [ ] 3.4 Confirm the port is honored and a document uploads + signs (chromium found, PDF renders)
- [ ] 3.5 Run `openspec validate documenso-per-service-unstable --strict` and confirm it passes
