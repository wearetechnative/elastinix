## ADDED Requirements

### Requirement: Module file location and naming
The service module file SHALL be created at `modules/nixos/services/service-<service-name>.nix`. The file is auto-discovered by `import-tree` — no manual registration is needed.

#### Scenario: Module file placed in correct location
- **WHEN** a new file `modules/nixos/services/service-<service-name>.nix` is created
- **THEN** it SHALL be automatically imported by `import-tree` without changes to flake.nix or any index file

### Requirement: Module function signature
The module SHALL use the function signature `{ lib, config, ... }:` at minimum. Additional arguments (e.g., `pkgs`, `tfvars`, `inputs`) MAY be added if needed by the specific service.

#### Scenario: Minimal function signature
- **WHEN** the service does not require packages or tfvars
- **THEN** the function signature SHALL be `{ lib, config, ... }:`

#### Scenario: Extended function signature
- **WHEN** the service requires additional arguments
- **THEN** they SHALL be added to the function signature (e.g., `{ lib, config, pkgs, tfvars, ... }:`)

### Requirement: Configuration let-binding
The module SHALL define `cfg = config.elastinix.services.<service-name>;` in a `let`/`in` block at the top level of the module.

#### Scenario: cfg binding defined
- **WHEN** the module is written
- **THEN** it SHALL contain `let cfg = config.elastinix.services.<service-name>; in` before the attribute set

### Requirement: Enable option
The module SHALL expose `elastinix.services.<service-name>.enable` as a boolean option using `lib.mkEnableOption`.

#### Scenario: Enable option declared
- **WHEN** the module options are defined
- **THEN** `options.elastinix.services.<service-name>` SHALL contain `enable = lib.mkEnableOption "<description>";`

### Requirement: Service-specific options
The module SHALL expose additional options as needed for the upstream service. Before writing the module, the implementer MUST look up the upstream NixOS service options at `https://search.nixos.org/options` for the current NixOS channel. Only essential options that vary between deployments SHALL be exposed (e.g., port, secrets, URLs). Each option MUST specify a `type` and `description`, and SHOULD specify a `default` where a sensible one exists.

#### Scenario: Upstream options researched
- **WHEN** a new service module is being created
- **THEN** the implementer SHALL first look up `services.<upstream-name>` options at `https://search.nixos.org/options` to determine correct option names, types, and defaults

#### Scenario: Minimal option set exposed
- **WHEN** the upstream service has many configurable options
- **THEN** only the options most likely to vary between deployments SHALL be exposed in the Elastinix wrapper

### Requirement: Configuration guard
All service configuration SHALL be wrapped in `config = lib.mkIf cfg.enable { ... }`. No configuration SHALL be applied when the service is not enabled.

#### Scenario: Service disabled
- **WHEN** `elastinix.services.<service-name>.enable` is `false` or unset
- **THEN** no `services.<upstream-name>` configuration SHALL be applied

#### Scenario: Service enabled
- **WHEN** `elastinix.services.<service-name>.enable` is `true`
- **THEN** `services.<upstream-name>.enable` SHALL be set to `true` and Elastinix options SHALL be mapped to their upstream equivalents

### Requirement: Upstream systemd hardening preserved
The module SHALL NOT override or weaken any systemd security hardening provided by the upstream NixOS service module.

#### Scenario: Hardening untouched
- **WHEN** the service is enabled
- **THEN** upstream systemd hardening settings (PrivateTmp, ProtectSystem, NoNewPrivileges, etc.) SHALL remain in effect

### Requirement: Secrets via environment files or agenix paths
If the upstream service supports secret injection (passwords, API keys, tokens), the Elastinix module SHALL expose an option for passing secrets via environment files or agenix-decrypted file paths. Secrets SHALL NOT be stored in the Nix store.

#### Scenario: Secrets passed via environment files
- **WHEN** the upstream service supports `environmentFiles` or similar
- **THEN** the Elastinix module SHALL expose an option to pass file paths for secret injection

#### Scenario: Secrets passed via agenix file path
- **WHEN** the upstream service expects a file path for a secret (e.g., password file)
- **THEN** the Elastinix module SHALL expose a path option compatible with `config.age.secrets.<name>.path`

### Requirement: Flake evaluation
The module SHALL evaluate without errors when checked with `nix flake check --no-build`.

#### Scenario: Clean flake evaluation
- **WHEN** the new module file is added to `modules/nixos/services/`
- **THEN** `nix flake check --no-build` SHALL complete without errors
