## 1. Research

- [ ] 1.1 Look up upstream NixOS service options at `https://search.nixos.org/options` for the current channel (25.11) to determine correct option names, types, and defaults
- [ ] 1.2 Identify which options to expose in the Elastinix wrapper (enable + essential service-specific options)

## 2. Service Module

- [ ] 2.1 Create `modules/nixos/services/service-<service-name>.nix` with function signature `{ lib, config, ... }:`
- [ ] 2.2 Define `let cfg = config.elastinix.services.<service-name>;` binding
- [ ] 2.3 Add `options.elastinix.services.<service-name>` with `enable = lib.mkEnableOption "<description>";`
- [ ] 2.4 Add service-specific options with correct types, defaults, and descriptions
- [ ] 2.5 Add `config = lib.mkIf cfg.enable { ... }` block that enables the upstream service and maps Elastinix options to upstream equivalents

## 3. Testing

- [ ] 3.1 Verify module evaluates without errors via `nix flake check --no-build`

## 4. Documentation

- [ ] 4.1 Create `docs/services/<service-name>.md` with service description, options table, configuration example, and secrets setup (if applicable)
- [ ] 4.2 Add service entry to `docs/README.md` under the appropriate category
