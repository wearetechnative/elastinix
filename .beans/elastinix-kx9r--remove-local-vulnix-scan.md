---
# elastinix-kx9r
title: Verwijder lokale vulnix-scan service (vervangen door centrale aanpak)
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
depends_on:
  - elastinix-rdih
---

De lokale `elastinix.services.vulnix-scan` module is vervangen door de centrale scanning architectuur (elastinix-rdih). De lokale module draait op elke compute zelf en vereist ~2GB NVD cache — dat is te zwaar voor kleine computes. Na uitrol van de centrale scanner kan de lokale module worden verwijderd.

## Wat

1. Verwijder `modules/nixos/services/service-vulnix-scan.nix`
2. Verwijder de `vulnix-scan` capability spec (`openspec/specs/vulnix-scan/spec.md`)
3. Verwijder alle verwijzingen naar `elastinix.services.vulnix-scan` in downstream configuraties (`technative-awsaccounts-workloads`)
4. Verwijder `vulnix` als flake input als het enkel voor de lokale service gebruikt werd

## Volgorde

Uitvoeren NÁ elastinix-rdih volledig uitgerold is op de scanner host, zodat bestaande hosts geen scanning-gat krijgen.
