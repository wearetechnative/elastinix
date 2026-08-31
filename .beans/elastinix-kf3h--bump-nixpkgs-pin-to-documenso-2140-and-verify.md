---
# elastinix-kf3h
title: Bump nixpkgs pin to documenso 2.14.0 and verify migrate+boot
status: todo
type: task
priority: high
created_at: 2026-08-27T10:01:04Z
updated_at: 2026-08-27T10:01:04Z
parent: elastinix-wxy7
blocked_by:
    - elastinix-pf4x
    - elastinix-f6ee
    - elastinix-ms7p
---

Integration step: bump the nixpkgs pin so `pkgs.documenso` provides **2.14.0**, and verify that the module works end-to-end. Blocked by the three fixes (PORT patch, Playwright revision, EROFS) — those must land first, otherwise the build/runtime breaks at the bump.

## To do

- Update the nixpkgs input in `flake.nix` to a revision that contains `documenso-2.14.0`; `nix flake update nixpkgs` (or the correct input) + commit `flake.lock`
- Check that the bundled `pkgs.playwright-driver.browsers` contains a chromium-headless-shell compatible with Playwright 1.56.1 (revision ~1194) — see the Playwright story
- `nixos-rebuild build` (or the elastinix apply target) runs without errors
- Deploy to a test/non-prod host

## Verification

- Service `documenso.service` reaches `active (running)`
- `prisma migrate deploy` applies the migrations (163+ migrations on a fresh DB; on an existing 1.12.x DB only the delta)
- **Take a DB backup/snapshot before the first migrate on an existing instance** (major upgrade from 1.12.x → 2.14.0)
- Port is honored (`cfg.port`)
- Login works; uploading + signing a document works (chromium + signing cert)
- No more EROFS error (if story 3 = Option A)

## Acceptance criteria

- nixpkgs pin on 2.14.0, `flake.lock` committed
- Module builds and runs on a test host
- Migrate + boot + signing verified
