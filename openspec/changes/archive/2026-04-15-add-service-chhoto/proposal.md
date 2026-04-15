## Why

Elastinix needs a URL shortener service for internal use. Chhoto-url is a lightweight, self-hosted URL shortener already available in NixOS 25.11. Adding it as an Elastinix service module makes it easy to deploy across the NixOS product family on AWS with consistent configuration and security hardening.

## What Changes

- Add new service module `modules/nixos/services/service-chhoto.nix`
- Expose `elastinix.services.chhoto` with enable, environmentFiles, port, and site_url options
- Wrap the upstream `services.chhoto-url` NixOS service with Elastinix conventions
- Apply standard systemd security hardening (upstream already provides this)

## Capabilities

### New Capabilities

- `chhoto-service`: NixOS service module wrapping chhoto-url with the Elastinix service pattern, exposing essential configuration options and delegating to upstream defaults for everything else.

### Modified Capabilities

_(none)_

## Impact

- **New file**: `modules/nixos/services/service-chhoto.nix`
- **Dependencies**: Requires NixOS 25.11 (chhoto-url module available upstream)
- **No breaking changes** to existing services or configuration
