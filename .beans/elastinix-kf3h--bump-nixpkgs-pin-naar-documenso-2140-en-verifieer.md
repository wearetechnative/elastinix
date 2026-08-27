---
# elastinix-kf3h
title: Bump nixpkgs-pin naar documenso 2.14.0 en verifieer migrate+boot
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

Integratiestap: bump de nixpkgs-pin zodat `pkgs.documenso` **2.14.0** levert, en verifieer dat de module end-to-end werkt. Geblokkeerd door de drie fixes (PORT-patch, Playwright-revisie, EROFS) — die moeten eerst landen, anders breekt de build/runtime bij de bump.

## Te doen

- Update de nixpkgs-input in `flake.nix` naar een revisie die `documenso-2.14.0` bevat; `nix flake update nixpkgs` (of de juiste input) + commit `flake.lock`
- Controleer dat de meegeleverde `pkgs.playwright-driver.browsers` een chromium-headless-shell bevat compatibel met Playwright 1.56.1 (revisie ~1194) — zie story Playwright
- `nixos-rebuild build` (of de elastinix apply-target) draait zonder fouten
- Deploy naar een test/non-prod host

## Verificatie

- Service `documenso.service` komt `active (running)`
- `prisma migrate deploy` past de migraties toe (163+ migraties bij een verse DB; op een bestaande 1.12.x-DB alleen de delta)
- **Neem een DB-backup/snapshot vóór de eerste migrate op een bestaande instance** (major-upgrade van 1.12.x → 2.14.0)
- Poort wordt gehonoreerd (`cfg.port`)
- Login werkt; een document uploaden + ondertekenen werkt (chromium + signing-cert)
- Geen EROFS-fout meer (als story 3 = Optie A)

## Acceptatiecriteria

- nixpkgs-pin op 2.14.0, `flake.lock` gecommit
- Module bouwt en draait op een test-host
- Migrate + boot + signing geverifieerd
