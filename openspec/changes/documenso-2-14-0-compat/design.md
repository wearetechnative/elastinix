## Context

See proposal.md — Why. The `services.documenso` module targets 1.12.x; three concrete incompatibilities block 2.14.0 (build-breaking `postFixup`, hardcoded Playwright revision 1169, cosmetic EROFS log), plus the nixpkgs bump that ties them together.

Constraints established by inspecting the real 2.14.0 package and the live 1.12.6 production instance (`i-07080453336573e1c`, nixpkgs `26.05.20260714`):

| Fact | Value |
|---|---|
| 2.14.0 vendored Playwright | `playwright-core` 1.56.1 → expects chromium-headless-shell rev **1194** |
| 1.12.6 (live) vendored Playwright | `playwright-core` 1.52.0 → expects rev **1169** |
| Live prod `playwright-driver.browsers` (26.05, Jul 2026) | ships chromium rev **1217** |
| Live bridge in production | `…-1169 → …-1217` (**+48**, provided *newer*), signing/rendering **works today** |
| Pinned stable `playwright-driver` (flake.lock 26.05, Aug 2025) | 1.52.0 → chromium **1169** (−25 vs expected, *older*) |
| Pinned unstable `playwright-driver` (the chosen source) | 1.61.1 → chromium **1228** (+34 vs expected, *newer*) |
| 2.14.0 native `PORT` handling | `parseInt(process.env.PORT ?? '3000', 10)` — honoured without patching |
| EROFS license write | non-fatal; license check still returns community edition |
| `documenso` in `nixos-26.05` (the current pin) | **1.12.6** — 2.14.0 is NOT in the stable channel |
| `documenso` in `nixpkgs-unstable` | **2.14.0** — the only channel carrying it |

## Goals / Non-Goals

**Goals:**
- Module builds against nixpkgs carrying `documenso-2.14.0` with no `--replace-fail` build break.
- Playwright chromium is found at the revision 2.14.0's vendored Playwright expects, derived automatically (not hardcoded).
- Provisioning is a pure build-time artifact, not a runtime `stateDir` mutation.
- Signing/rendering correctness is verified before production.

**Non-Goals:**
- Rewriting the `ExecStart` into a hand-rolled wrapper (EROFS stays Path 1: accept + document).
- Pinning or overriding `playwright-driver` to match Documenso's Playwright version exactly.
- Changing the certificate, S3, SMTP, Redis, or secrets requirements (untouched).
- Bidirectional or incremental migration logic — `prisma migrate deploy` is used as-is.

## Decisions

### D1 — Drop the `overrideAttrs`/`postFixup` PORT patch; use `pkgs.documenso` directly
The patch targets a string absent in 2.14.0 and `--replace-fail` is designed to fail when the pattern is missing, so the package build aborts. 2.14.0 reads `PORT` natively, and the module already writes `PORT` into the generated `.env`. The override is therefore both broken and redundant.
- *Alternative — `--replace-quiet`*: would let the build pass but silently no-op; keeps dead code and misleads readers. Rejected.
- *Alternative — port-shim wrapper*: unnecessary given native support. Rejected.

### D2 — Provision Playwright browsers via a build-time derivation, not `ExecStartPre`
A `pkgs.runCommand` mirrors `pkgs.playwright-driver.browsers` and adds a `chromium_headless_shell-<rev>` symlink, where `<rev>` is read at build time from `${cfg.package}/node_modules/playwright-core/browsers.json` (via `jq`, `select(.name=="chromium-headless-shell")`). `PLAYWRIGHT_BROWSERS_PATH` points directly at the resulting read-only store path.

Why: the store path of the browsers is known at build time — discovering it with `ls | grep | head` in a boot-time hook, then `mkdir`/`chown`/`ln` into `stateDir`, defers Nix's job to runtime. Moving it into a derivation means:
- failure surfaces at `nixos-rebuild` (build fails) instead of in the journal at boot;
- no `stateDir` cache, no `chown`, no mutable browser dir;
- the revision self-corrects on future nixpkgs/Playwright bumps (read from the package, never hardcoded).

- *Alternative — keep runtime symlink, just change 1169→1194*: still hardcoded, still imperative, breaks again on the next Playwright bump. Rejected (bean f6ee explicitly prefers dynamic).
- *Alternative — IFD via `builtins.readFile` on the package at eval*: forces a build during evaluation. The `runCommand` reads `browsers.json` as an ordinary build-time input instead — no IFD. Chosen.
- *Alternative — pin `playwright-driver` to 1.56.1 so `.browsers` already carries 1194*: brittle hash juggling against whatever the nixpkgs pin carries; fights the pin. Rejected — ride stock chromium and rename.

### D3 — Bridge legitimacy relies on chromium-headless-shell protocol stability across nearby revisions
The rename bridges the directory *name*, not the binary ABI. This is validated empirically: the live 1.12.6 instance runs a **48-revision** gap (1169→1217) and signs/renders correctly. The 2.14.0 gap is smaller (1194→1217, 23 revisions). This is strong evidence, not proof — see Risks.

### D5 — Source 2.14.0 from a scoped `nixpkgs-unstable` input via overlay, not by moving the platform
`documenso-2.14.0` exists only in `nixpkgs-unstable`; the platform's main `nixpkgs` is pinned to the `nixos-26.05` release channel, which carries 1.12.6 and (being a major bump) will not backport 2.14.0. So "bump the nixpkgs pin" is not achievable within `nixos-26.05`.

Add a dedicated `nixpkgs-unstable` flake input and an overlay that pulls **only** `documenso` — together with the `playwright-driver` that the browsers bridge (D2) consumes — from that input. Everything else in elastinix stays on `nixos-26.05`.

- **Why source `playwright-driver` from unstable too, not from stable:** verified numbers — the pinned stable `playwright-driver` ships chromium **1169**, unstable ships **1228**, and documenso 2.14.0 expects **1194**. Production evidence is that a *newer-than-expected* chromium works (live: expected 1169, provided 1217, +48, signs correctly). Unstable's 1228 keeps the bridge in that same proven "provided newer than expected" (+34) direction; stable's 1169 would be *older* than expected (−25) — an untested direction and a genuinely old chromium relative to Playwright 1.56.1. So unstable is the lower-risk source for the browser, not because it era-matches (it does not — driver 1.61.1 vs vendored 1.56.1) but because the resulting chromium sits on the evidence-backed side of 1194. The dynamic bridge (D2) renames 1228 → 1194 regardless.
- *Alternative — point main `nixpkgs.url` at unstable*: rebuilds every elastinix service on unstable, huge blast radius, couples an isolated app upgrade to platform-wide instability. Rejected.
- *Alternative — `documenso.overrideAttrs`/source override on the 26.05 package*: re-packages a major version by hand (deps, prisma, playwright) — far more fragile than taking the upstream unstable derivation. Rejected.

The overlay pins to a specific unstable revision (committed in `flake.lock`), so the "unstable" input is reproducible and updated deliberately, not floating.

### D4 — EROFS license write: accept + document (Path 1)
Keep the vendored `bin/documenso` start wrapper. The wrapper `cd`s into the read-only store, so `process.cwd()` is unwritable and the license cache write fails with EROFS — but the license check itself succeeds and the service runs. Document the expected log line in `docs/services/documenso.md`.
- *Alternative — Path A, hand-rolled `ExecStart`* (`cd stateDir; prisma migrate; node main.js`): makes the module own the `PRISMA_QUERY_ENGINE_LIBRARY`/`PRISMA_SCHEMA_ENGINE_BINARY` exports and re-verify migrations on every future bump — a silent breakage risk during a major upgrade. Rejected for this change; can be revisited later if log noise justifies it.

## Risks / Trade-offs

- **chromium 1217 may not render/sign correctly under Playwright 1.56.1** (the original nixpkgs pin was introduced *because documents were not signed correctly*) → Hard acceptance gate: render + sign one real PDF on a test host and visually verify the output before production. The 48-rev gap working in prod today makes this likely but not certain.
- **nixpkgs bump lands a chromium the bridge can't build** (no `chromium_headless_shell-*` in the driver) → the `runCommand` fails loudly at build time with a clear message; caught before deploy.
- **Major DB migration 1.12.x → 2.14.0** (163+ migrations on a fresh DB; delta on an existing one) → take a DB backup/snapshot before the first `prisma migrate deploy` on any existing instance; verify on non-prod first.
- **Removing the `stateDir` browser cache changes an observable path** → acceptable; nothing else references it, and `PLAYWRIGHT_BROWSERS_PATH` now points at the store.

## Migration Plan

1. Add the `nixpkgs-unstable` input + overlay (D5) so `pkgs.documenso` resolves to 2.14.0; D1/D2/D4 are only exercisable against 2.14.0, so this comes first.
2. Land the module changes (D1, D2, D4).
3. Update `docs/services/documenso.md` with the EROFS note.
4. Commit `flake.lock` (pins the unstable revision). `nixos-rebuild build` the module — confirm no build errors and the browsers derivation builds.
5. Deploy to a non-prod/test host. **Back up the DB first if it is an existing instance.**
6. Verify: service `active (running)`; `prisma migrate deploy` applied; port honoured; login works; upload + **sign a document and visually confirm the rendered signature** (chromium + cert).
7. Rollback: NixOS generation rollback restores the previous closure; restore the DB snapshot if a migration was applied and must be reverted.

## Open Questions

None blocking. (Whether to later adopt EROFS Path A is deferred and does not affect these specs or tasks.)
