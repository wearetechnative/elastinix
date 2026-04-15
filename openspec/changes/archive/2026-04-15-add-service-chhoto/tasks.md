## 1. Service Module

- [x] 1.1 Create `modules/nixos/services/service-chhoto.nix` with function signature `{ lib, config, ... }:`
- [x] 1.2 Define `let cfg = config.elastinix.services.chhoto;` binding
- [x] 1.3 Add `options.elastinix.services.chhoto` with enable option via `lib.mkEnableOption`
- [x] 1.4 Add `environmentFiles` option (type: `lib.types.listOf lib.types.path`, default: `[]`)
- [x] 1.5 Add `port` option (type: `lib.types.port`)
- [x] 1.6 Add `siteUrl` option (type: `lib.types.nullOr lib.types.str`, default: `null`)
- [x] 1.7 Add `config = lib.mkIf cfg.enable` block wrapping `services.chhoto-url` configuration
- [x] 1.8 Map all Elastinix options to their upstream `services.chhoto-url` equivalents

## 2. Testing

- [x] 2.1 Verify module evaluates without errors via `nix build`
- [x] 2.2 Verify all option types are correct and defaults apply

## 3. Documentation

- [x] 3.1 Create `docs/services/chhoto.md` with service description, configuration example, and secrets setup
- [x] 3.2 Add chhoto entry to `docs/README.md` service index
