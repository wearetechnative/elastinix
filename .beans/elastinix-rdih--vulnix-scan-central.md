---
# elastinix-rdih
title: Centrale vulnix-scan service
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
---

Nieuwe elastinix service die als centrale scanner draait op een grote host (bijv. nixhost of compute6) en van alle geconfigureerde computes de `packages.json` ophaalt via hostinfo en scant met vulnix.

## Wat

De service `elastinix.services.vulnix-scan-central`:

1. Haalt periodiek `packages.json` op van alle geconfigureerde hosts via `http://<host>:3333/packages.json`
2. Runt `vulnix --from-file packages.json --json` per host
3. Schrijft resultaten naar `/var/lib/vulnix/<hostname>/output.json`
4. NVD cache leeft op de scanner host (eenmalig bootstrap ~2GB)

## Configuratie

```nix
elastinix.services.vulnix-scan-central = {
  enable = true;
  hosts = [
    { name = "compute1-prod"; url = "http://3.125.245.136:3333"; }
    { name = "compute2-prod"; url = "http://54.93.81.45:3333"; }
    # ...
  ];
  interval = "weekly";
};
```

## Vereiste op elke gescande host

`hostinfo.enablePackages = true` — zodat `packages.json` beschikbaar is via hostinfo.

## Afhankelijkheid

Vereist `elastinix-p9gu` (epic) en de packages.json generator met patches in technative-awsaccounts-workloads.
