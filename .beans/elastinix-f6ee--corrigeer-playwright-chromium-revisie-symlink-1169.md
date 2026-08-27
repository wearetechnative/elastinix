---
# elastinix-f6ee
title: Corrigeer Playwright chromium-revisie symlink (1169 -> bundled)
status: todo
type: bug
priority: high
created_at: 2026-08-27T10:00:57Z
updated_at: 2026-08-27T10:00:57Z
parent: elastinix-wxy7
---

**Runtime-blocker.** De `ExecStartPre` "playwright-setup" maakt een symlink met de door Documenso verwachte naam:

```bash
ln -sfn "$NIXPKGS_BROWSERS/$ACTUAL_VERSION" "$STATE_BROWSERS/chromium_headless_shell-1169"
```

De *bron* (`ACTUAL_VERSION`) is dynamisch (prima), maar de *doelnaam* `chromium_headless_shell-1169` is hardcoded. Documenso 2.14.0 bundelt **Playwright 1.56.1**, die chromium-headless-shell **revisie 1194** verwacht (uit `node_modules/playwright-core/browsers.json`). Documenso zoekt dus naar `chromium_headless_shell-1194` in `PLAYWRIGHT_BROWSERS_PATH`, vindt de `-1169`-symlink niet → headless chromium niet gevonden → PDF-/rendering-functies falen at runtime.

## Oplossing (aanbevolen: versie-onafhankelijk)

Leid de verwachte revisie af uit het package zelf i.p.v. een hardcoded nummer, zodat het toekomstige Playwright-bumps overleeft:

```bash
EXPECTED=$(${pkgs.jq}/bin/jq -r \
  '.browsers[] | select(.name=="chromium-headless-shell") | .revision' \
  ${cfg.package}/node_modules/playwright-core/browsers.json)
ln -sfn "$NIXPKGS_BROWSERS/$ACTUAL_VERSION" "$STATE_BROWSERS/chromium_headless_shell-$EXPECTED"
```

Minimale variant (alleen voor 2.14.0): `-1169` → `-1194`.

## Aandachtspunt

Zorg dat de nixpkgs-pin een `playwright-driver.browsers` levert die een chromium-headless-shell bevat die compatibel is met Playwright 1.56.1 (revisie in de buurt van 1194). Controleer dit bij de nixpkgs-bump (story 4).

## Acceptatiecriteria

- Symlink-doelnaam matcht de revisie die de gebundelde Playwright verwacht
- Documenso vindt chromium bij het genereren/renderen van een ondertekend PDF
- Bij voorkeur dynamisch afgeleid, niet opnieuw hardcoded
