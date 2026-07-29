## Why

The two central scanner services (`vulnix-scan-central` and `trivy-scan-central`) share identical structure but are configured separately, requiring operators to maintain two host lists that are largely overlapping. Since all scanned hosts always expose `packages.json` (vulnix) and only some expose `docker-images.json` (trivy), a single service with a per-host `enableDockerScan` flag captures this relationship more accurately and reduces configuration duplication.

Related task: [elastinix-m7qf](../../../.beans/elastinix-m7qf--merge-scanner-services.md)

## What Changes

- **New**: `elastinix.services.vulnerability-scan-central` — combined scanner service replacing both separate services
- **New**: Per-host `enableDockerScan` boolean option (default `false`) within the `hosts` list
- **Fixed**: Script no longer uses `set -euo pipefail` — individual scan failures are logged and counted, scan continues for remaining hosts and images
- **New**: `vulnixCacheDir` string option (default `"/var/lib/vulnix-cache"`) — configurable NVD cache location
- **New**: `trivyCacheDir` string option (default `"/var/lib/trivy-cache"`) — configurable trivy DB cache location (fixes read-only filesystem error under systemd hardening)
- **Removed**: `elastinix.services.vulnix-scan-central` module (`service-vulnix-scan-central.nix` deleted)
- **Removed**: `elastinix.services.trivy-scan-central` module (`service-trivy-scan-central.nix` deleted)
- Docs updated: `docs/services/vulnerability-scan-central.md` (new), `vulnix-scan-central.md` and `trivy-scan-central.md` marked deprecated
- `docs/README.md` updated to reflect new service name
- No changes to `vulnerability-prometheus-exporter` — output paths (`/var/lib/vulnix/`, `/var/lib/trivy/`) remain identical

## Capabilities

### New Capabilities

- `vulnerability-scan-central`: Combined central vulnerability scanner that runs vulnix for all configured hosts and trivy for hosts with `enableDockerScan = true`, producing output in the same directory structure as the two replaced services

### Modified Capabilities

<!-- No existing spec-level requirements change — the Prometheus exporter and hostinfo interfaces are unchanged -->

## Impact

- **Modules removed**: `modules/nixos/services/service-vulnix-scan-central.nix`, `modules/nixos/services/service-trivy-scan-central.nix`
- **Module added**: `modules/nixos/services/service-vulnerability-scan-central.nix`
- **Breaking for existing users**: Anyone using `elastinix.services.vulnix-scan-central` or `elastinix.services.trivy-scan-central` must migrate to `elastinix.services.vulnerability-scan-central`
- **No impact**: `vulnerability-prometheus-exporter`, hostinfo service, flake inputs
