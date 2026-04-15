## Context

Elastinix wraps NixOS services into opinionated modules under the `elastinix.services.*` namespace. Chhoto-url is a lightweight URL shortener available in NixOS 25.11 via `services.chhoto-url`. It uses SQLite for storage, needs no external database, and the upstream NixOS module already includes systemd security hardening.

Existing Elastinix services (vaultwarden, traefik, hedgedoc, freshrss) follow a consistent pattern: minimal options wrapping the upstream NixOS service, with secrets passed via environment files.

## Goals / Non-Goals

**Goals:**
- Single-file service module following existing Elastinix conventions
- Expose only essential options: enable, environmentFiles, port, site_url
- Delegate all other configuration to upstream NixOS defaults
- Support secret injection (password, API key) via environment files

**Non-Goals:**
- Multi-instance support (not needed for a URL shortener)
- Nginx/traefik reverse proxy configuration (handled separately per deployment)
- Exposing all upstream chhoto-url settings (keep it minimal)
- Flake input changes (chhoto-url is already in nixpkgs)

## Decisions

### 1. Single-instance, not multi-instance

Chhoto-url is a simple URL shortener. There's no use case for running multiple instances. This avoids the complexity of `attrsOf submodule` and the circular dependency risks with agenix that jirasync encountered.

**Alternative**: Multi-instance pattern — rejected as unnecessary complexity.

### 2. Use `environmentFiles` (list of paths) instead of single `environment_file`

The upstream NixOS module uses `environmentFiles` (plural, list of paths). Matching this avoids a confusing 1:1 mapping and allows composing secrets from multiple sources (e.g., agenix + other).

**Alternative**: Single `environment_file` string like vaultwarden — rejected because upstream uses a list, and lists are more flexible.

### 3. Expose `port` and `site_url` as direct options

These are the two settings most likely to vary between deployments. Other settings (slug_style, redirect_method, etc.) have sensible defaults and can be changed upstream if needed.

**Alternative**: Expose a full `settings` attrset passthrough — rejected as over-engineering for a simple service.

### 4. No reverse proxy configuration included

Some Elastinix services (vaultwarden, hedgedoc, freshrss) bundle nginx config. However, deployments may use traefik instead. Keeping proxy config out of the module keeps it focused and composable.

**Alternative**: Include nginx virtualHost config — rejected because proxy choice varies per deployment.

## Risks / Trade-offs

- **Limited configurability**: Only 4 options exposed. If a deployment needs to change `slug_style` or `redirect_method`, they'd need to set it via upstream `services.chhoto-url.settings` directly alongside the Elastinix module.
  → Mitigation: This is acceptable and matches how other minimal Elastinix services work. Options can be added later if needed.

- **Upstream module availability**: Depends on chhoto-url being in NixOS 25.11.
  → Mitigation: Already verified as available in the 25.11 channel.
