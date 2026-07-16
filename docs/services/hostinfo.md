# Hostinfo Service

The Hostinfo service (`elastinix.services.hostinfo`) exposes system information as JSON files via a lightweight HTTP server. It is designed for automated consumption by monitoring tools, dashboards, and lambdas.

## Features

- **Services inventory**: Daily-generated JSON listing all enabled elastinix services and programs
- **Extensible**: Any JSON file placed in `/var/lib/hostinfo/` is automatically served
- **Optional SBOM**: Exposes vulnerability scan results from `elastinix.services.vulnix-scan` as `sbom.json`
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
| `enableSbom` | boolean | `false` | Symlink `/var/lib/sbom/system.json` as `sbom.json` |

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

### `sbom.json` (when `enableSbom = true`)

A symlink to `/var/lib/sbom/system.json`, containing vulnix vulnerability scan output. Requires `elastinix.services.vulnix-scan.enable = true`.

## Storage Directory

All files in `/var/lib/hostinfo/` are served automatically. The directory is created with permissions `0755 root root` via `systemd.tmpfiles`.

To add custom JSON to the hostinfo server, drop files into `/var/lib/hostinfo/`.

## Systemd Units

| Unit | Type | Description |
|------|------|-------------|
| `elastinix-hostinfo-inventory.service` | oneshot | Generates `services.json` with current timestamp |
| `elastinix-hostinfo-inventory.timer` | timer | Triggers inventory generation daily (persistent) |
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
- **Inventory generation**: `jq` injects `buildTime` at runtime into a pure Nix-store template
- **SBOM symlink**: `systemd.tmpfiles` `L+` rule (only created when `enableSbom = true`)
