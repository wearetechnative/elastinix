# Hostinfo Service

The Hostinfo service (`elastinix.services.hostinfo`) exposes system information as JSON files via a lightweight HTTP server. It is designed for automated consumption by monitoring tools, dashboards, and lambdas.

## Features

- **Services inventory**: Daily-generated JSON listing all enabled elastinix services and programs (optional, on by default)
- **Extensible**: Any JSON file placed in `/var/lib/hostinfo/` is automatically served
- **Optional SBOM**: Exposes vulnerability scan results from `elastinix.services.vulnix-scan` as `sbom.json`
- **Optional packages**: Exposes an externally-uploaded `packages.json` from `/var/lib/packages/`
- **Pure builds**: Static data is embedded at build time; only the timestamp is injected at runtime
- **Configurable port**: Default `3333`, override as needed
- **Automatic firewall**: Opens the configured port without manual configuration
- **Systemd hardening**: Both the inventory generator and HTTP server run with restricted permissions

## Configuration

### Basic Example

```nix
elastinix.services.hostinfo = {
  enable = true;
};
```

### Without inventory generation

Run the HTTP server without generating `services.json` (e.g. to serve only externally-provided files):

```nix
elastinix.services.hostinfo = {
  enable = true;
  enableInventory = false;
};
```

### With packages inventory

Expose the package list uploaded by Terraform to `/var/lib/packages/packages.json`:

```nix
elastinix.services.hostinfo = {
  enable = true;
  enablePackages = true;
};
```

### With Docker image inventory

Expose the list of running Docker containers as `docker-images.json` for central trivy scanning:

```nix
elastinix.services.hostinfo = {
  enable = true;
  enableDockerImages = true;
};
```

### With SBOM

Enable alongside `vulnix-scan` to also expose vulnerability data:

```nix
elastinix.services.hostinfo = {
  enable = true;
  enableSbom = true;
};

elastinix.services.vulnix-scan.enable = true;
```

### Custom Port

```nix
elastinix.services.hostinfo = {
  enable = true;
  port = 8080;
};
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the hostinfo service |
| `port` | port (1–65535) | `3333` | Port for the HTTP server |
| `enableInventory` | boolean | `true` | Generate `services.json` via daily timer. Set to `false` to skip inventory generation. |
| `enablePackages` | boolean | `false` | Symlink `/var/lib/packages/packages.json` as `packages.json`. Source uploaded externally by Terraform. |
| `enableDockerImages` | boolean | `false` | Generate Docker image inventory from Docker socket and expose as `docker-images.json` |
| `enableSbom` | boolean | `false` | Symlink `/var/lib/sbom/system.json` as `sbom.json` |
| `enableVulnixReport` | boolean | `false` | Symlink `/var/lib/vulnix/output.json` as `vulnix-report.json` |

## JSON Output

### `services.json`

Generated daily at `/var/lib/hostinfo/services.json`:

```json
{
  "hostname": "compute2-prod",
  "buildTime": "2026-05-11T08:00:00Z",
  "services": {
    "badgersbay": true,
    "hostinfo": true,
    "vulnix-scan": true
  },
  "programs": {
    "awsUtils": true,
    "docker": true
  },
  "nixosVersion": "26.05.0",
  "systemStateVersion": "26.05"
}
```

| Field | Description |
|-------|-------------|
| `hostname` | NixOS hostname (`config.networking.hostName`) |
| `buildTime` | ISO 8601 UTC timestamp of last inventory generation |
| `services` | Map of enabled `elastinix.services.*` names to `true` |
| `programs` | Map of enabled `elastinix.programs.*` names to `true` |
| `nixosVersion` | Full NixOS version string |
| `systemStateVersion` | NixOS state version |

### `packages.json` (when `enablePackages = true`)

A symlink to `/var/lib/packages/packages.json`, containing the NixOS package inventory uploaded by Terraform. If the source file does not exist yet, the HTTP server returns a 404 for this path.

### `sbom.json` (when `enableSbom = true`)

A symlink to `/var/lib/sbom/system.json`, containing vulnix vulnerability scan output. Requires `elastinix.services.vulnix-scan.enable = true`.

## Storage Directory

All files in `/var/lib/hostinfo/` are served automatically. The directory is created with permissions `0755 root root` via `systemd.tmpfiles`.

To add custom JSON to the hostinfo server, drop files into `/var/lib/hostinfo/`.

## Systemd Units

| Unit | Type | Description |
|------|------|-------------|
| `elastinix-hostinfo-inventory.service` | oneshot | Generates `services.json` with current timestamp (only when `enableInventory = true`) |
| `elastinix-hostinfo-inventory.timer` | timer | Triggers inventory generation daily (only when `enableInventory = true`) |
| `elastinix-hostinfo-server.service` | simple | Python HTTP server serving `/var/lib/hostinfo/` |

## Useful Commands

```bash
# Check server status
systemctl status elastinix-hostinfo-server.service

# Check inventory generator
systemctl status elastinix-hostinfo-inventory.service

# Manually trigger inventory regeneration
systemctl start elastinix-hostinfo-inventory.service

# View server logs
journalctl -u elastinix-hostinfo-server.service -f

# Test HTTP endpoint
curl http://localhost:3333/services.json | jq .

# Test SBOM endpoint (if enableSbom = true)
curl http://localhost:3333/sbom.json | jq .

# List all served files
curl http://localhost:3333/
```

## Security

The HTTP server runs as `nobody:nogroup` with extensive systemd hardening:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `ProtectKernelTunables=true`
- `ProtectControlGroups=true`
- `ReadOnlyPaths=/etc /var/lib/hostinfo`

No authentication is applied. The endpoint is intended for internal network use. For HTTPS and access control, see bean `elastinix-n3zn` (nginx vhost, planned).

## Future Work

- **nginx vhost** (`elastinix-n3zn`): HTTPS access at `hostinfo.${domain}` with optional auth
- **Rename `buildTime` to `lastUpdated`** (`elastinix-vtja`): Requires updating lambda `elastinix_services_monitor_prod`

## Implementation Details

- **Service definition**: `modules/nixos/services/service-hostinfo.nix`
- **HTTP server**: Python `http.server` (stdlib, no external deps)
- **Inventory generation**: `jq` injects `buildTime` at runtime into a pure Nix-store template (only when `enableInventory = true`)
- **Symlinks**: `systemd.tmpfiles` `L+` rules for `enableSbom`, `enableVulnixReport`, and `enablePackages`
