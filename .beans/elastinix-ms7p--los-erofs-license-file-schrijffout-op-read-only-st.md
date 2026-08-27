---
# elastinix-ms7p
title: Los EROFS license-file schrijffout op (read-only store cwd)
status: todo
type: bug
priority: low
created_at: 2026-08-27T10:00:58Z
updated_at: 2026-08-27T10:00:58Z
parent: elastinix-wxy7
---

**Cosmetisch / niet-fataal.** Bij elke boot logt Documenso:

```
[License] Failed to save license file: Error: EROFS: read-only file system,
open '/nix/store/…-documenso-2.14.0/apps/remix/.documenso-license.json'
```

De license-check zélf slaagt (`Derived Status: NOT_FOUND` = community edition), dus de service werkt gewoon. Het is puur log-ruis.

## Oorzaak

De license-client bepaalt het schrijfpad via `process.cwd()` (bestandsnaam `.documenso-license.json`). De gebundelde wrapper `bin/documenso` doet:

```bash
cd /nix/store/…/apps/remix
… node build/server/main.js
```

Daardoor is `process.cwd()` het **read-only nix-store-pad** → schrijven faalt met EROFS. `WorkingDirectory=${stateDir}` in de unit helpt niet, want de wrapper `cd`'t expliciet de store in.

## Mogelijke oplossingen

**Optie A — draai met een schrijfbare cwd (aanbevolen).**
Vervang de packaged wrapper als `ExecStart` door een equivalent dat vanuit `${cfg.stateDir}` draait met absolute paden, zodat `process.cwd()` schrijfbaar is en de license-cache in de stateDir belandt:

```nix
ExecStart = pkgs.writeShellScript "documenso-start" ''
  cd ${cfg.stateDir}
  export PRISMA_QUERY_ENGINE_LIBRARY=…   # zelfde PRISMA_* env als de wrapper
  ${prismaPkg}/bin/prisma migrate deploy \
    --schema ${cfg.package}/packages/prisma/schema.prisma
  exec ${pkgs.nodejs}/bin/node \
    ${cfg.package}/apps/remix/build/server/main.js
'';
```

Let op: overneem exact de `PRISMA_QUERY_ENGINE_LIBRARY/BINARY` + `PRISMA_SCHEMA_ENGINE_BINARY` exports uit de originele `bin/documenso`-wrapper. Verifieer dat main.js zijn eigen assets via `import.meta.url` resolvet (en niet via cwd) — zo ja, dan is de andere cwd veilig. Regressietest: service start + één document ondertekenen.

**Optie B — accepteer het (laagste risico).**
Laat de fout staan (niet-fataal) en filter desgewenst alleen de logregel. Documenteer in `docs/services/documenso.md` dat de EROFS-melding verwacht en onschadelijk is.

**Niet werkbaar:** een schrijfbare symlink vooraf plaatsen op `$out/apps/remix/.documenso-license.json` — de store is read-only, dus die symlink kan er niet komen.

## Acceptatiecriteria

- Óf: geen EROFS-fout meer in `journalctl -u documenso` (Optie A)
- Óf: bewuste keuze voor Optie B, gedocumenteerd
- Service blijft correct starten en documenten ondertekenen
