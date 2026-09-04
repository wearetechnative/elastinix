---
# elastinix-ms7p
title: Fix EROFS license-file write error (read-only store cwd)
status: todo
type: bug
priority: low
created_at: 2026-08-27T10:00:58Z
updated_at: 2026-08-27T10:00:58Z
parent: elastinix-wxy7
---

**Cosmetic / non-fatal.** On every boot Documenso logs:

```
[License] Failed to save license file: Error: EROFS: read-only file system,
open '/nix/store/…-documenso-2.14.0/apps/remix/.documenso-license.json'
```

The license check itself succeeds (`Derived Status: NOT_FOUND` = community edition), so the service works fine. It is purely log noise.

## Cause

The license client determines the write path via `process.cwd()` (file name `.documenso-license.json`). The bundled wrapper `bin/documenso` does:

```bash
cd /nix/store/…/apps/remix
… node build/server/main.js
```

As a result, `process.cwd()` is the **read-only nix-store path** → writing fails with EROFS. `WorkingDirectory=${stateDir}` in the unit does not help, because the wrapper explicitly `cd`s into the store.

## Possible solutions

**Option A — run with a writable cwd (recommended).**
Replace the packaged wrapper as `ExecStart` with an equivalent that runs from `${cfg.stateDir}` using absolute paths, so `process.cwd()` is writable and the license cache lands in the stateDir:

```nix
ExecStart = pkgs.writeShellScript "documenso-start" ''
  cd ${cfg.stateDir}
  export PRISMA_QUERY_ENGINE_LIBRARY=…   # same PRISMA_* env as the wrapper
  ${prismaPkg}/bin/prisma migrate deploy \
    --schema ${cfg.package}/packages/prisma/schema.prisma
  exec ${pkgs.nodejs}/bin/node \
    ${cfg.package}/apps/remix/build/server/main.js
'';
```

Note: copy exactly the `PRISMA_QUERY_ENGINE_LIBRARY/BINARY` + `PRISMA_SCHEMA_ENGINE_BINARY` exports from the original `bin/documenso` wrapper. Verify that main.js resolves its own assets via `import.meta.url` (and not via cwd) — if so, the different cwd is safe. Regression test: service start + sign one document.

**Option B — accept it (lowest risk).**
Leave the error in place (non-fatal) and optionally filter just the log line. Document in `docs/services/documenso.md` that the EROFS message is expected and harmless.

**Not workable:** placing a writable symlink up front at `$out/apps/remix/.documenso-license.json` — the store is read-only, so that symlink cannot be created there.

## Acceptance criteria

- Either: no more EROFS error in `journalctl -u documenso` (Option A)
- Or: deliberate choice for Option B, documented
- Service keeps starting correctly and signing documents
