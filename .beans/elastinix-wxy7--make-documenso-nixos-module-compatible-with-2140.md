---
# elastinix-wxy7
title: Make Documenso NixOS module compatible with 2.14.0
status: in-progress
type: epic
priority: high
created_at: 2026-08-27T10:00:41Z
updated_at: 2026-08-27T14:00:00Z
---

The NixOS module `modules/nixos/services/documenso` (`services.documenso`) is written against an older Documenso release and is **not compatible with Documenso 2.14.0**. As it stands, the package does not even *build* against 2.14.0, and even with that blocker worked around, PDF rendering breaks at runtime. This epic bundles the changes needed to get the module working on 2.14.0.

## Background

Verification done against the actual `documenso-2.14.0` from nixpkgs (store path inspected + tested locally). Findings:

| Component | Status on 2.14.0 |
|---|---|
| `--replace-fail` PORT patch in `postFixup` | ❌ **breaks the build** — target string no longer exists |
| Playwright/Chromium symlink `-1169` | ❌ **runtime** — 2.14.0 bundles Playwright 1.56.1 → expects revision `1194` |
| `[License] EROFS` write error | ⚠️ cosmetic (non-fatal) but log noise + fails every boot |
| Env-var names (jobs/redis/smtp/storage/signing/crypto/signup/telemetry) | ✅ still valid |
| Start via `bin/documenso` (prisma migrate + node main.js) | ✅ unchanged |

## Scope

Story beans (in order):

1. Remove build-breaking PORT patch (blocker)
2. Fix Playwright chromium-revision symlink (runtime)
3. Fix EROFS license-file write error (cosmetic)
4. Bump nixpkgs pin to 2.14.0 + verify migrate/boot (integration, blocked by 1–3)

## Definition of done

- `nixos-rebuild` builds the documenso module against nixpkgs with 2.14.0 without errors
- Service starts, `prisma migrate deploy` runs, port is honored
- PDF signing/rendering works (chromium found)
- No more EROFS error in the journal (or deliberately accepted + documented)

## References

- Module: `modules/nixos/services/documenso/default.nix`
- Last module change: `061350b fix: Documenso ignores port fixed` (2026-06-05)
