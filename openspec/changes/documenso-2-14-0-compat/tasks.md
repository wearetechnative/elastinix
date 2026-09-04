## 1. Remove the build-breaking PORT patch (bean pf4x)

- [x] 1.1 In `modules/nixos/services/documenso/default.nix`, drop the `overrideAttrs`/`postFixup` block from the `package` option default; set it to `pkgs.documenso`
- [x] 1.2 Update the `package` option `description` to remove the mention of the port patch
- [x] 1.3 Confirm the module still writes `PORT` into the generated `.env` (env-file generator, `documenso-env` service) — no change needed, just verify

## 2. Build-time Playwright browsers derivation (bean f6ee)

- [x] 2.1 Add a `let`-bound `playwrightBrowsers = pkgs.runCommand "documenso-playwright-browsers" { nativeBuildInputs = [ pkgs.jq ]; } ''…''` derivation that: symlinks the contents of `${pkgs.playwright-driver.browsers}` into `$out`; reads the expected revision from `${cfg.package}/node_modules/playwright-core/browsers.json` via `jq -r '.browsers[]|select(.name=="chromium-headless-shell").revision'`; locates the actual `chromium_headless_shell-*` in the driver; and creates `$out/chromium_headless_shell-<expected>` pointing at it
- [x] 2.2 Make the derivation fail loudly (non-zero exit, clear message) if no `chromium_headless_shell-*` exists in `pkgs.playwright-driver.browsers`
- [x] 2.3 Set `PLAYWRIGHT_BROWSERS_PATH = playwrightBrowsers;` in the service `environment` (point directly at the store path); keep `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1"` and `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1"`
- [x] 2.4 Remove the runtime `ExecStartPre` playwright-setup script (the `mkdir`/`chown`/`ls | grep | head`/`ln` block) entirely; keep the conditional certificate-generation `ExecStartPre` intact
- [x] 2.5 Remove the now-unused `stateDir/.cache/ms-playwright` handling and any related `ReadWritePaths`/tmpfiles entry that only existed for the browser cache (verify nothing else depends on it) — verified: only the ExecStartPre created `.cache`; `stateDir` tmpfiles/ReadWritePaths remain for cert + `.env`

## 3. EROFS license-write: accept + document (bean ms7p, Path 1)

- [x] 3.1 Keep `ExecStart = "${cfg.package}/bin/documenso"` (do NOT rewrite into a hand-rolled wrapper) — eval-confirmed `ExecStart` resolves to `…/documenso-2.14.0/bin/documenso`
- [x] 3.2 In `docs/services/documenso.md`, add a note that the `[License] Failed to save license file: EROFS` log line on boot is expected and harmless (license check succeeds → community edition), caused by the vendored wrapper `cd`ing into the read-only store

## 4. Source 2.14.0 from scoped nixpkgs-unstable (bean kf3h)

> Prerequisite for build-verifying groups 1–2: `documenso-2.14.0` is only in `nixpkgs-unstable`, not in the pinned `nixos-26.05`. Do this before relying on a green build of the module edits.

- [x] 4.1 Add a `nixpkgs-unstable` input to `flake.nix` (`github:NixOS/nixpkgs/nixpkgs-unstable`); commit the pinned revision in `flake.lock`. Do NOT change the main `nixpkgs` (`nixos-26.05`) — locked to `ac6b2166` (2026-08-25)
- [x] 4.2 Add an overlay (applied to the main nixpkgs used by elastinix) that sets `documenso` — and `playwright-driver` — from the `nixpkgs-unstable` input, so `pkgs.documenso` resolves to 2.14.0 and `pkgs.playwright-driver.browsers` comes from the same unstable era
- [x] 4.3 Confirm `pkgs.documenso.version` is `2.14.0` and that `pkgs.playwright-driver.browsers` contains a `chromium_headless_shell-*` (note the revision) — verified: documenso **2.14.0**; unstable playwright-driver **1.61.1** ships chromium **1228**; documenso expects **1194** → bridge renames 1228→1194 (newer-than-expected, the prod-proven direction; see design D5)
- [ ] 4.4 `nixos-rebuild build` (or the elastinix apply target) — confirm the module and the `playwrightBrowsers` derivation build with no errors, and that no other service was pulled onto unstable  *(eval-level verified: module evaluates clean in a `nixosSystem` harness, `PLAYWRIGHT_BROWSERS_PATH` resolves to the `documenso-playwright-browsers` derivation, `ExecStartPre` count = 0; full realization deferred to the test-host build in group 5 — needs the chromium/documenso closure)*

## 5. End-to-end verification on a test host (bean kf3h)

- [ ] 5.1 **Back up / snapshot the DB before the first `prisma migrate deploy`** on any existing (1.12.x) instance
- [ ] 5.2 Deploy to a non-prod/test host; confirm `documenso.service` reaches `active (running)`
- [ ] 5.3 Confirm `prisma migrate deploy` applied migrations (163+ on a fresh DB; delta on an existing DB)
- [ ] 5.4 Confirm the configured `cfg.port` is honoured
- [ ] 5.5 Log in, upload a document, **sign it, and visually verify the rendered signature output** (proves chromium found + signing correctness — the original pin's failure mode)
- [ ] 5.6 Confirm no chromium/playwright "browser not found" errors in `journalctl -u documenso`; confirm EROFS line is the only license-related noise (expected)

## 6. OpenSpec bookkeeping

- [x] 6.1 Set bean `elastinix-wxy7` status to `in-progress` and `updated_at` to today (frontmatter only)
- [x] 6.2 Run `openspec validate documenso-2-14-0-compat --strict` and resolve any issues — valid
