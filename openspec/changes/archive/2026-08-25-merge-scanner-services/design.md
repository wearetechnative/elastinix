## Context

Two existing modules — `service-vulnix-scan-central.nix` and `service-trivy-scan-central.nix` — have identical structure (same `hostType` submodule, same timer pattern, same systemd hardening) but are configured independently. In practice, every scanned host exposes `packages.json` via hostinfo (vulnix input), while only Docker-enabled hosts additionally expose `docker-images.json` (trivy input). The two host lists are therefore always partially overlapping, creating a synchronisation burden.

See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- Replace both modules with a single `service-vulnerability-scan-central.nix`
- Preserve all existing output paths (`/var/lib/vulnix/`, `/var/lib/trivy/`) so the Prometheus exporter requires no changes
- Add `enableDockerScan` boolean per host entry (default `false`)
- Keep the single shared `interval` option
- Configurable cache directories for vulnix (`vulnixCacheDir`) and trivy (`trivyCacheDir`) to work within systemd `ProtectSystem = "strict"` hardening

**Non-Goals:**
- Changing the scan logic, tools, or output format
- Supporting different intervals per scanner type
- Changing the Prometheus exporter or hostinfo service
- Parallelising scans across hosts

## Decisions

### Single `hosts` list with per-host `enableDockerScan`

**Decision**: The combined service uses one `hosts` list. Each entry adds an optional `enableDockerScan = true` flag to also run trivy for that host.

**Rationale**: Every host always gets vulnix. Only some hosts need trivy. This mirrors the actual deployment model and avoids duplicating host URLs across two lists. The flag is co-located with the URL, so there is one place to add or remove a host.

**Alternative considered**: Separate `vulnixHosts` and `trivyHosts` lists. Rejected because hosts that need both scanners would need to be listed twice, and there is no benefit over the current two-service model.

### Shared `interval` for both scanners

**Decision**: One `interval` option applies to both vulnix and trivy runs within the same service.

**Rationale**: Vulnix and trivy run sequentially in a single oneshot service. Separate intervals would require two timers and two services, reverting to the current split. In practice, weekly is the correct cadence for both.

**Alternative considered**: `vulnixInterval` / `trivyInterval` per scanner. Rejected as over-engineering given the shared use case.

### Sequential execution within one systemd oneshot

**Decision**: Vulnix and trivy scans run sequentially (not in parallel) within a single shell script.

**Rationale**: Trivy pulls images from the internet; parallel execution could saturate bandwidth and complicate error handling. Sequential execution is simpler and the weekly timer makes total duration irrelevant.

**Trade-off**: On large deployments (many hosts, many images) a single run could take hours. This is acceptable for a weekly scan cadence.

### Output paths unchanged

**Decision**: `/var/lib/vulnix/<host>/output.json` and `/var/lib/trivy/<host>/<image>/output.json` stay identical.

**Rationale**: The Prometheus exporter reads these paths directly. Changing them would require a coordinated update to the exporter with no benefit.

## Risks / Trade-offs

- **Breaking change for existing users** → Mitigation: document migration in deprecated service doc pages; old module attributes raise a NixOS evaluation error immediately (no silent breakage)
- **Long scan runs on large deployments** → Mitigation: document expected duration; trivy image pulls are bounded by registry speed, not scanner host CPU
- **Trivy writes vulnerability DB to `$HOME/.cache`** → Under `ProtectSystem = "strict"` this path is read-only. Mitigation: pass `--cache-dir` pointing to `trivyCacheDir` (a writable path in `ReadWritePaths`)

## Migration Plan

1. Deploy new `service-vulnerability-scan-central.nix`
2. In NixOS configurations, replace:
   ```nix
   # Before
   elastinix.services.vulnix-scan-central = { enable = true; hosts = [...]; };
   elastinix.services.trivy-scan-central  = { enable = true; hosts = [...]; };

   # After
   elastinix.services.vulnerability-scan-central = {
     enable = true;
     hosts = [
       { name = "compute1"; url = "http://..."; enableDockerScan = true; }
       { name = "compute2"; url = "http://..."; }
     ];
   };
   ```
3. Remove old modules — NixOS evaluation will error on any remaining references
4. Rollback: revert module file change; output directories are untouched
