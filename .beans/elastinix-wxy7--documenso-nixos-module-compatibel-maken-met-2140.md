---
# elastinix-wxy7
title: Documenso NixOS-module compatibel maken met 2.14.0
status: in-progress
type: epic
priority: high
created_at: 2026-08-27T10:00:41Z
updated_at: 2026-08-27T14:00:00Z
---

De NixOS-module `modules/nixos/services/documenso` (`services.documenso`) is geschreven tegen een oudere Documenso-release en is **niet compatibel met Documenso 2.14.0**. Zoals hij nu is, *bouwt* het package niet eens tegen 2.14.0, en zelfs met die blocker omzeild breekt PDF-rendering at runtime. Deze epic bundelt de wijzigingen die nodig zijn om de module werkend te krijgen op 2.14.0.

## Achtergrond

Verificatie gedaan tegen de daadwerkelijke `documenso-2.14.0` uit nixpkgs (store-pad geïnspecteerd + lokaal getest). Bevindingen:

| Onderdeel | Status op 2.14.0 |
|---|---|
| `--replace-fail` PORT-patch in `postFixup` | ❌ **breekt de build** — doelstring bestaat niet meer |
| Playwright/Chromium symlink `-1169` | ❌ **runtime** — 2.14.0 bundelt Playwright 1.56.1 → verwacht revisie `1194` |
| `[License] EROFS` schrijffout | ⚠️ cosmetisch (niet-fataal) maar log-ruis + faalt elke boot |
| Env-var-namen (jobs/redis/smtp/storage/signing/crypto/signup/telemetry) | ✅ nog geldig |
| Start via `bin/documenso` (prisma migrate + node main.js) | ✅ ongewijzigd |

## Scope

Story-beans (in volgorde):

1. Build-brekende PORT-patch verwijderen (blocker)
2. Playwright chromium-revisie symlink corrigeren (runtime)
3. EROFS license-file schrijffout oplossen (cosmetisch)
4. nixpkgs-pin bumpen naar 2.14.0 + migrate/boot verifiëren (integratie, geblokkeerd door 1–3)

## Definition of done

- `nixos-rebuild` bouwt de documenso-module tegen nixpkgs met 2.14.0 zonder fouten
- Service start, `prisma migrate deploy` draait, poort wordt gehonoreerd
- PDF-signing/rendering werkt (chromium gevonden)
- Geen EROFS-fout meer in de journal (of bewust geaccepteerd + gedocumenteerd)

## Referenties

- Module: `modules/nixos/services/documenso/default.nix`
- Laatste module-wijziging: `061350b fix: Documenso ignores port fixed` (2026-06-05)
