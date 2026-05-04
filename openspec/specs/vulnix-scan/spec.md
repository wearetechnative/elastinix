# Capability: vulnix-scan

## Purpose

TBD - Vulnerability scanning service for NixOS systems using vulnix to detect known CVEs in installed packages.

## Requirements

### Requirement: Service enable option
The module SHALL expose `elastinix.services.vulnix-scan.enable` as a boolean option to activate the service. When disabled, no systemd units or tmpfiles rules SHALL be created.

#### Scenario: Service enabled
- **WHEN** `elastinix.services.vulnix-scan.enable` is set to `true`
- **THEN** the system creates `vulnix-scan.service`, `vulnix-scan.timer`, and the `/var/lib/sbom` directory

#### Scenario: Service disabled
- **WHEN** `elastinix.services.vulnix-scan.enable` is set to `false` or not set
- **THEN** no vulnix-scan systemd units or tmpfiles rules are present on the system

### Requirement: Weekly timer schedule
The module SHALL create a systemd timer `vulnix-scan.timer` that triggers `vulnix-scan.service` on a weekly schedule using `OnCalendar=weekly`. The timer SHALL use `Persistent=true` so that missed runs execute on next boot.

#### Scenario: Timer triggers weekly
- **WHEN** the timer is active and a week has elapsed since the last run
- **THEN** `vulnix-scan.service` is started

#### Scenario: Missed run after reboot
- **WHEN** the host was powered off during a scheduled run and then boots up
- **THEN** the service runs shortly after boot to catch up on the missed execution

### Requirement: Generate package manifest from store paths
The service SHALL generate a `packages.json` file by enumerating store paths via `nix-store -qR /run/current-system` and extracting derivation names from the store path format (`/nix/store/<hash>-<name>`). This manifest SHALL be written to `/var/lib/sbom/packages.json`.

#### Scenario: Package manifest generated
- **WHEN** the service runs
- **THEN** `/var/lib/sbom/packages.json` contains a JSON object with an entry for each store path in the system closure, each with a `name` and `patches` field

#### Scenario: No .drv files required
- **WHEN** the service runs on a host where `.drv` files are not present in the Nix store
- **THEN** the package manifest is generated successfully from store path names alone

### Requirement: Scan packages with vulnix
The service SHALL run `vulnix --json --from-file /var/lib/sbom/packages.json --no-requisites` to scan the generated package manifest against the NIST NVD database for known CVEs.

#### Scenario: Successful scan with no vulnerabilities
- **WHEN** vulnix finds no known CVEs matching the packages
- **THEN** vulnix exits with code 0

#### Scenario: Successful scan with vulnerabilities found
- **WHEN** vulnix finds known CVEs matching the packages
- **THEN** vulnix exits with code 2 and the output contains vulnerability data in JSON format

### Requirement: Write SBOM to disk
The service SHALL write the raw vulnix JSON output to `/var/lib/sbom/system.json`. Each run SHALL overwrite the previous file. The `/var/lib/sbom` directory SHALL be created via `systemd.tmpfiles.rules`.

#### Scenario: SBOM file written
- **WHEN** the service completes a scan
- **THEN** `/var/lib/sbom/system.json` contains the raw JSON output from vulnix

#### Scenario: SBOM directory exists
- **WHEN** the service is enabled
- **THEN** `/var/lib/sbom` directory exists with appropriate permissions

### Requirement: Journal logging
The service SHALL log scan activity to the systemd journal. The administrator SHALL be able to review scan results via `journalctl -u vulnix-scan`.

#### Scenario: Vulnerabilities found and logged
- **WHEN** vulnix finds CVEs during a scan
- **THEN** the journal contains output indicating vulnerabilities were found

#### Scenario: Clean scan logged
- **WHEN** vulnix finds no CVEs during a scan
- **THEN** the journal contains output indicating no vulnerabilities were found

### Requirement: Service always exits successfully
The service SHALL always exit with code 0 regardless of whether vulnerabilities are found. Vulnix exit code 2 (vulnerabilities found) SHALL NOT cause the service to report failure.

#### Scenario: Exit code 2 handled
- **WHEN** vulnix exits with code 2 (vulnerabilities found)
- **THEN** the service script exits with code 0 and the systemd service reports success

### Requirement: Systemd security hardening
The service SHALL apply standard elastinix systemd hardening: `PrivateTmp=true`, `ProtectSystem=strict`, `ProtectHome=true`, `NoNewPrivileges=true`, `PrivateDevices=true`, `ProtectKernelTunables=true`, `ProtectKernelModules=true`, `ProtectControlGroups=true`, `RestrictNamespaces=true`, `LockPersonality=true`, `RestrictRealtime=true`, `RestrictSUIDSGID=true`, `RemoveIPC=true`. The service SHALL have `ReadWritePaths=/var/lib/sbom` to allow writing output files.

#### Scenario: Hardened service writes SBOM
- **WHEN** the service runs with security hardening active
- **THEN** it can still read `/nix/store`, query store paths, and write to `/var/lib/sbom/`
