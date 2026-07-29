## ADDED Requirements

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
