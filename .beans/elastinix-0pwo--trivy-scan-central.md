---
# elastinix-0pwo
title: Centrale trivy-scan service voor Docker images
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
depends_on:
  - elastinix-pg6e
---

Nieuwe elastinix service die als centrale scanner draait en van alle geconfigureerde computes de `docker-images.json` ophaalt via hostinfo en elke image scant met trivy.

## Wat

De service `elastinix.services.trivy-scan-central`:

1. Haalt periodiek `docker-images.json` op van geconfigureerde hosts via `http://<host>:3333/docker-images.json`
2. Runt `trivy image --format json <image>` per image
3. Schrijft resultaten naar `/var/lib/trivy/<hostname>/<image-name>/output.json`

Trivy pulled images rechtstreeks van de registry — geen toegang tot de compute zelf nodig.

## Configuratie

```nix
elastinix.services.trivy-scan-central = {
  enable = true;
  hosts = [
    { name = "compute1-prod"; url = "http://3.125.245.136:3333"; }
    { name = "compute3-prod"; url = "http://18.199.249.128:3333"; }
  ];
  interval = "weekly";
};
```

## Vereiste op elke gescande host

`hostinfo.enableDockerImages = true` — zodat `docker-images.json` beschikbaar is via hostinfo (zie elastinix-pg6e).

## Kritische applicaties (ISO 27001)

- compute1: `twentyhq/twenty-server`, `twentyhq/twenty-worker`, `gotenberg/gotenberg`
- compute3: `zammad/zammad`, `elasticsearch`
