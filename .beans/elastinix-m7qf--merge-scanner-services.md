---
# elastinix-m7qf
title: Samenvoegen vulnix en trivy scanner tot één service
status: completed
type: task
priority: normal
created_at: 2026-07-28T00:00:00Z
updated_at: 2026-07-28T13:00:00Z
openspec-link: openspec/changes/archive/2026-08-25-merge-scanner-services
parent: elastinix-p9gu
depends_on:
  - elastinix-rdih
  - elastinix-0pwo
---

Vervang de twee losse scanner services (`vulnix-scan-central` en `trivy-scan-central`) door één gecombineerde service `vulnerability-scan-central`. Alle hosts krijgen altijd een vulnix-scan; hosts met Docker krijgen ook een trivy-scan via een per-host `enableDockerScan` vlag.

## Wat

Nieuwe service `elastinix.services.vulnerability-scan-central` die:

1. Per geconfigureerde host altijd `packages.json` ophaalt en scant met vulnix
2. Per host optioneel `docker-images.json` ophaalt en scant met trivy (als `enableDockerScan = true`)
3. Output-paden blijven hetzelfde: `/var/lib/vulnix/<host>/` en `/var/lib/trivy/<host>/`

## Configuratie

```nix
elastinix.services.vulnerability-scan-central = {
  enable = true;
  interval = "weekly";
  hosts = [
    { name = "compute1-prod"; url = "http://10.0.1.10:3333"; enableDockerScan = true; }
    { name = "compute2-prod"; url = "http://10.0.1.11:3333"; }
    { name = "compute3-prod"; url = "http://10.0.1.12:3333"; enableDockerScan = true; }
  ];
};
```

## Waarom samenvoegen

- Alle hosts hebben altijd `packages.json` — vulnix is universeel
- Alleen sommige hosts hebben Docker → `enableDockerScan` per host in plaats van twee aparte lijsten synchroon houden
- Één `enable`, één `interval`, één plek voor host-definitie

## Te doen

- Maak `service-vulnerability-scan-central.nix` als vervanging voor beide losse modules
- Verwijder `service-vulnix-scan-central.nix` en `service-trivy-scan-central.nix`
- Update `docs/services/` (nieuwe doc, oude docs naar deprecated)
- Update `docs/README.md`
- Prometheus exporter hoeft niet te veranderen (leest dezelfde output-paden)
