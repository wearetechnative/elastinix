## Why

Adding new services to Elastinix requires following a consistent module pattern, documentation structure, and integration approach. This generic change serves as a reusable blueprint so that any new NixOS service can be added with the correct conventions every time — whether by a human or an AI agent.

## What Changes

- Add a new service module at `modules/nixos/services/service-<service-name>.nix`
- The module wraps an upstream NixOS service under `elastinix.services.<service-name>`
- Mandatory: enable option, `cfg` let-binding, `lib.mkIf cfg.enable` guard
- Optional: additional service-specific options (port, secrets, URLs, etc.)
- Add service documentation at `docs/services/<service-name>.md`
- Add service entry to `docs/README.md` index

## Capabilities

### New Capabilities

- `service-module`: The NixOS service module following the canonical Elastinix pattern with required structure and options
- `service-docs`: Mandatory documentation for the new service in docs/services/ and docs/README.md index

### Modified Capabilities

_(none)_

## Impact

- **New file**: `modules/nixos/services/service-<service-name>.nix` (auto-discovered by `import-tree`)
- **New file**: `docs/services/<service-name>.md`
- **Modified file**: `docs/README.md` (new entry in service index)
- **No flake.nix changes** unless the service requires an external flake input
