## Context

Elastinix wraps NixOS services into opinionated modules under the `elastinix.services.*` namespace. There are ~28 service modules in `modules/nixos/services/`. All follow a consistent pattern but this pattern has never been formally documented as a reusable blueprint.

This design captures the canonical pattern so any new service — added by a human or AI — follows the same conventions.

## Goals / Non-Goals

**Goals:**
- Define the exact file structure and Nix module pattern for a new service
- Document the `import-tree` auto-discovery mechanism (no manual registration needed)
- Establish the process for researching upstream NixOS service options before writing the module
- Make documentation (docs/services/ + docs/README.md) a mandatory part of adding a service

**Non-Goals:**
- Prescribing which specific options each service must expose (beyond `enable`) — this is service-dependent
- Multi-instance service pattern (covered separately; most services are single-instance)
- Reverse proxy configuration (traefik/nginx choice varies per deployment)
- Flake input changes (only needed if the service is not already in nixpkgs)

## Decisions

### 1. Canonical module structure

Every service module MUST follow this structure:

```nix
{ lib, config, ... }:
let
  cfg = config.elastinix.services.<service-name>;
in
{
  options.elastinix.services.<service-name> = {
    enable = lib.mkEnableOption "<description>";
    # Additional service-specific options here
  };

  config = lib.mkIf cfg.enable {
    services.<upstream-service-name> = {
      enable = true;
      # Map elastinix options to upstream options
    };
  };
}
```

**Why this pattern**: It matches all existing Elastinix services, provides a clean separation between option declaration and configuration, and ensures services are only activated when explicitly enabled.

### 2. Research upstream options first

Before writing the module, the implementer (human or AI) MUST look up the upstream NixOS service options at `https://search.nixos.org/options` for the target NixOS channel (currently 25.11). This ensures:
- The correct upstream option names and types are used
- Only genuinely useful options are exposed in the Elastinix wrapper
- Default values align with upstream expectations

**Alternative**: Guessing option names from documentation — rejected because NixOS option search is the authoritative source.

### 3. Auto-discovery via import-tree

Service modules are automatically imported by `import-tree` (from `github:vic/import-tree`) in `lib/os_config_live.nix` and `lib/os_config_vm.nix`:

```nix
(inputs.import-tree ../modules/nixos/services)
```

This means: placing `service-<name>.nix` in `modules/nixos/services/` is sufficient. No registration in flake.nix or any index file is needed.

### 4. Minimal option exposure with upstream fallback

The Elastinix module should expose only the essential options needed for typical deployments — usually `enable` plus a small number of service-specific options (port, secrets, URLs). For advanced configuration, users can set upstream `services.<name>` options directly alongside the Elastinix module.

**Why**: Keeps the module simple and maintainable. Avoids duplicating the entire upstream option set.

### 5. Mandatory documentation

Every new service MUST include:
- `docs/services/<service-name>.md` — service description, options table, configuration example, secrets setup
- An entry in `docs/README.md` under the appropriate category

## Risks / Trade-offs

- **Limited option coverage**: Only essential options are exposed. Users needing advanced configuration must use upstream options directly.
  → Mitigation: This is documented and intentional. Options can be added later.

- **Upstream option changes**: NixOS upstream may rename or restructure service options between releases.
  → Mitigation: Pin to a specific NixOS channel (25.11). Review on channel upgrades.
