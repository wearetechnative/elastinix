# Spec: hostinfo-service

## Purpose

Defines requirements for the `elastinix.services.hostinfo` NixOS module. The module serves JSON files (including a dynamically generated services inventory) from `/var/lib/hostinfo/` via a Python HTTP server, enabling machine-readable host introspection over the network.

## Requirements

### Requirement: Service enable option
The module SHALL expose `elastinix.services.hostinfo.enable` as a boolean option. When disabled, no systemd units, tmpfiles rules, or firewall changes SHALL be created.

#### Scenario: Service enabled
- **WHEN** `elastinix.services.hostinfo.enable` is set to `true`
- **THEN** the system creates the `elastinix-hostinfo-inventory` oneshot service, `elastinix-hostinfo-inventory` timer, `elastinix-hostinfo-server` service, the `/var/lib/hostinfo` directory, and opens the configured firewall port

#### Scenario: Service disabled
- **WHEN** `elastinix.services.hostinfo.enable` is set to `false` or not set
- **THEN** no hostinfo systemd units, tmpfiles rules, or firewall changes are present on the system

### Requirement: Configurable port
The module SHALL expose `elastinix.services.hostinfo.port` as an integer option with default value `3333`. The HTTP server SHALL listen on the configured port.

#### Scenario: Default port
- **WHEN** `port` is not set
- **THEN** the HTTP server listens on port `3333`

#### Scenario: Custom port
- **WHEN** `port` is set to a custom value (e.g. `8080`)
- **THEN** the HTTP server listens on port `8080` and the firewall opens port `8080`

### Requirement: Automatic firewall configuration
The module SHALL automatically open the configured port in the NixOS firewall. No manual firewall configuration SHALL be required.

#### Scenario: Firewall opened
- **WHEN** `elastinix.services.hostinfo.enable` is `true`
- **THEN** the configured port is added to `networking.firewall.allowedTCPPorts`

### Requirement: Generate services inventory JSON daily
The module SHALL create a systemd timer that triggers a oneshot service daily. The oneshot service SHALL generate `/var/lib/hostinfo/services.json` containing:
- `hostname`: the NixOS hostname
- `buildTime`: ISO 8601 UTC timestamp of when the file was generated
- `services`: object mapping enabled `elastinix.services.*` names to `true`
- `programs`: object mapping enabled `elastinix.programs.*` names to `true`
- `nixosVersion`: the NixOS version string
- `systemStateVersion`: the NixOS state version string

#### Scenario: Inventory generated on daily timer
- **WHEN** the daily timer fires
- **THEN** `/var/lib/hostinfo/services.json` is written with current `buildTime` and the enabled services/programs

#### Scenario: Inventory generated on first boot
- **WHEN** the host boots and the daily run has not yet occurred
- **THEN** the timer's `Persistent = true` causes the oneshot to run and `/var/lib/hostinfo/services.json` is created

#### Scenario: Enabled services reflected
- **WHEN** `elastinix.services.badgersbay.enable = true` is set in the host config
- **THEN** `services.json` contains `"badgersbay": true` in the `services` object

### Requirement: Pure Nix build
The static inventory data (services list, hostname, versions) SHALL be written to the Nix store as a pure derivation without timestamps. The `buildTime` timestamp SHALL be injected at runtime by the systemd oneshot service.

#### Scenario: Build is reproducible
- **WHEN** the NixOS configuration is built twice with identical inputs
- **THEN** the Nix store path for the static template is identical (no impure timestamp in the build)

### Requirement: HTTP server serves hostinfo directory
The module SHALL run a long-running `python3 -m http.server` process that serves all files in `/var/lib/hostinfo/` on the configured port. The server SHALL restart automatically on failure.

#### Scenario: services.json accessible via HTTP
- **WHEN** the service is running
- **THEN** `GET http://localhost:3333/services.json` returns the contents of `/var/lib/hostinfo/services.json`

#### Scenario: Additional JSON files served automatically
- **WHEN** a new file (e.g. `sbom.json`) is present in `/var/lib/hostinfo/`
- **THEN** it is accessible via HTTP without any server reconfiguration

#### Scenario: Server restarts on failure
- **WHEN** the Python HTTP server process crashes
- **THEN** systemd restarts it after 10 seconds

### Requirement: Optional SBOM exposure
The module SHALL expose `elastinix.services.hostinfo.enableSbom` as a boolean option (default `false`). When enabled, the module SHALL create a symlink `/var/lib/hostinfo/sbom.json` pointing to `/var/lib/sbom/system.json`.

#### Scenario: SBOM disabled by default
- **WHEN** `enableSbom` is not set
- **THEN** no `/var/lib/hostinfo/sbom.json` symlink is created

#### Scenario: SBOM enabled
- **WHEN** `enableSbom = true`
- **THEN** `/var/lib/hostinfo/sbom.json` is a symlink to `/var/lib/sbom/system.json` and is served by the HTTP server

### Requirement: Optional inventory generation

The module SHALL expose `elastinix.services.hostinfo.enableInventory` as a boolean option with default `true`. When `false`, no inventory systemd units (oneshot service and daily timer) SHALL be created.

#### Scenario: Inventory enabled by default

- **WHEN** `enableInventory` is not set
- **THEN** the `elastinix-hostinfo-inventory` oneshot service and `elastinix-hostinfo-inventory` timer are created and `services.json` is generated

#### Scenario: Inventory disabled

- **WHEN** `enableInventory = false`
- **THEN** no `elastinix-hostinfo-inventory` systemd service or timer is created and no `services.json` is written to `/var/lib/hostinfo/`

#### Scenario: HTTP server runs without inventory

- **WHEN** `enable = true` and `enableInventory = false`
- **THEN** the `elastinix-hostinfo-server` HTTP server still starts and serves any files present in `/var/lib/hostinfo/`

### Requirement: Optional packages inventory exposure

The module SHALL expose `elastinix.services.hostinfo.enablePackages` as a boolean option with default `false`. When `true`, the module SHALL create a symlink `/var/lib/hostinfo/packages.json` pointing to `/var/lib/packages/packages.json`.

#### Scenario: Packages disabled by default

- **WHEN** `enablePackages` is not set
- **THEN** no `/var/lib/hostinfo/packages.json` symlink is created

#### Scenario: Packages enabled

- **WHEN** `enablePackages = true`
- **THEN** `/var/lib/hostinfo/packages.json` is a symlink to `/var/lib/packages/packages.json` and is served by the HTTP server

#### Scenario: Missing source file does not crash server

- **WHEN** `enablePackages = true` but `/var/lib/packages/packages.json` does not yet exist
- **THEN** the HTTP server continues running; a request for `packages.json` returns a 404

### Requirement: Systemd security hardening
The HTTP server service SHALL apply standard elastinix systemd hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, `ProtectKernelTunables`, `ProtectControlGroups`. The service SHALL have `ReadOnlyPaths` covering `/etc` and `/var/lib/hostinfo`.

#### Scenario: Hardened server serves files
- **WHEN** the service runs with security hardening active
- **THEN** it can still read and serve files from `/var/lib/hostinfo/`

### Requirement: Storage directory created automatically
The module SHALL create `/var/lib/hostinfo` via `systemd.tmpfiles.rules` with permissions `0755 root root`.

#### Scenario: Directory exists when service starts
- **WHEN** the service is enabled
- **THEN** `/var/lib/hostinfo` exists with correct permissions before the HTTP server starts
