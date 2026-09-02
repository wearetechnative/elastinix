---
# elastinix-m7qf
title: Merge the vulnix and trivy scanners into one service
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

Replace the two separate scanner services (`vulnix-scan-central` and
`trivy-scan-central`) with a single combined `vulnerability-scan-central`. Every
host always gets a vulnix scan; hosts running Docker also get a trivy scan through
a per-host `enableDockerScan` flag.

## What

A new service `elastinix.services.vulnerability-scan-central` that:

1. Fetches `packages.json` from every host and scans it with vulnix
2. Optionally fetches `docker-images.json` per host and scans it with trivy, where
   `enableDockerScan = true`
3. Keeps the output paths unchanged: `/var/lib/vulnix/<host>/` and
   `/var/lib/trivy/<host>/`

## Configuration

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

## Why merge them

- Every host always has `packages.json`, so vulnix is universal
- Only some hosts run Docker, so `enableDockerScan` per host beats keeping two
  separate host lists in sync
- One `enable`, one `interval`, one place where hosts are defined

## To do

- Write `service-vulnerability-scan-central.nix` replacing both separate modules
- Remove `service-vulnix-scan-central.nix` and `service-trivy-scan-central.nix`
- Update `docs/services/` with a new document and mark the old ones deprecated
- Update `docs/README.md`
- The Prometheus exporter needs no change, since it reads the same output paths
