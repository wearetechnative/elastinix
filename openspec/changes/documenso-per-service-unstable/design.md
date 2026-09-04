## Context

See proposal.md — Why. The module already carries a `nixpkgs-unstable` input because Documenso 2.14.0 exists only there (`nixos-26.05` ships 1.12.x). Two implementation choices from the earlier 2.14.0 work are revisited here:

1. **Sourcing** — 2.14.0 is currently injected via a module-global `config.nixpkgs.overlays` block that replaces `documenso` and `playwright-driver` host-wide.
2. **EROFS** — a `documenso.overrideAttrs` (`postFixup` symlink into `stateDir`, commit `8549ae5`) was added to silence the boot-time `EROFS` license-cache write.

Grounded findings from the running non-prod instance and upstream source:
- Documenso's `LicenseClient` POSTs to `https://license.documenso.com/api/license` on boot, derives `NOT_FOUND` for a keyless community instance, then tries to cache the result to `path.join(process.cwd(), '.documenso-license.json')`. The bundled `bin/documenso` wrapper `cd`s into the read-only store, so the cache write fails with `EROFS`. The check itself logs `License check completed successfully`.
- `overrideAttrs` changes the derivation hash, so the prebuilt `documenso` in `cache.nixos.org` is bypassed and the full pnpm/Node build runs locally.

## Goals / Non-Goals

**Goals:**
- Restore the binary-cache hit for `documenso` (no local build).
- Narrow the version override to the service instead of the whole host.
- Keep Documenso↔Playwright revision matching intact.

**Non-Goals:**
- Suppressing or fixing the EROFS log line (explicitly accepted).
- Changing the license phone-home behavior (egress control is a separate concern).
- Touching the Playwright build-time bridge's revision-derivation logic (owned by the `documenso-2-14-0-compat` change); only its package source moves to `unstable`.

## Decisions

### Decision 1: Per-service reference into the input, not an overlay
Bind `unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}` in the module's `let`, set `services.documenso.package` default to `unstable.documenso`, and point the Playwright bridge at `unstable.playwright-driver`. Remove the `config.nixpkgs.overlays` block.

- **Why over the overlay**: an overlay mutates the host's whole package set — every `pkgs.documenso`/`pkgs.playwright-driver` on the host becomes the unstable version, which is a surprising side effect for anything else on the box. A per-service reference is surgical: only the service sees unstable; the rest of `nixos-26.05` is untouched.
- **Alternative — keep the overlay**: valid on a dedicated appliance where nothing else uses those packages, but it couples host-wide behavior to a single service's needs for no benefit.
- **Alternative — bump main nixpkgs**: rejected upstream already (moves the entire platform off `nixos-26.05`).

### Decision 2: Use stock Documenso (drop overrideAttrs) and accept EROFS
Remove the license-symlink `overrideAttrs`. Because the derivation is then identical to upstream, the package is substituted prebuilt from the binary cache. The only consequence is the EROFS license-write log line returns on every boot.

- **Why acceptable**: the failed write is a *cache* write of an irrelevant `NOT_FOUND` result. The license check succeeds, the service runs, PDFs sign and render. It is cosmetic log noise (ms7p Option B).
- **The trade-off in one line**: `overrideAttrs` gave a clean log at the cost of a full local rebuild; stock gives a cache hit at the cost of one log line. For an appliance rebuilt/redeployed regularly, the cache hit is worth more than a silent journal.
- **Alternative — ms7p Option A (writable-cwd ExecStart)**: would give both a cache hit *and* no EROFS, but requires replacing the supported bundled `bin/documenso` wrapper with a hand-rolled `ExecStart` (re-exporting the exact `PRISMA_*` env, running `prisma migrate deploy`, launching `node main.js` from `stateDir`). More surface area and a maintenance liability across upgrades. Deferred; not needed to meet the goals here.

## Risks / Trade-offs

- **EROFS log noise is mistaken for a fault** → Document it in `docs/services/documenso.md` as expected and harmless; the spec encodes the accepted behavior.
- **Documenso not present in the binary cache for a given unstable revision** (large package, cache window) → Then it rebuilds locally as before — no worse than the current override path. Verify with a build that substitutes rather than compiles when pinning the unstable revision.
- **License client reaches out to `license.documenso.com` on every boot** → Out of scope here; if an air-gapped/egress-controlled appliance is required, handle via firewall egress rules or `INTERNAL_OVERRIDE_LICENSE_SERVER_URL` (which only redirects the destination, does not disable the call).

## Migration Plan

1. In `modules/nixos/services/documenso/default.nix`: add the `unstable` let-binding; set `package` default to `unstable.documenso`; point the Playwright `runCommand` bridge at `unstable.playwright-driver`; remove the `config.nixpkgs.overlays` block and the `overrideAttrs`.
2. Document the expected EROFS line in `docs/services/documenso.md`.
3. Build the service on a cache-connected host; confirm `documenso` is substituted (not compiled).
4. Deploy to a non-prod host; confirm the service reaches `active (running)`, `Derived Status: NOT_FOUND`, port honored, and a document uploads + signs.
5. **Rollback**: revert the module change — restores the overlay + override path with no data impact (no schema or state change is involved).
