---
# elastinix-0pwo
title: Central trivy scan service for Docker images
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
depends_on:
  - elastinix-pg6e
---

New elastinix service running as the central scanner, fetching
`docker-images.json` from every configured compute over hostinfo and scanning
each image with trivy.

## What

The service `elastinix.services.trivy-scan-central`:

1. Periodically fetches `docker-images.json` from the configured hosts over
   `http://<host>:3333/docker-images.json`
2. Runs `trivy image --format json <image>` per image
3. Writes results to `/var/lib/trivy/<hostname>/<image-name>/output.json`

Trivy pulls images straight from the registry, so no access to the compute itself
is needed.

## Configuration

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

## Required on every scanned host

`hostinfo.enableDockerImages = true`, so that `docker-images.json` is served by
hostinfo (see elastinix-pg6e).

## Superseded

Merged with the vulnix scanner into a single `vulnerability-scan-central`
(elastinix-m7qf), where container scanning became a per-host `enableDockerScan`
flag rather than a second host list.
