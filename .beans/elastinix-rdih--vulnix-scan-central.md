---
# elastinix-rdih
title: Central vulnix scan service
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
---

New elastinix service running as the central scanner on a large host, fetching
`packages.json` from every configured compute over hostinfo and scanning it with
vulnix.

## What

The service `elastinix.services.vulnix-scan-central`:

1. Periodically fetches `packages.json` from every configured host over
   `http://<host>:3333/packages.json`
2. Runs `vulnix --from-file packages.json --json` per host
3. Writes results to `/var/lib/vulnix/<hostname>/output.json`
4. Keeps the NVD cache on the scanner host, bootstrapped once at roughly 2 GB

## Configuration

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

## Required on every scanned host

`hostinfo.enablePackages = true`, so that `packages.json` is served by hostinfo.

## Dependency

Requires elastinix-p9gu (epic) and the packages.json generator with patches in
technative-awsaccounts-workloads.

## Superseded

This service was later merged with the trivy scanner into a single
`vulnerability-scan-central` (elastinix-m7qf).
