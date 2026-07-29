## Why

The `hostinfo` service always generates `services.json` when enabled, but operators may want to run the HTTP server without the inventory (e.g. to serve only `packages.json` or `sbom.json`). Additionally, Terraform uploads a package inventory to `/var/lib/packages/packages.json` that currently has no way to be exposed via the hostinfo endpoint.

## What Changes

- Add `enableInventory` boolean option (default `true`) to `elastinix.services.hostinfo` — controls whether the inventory timer and oneshot service that generate `services.json` are created. Default `true` preserves existing behaviour.
- Add `enablePackages` boolean option (default `false`) to `elastinix.services.hostinfo` — when `true`, creates a symlink `/var/lib/hostinfo/packages.json → /var/lib/packages/packages.json`, following the same pattern as `enableVulnixReport` and `enableSbom`.

## Capabilities

### New Capabilities

_(none — both options extend the existing `hostinfo-service` capability)_

### Modified Capabilities

- `hostinfo-service`: Two new boolean options added (`enableInventory`, `enablePackages`) with associated scenarios for enabling/disabling inventory generation and packages exposure.

## Impact

- **Modified file**: `modules/nixos/services/service-hostinfo.nix`
- **Modified spec**: `openspec/specs/hostinfo-service/spec.md` (delta spec adds new requirements)
- **No breaking changes**: `enableInventory` defaults to `true`, preserving current behaviour
