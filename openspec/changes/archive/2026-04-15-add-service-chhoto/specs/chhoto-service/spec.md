## ADDED Requirements

### Requirement: Service enable option
The module SHALL expose `elastinix.services.chhoto.enable` as a boolean option (via `lib.mkEnableOption`). When disabled, no chhoto-url configuration SHALL be applied.

#### Scenario: Service disabled by default
- **WHEN** `elastinix.services.chhoto.enable` is not set
- **THEN** no `services.chhoto-url` configuration is applied to the system

#### Scenario: Service enabled
- **WHEN** `elastinix.services.chhoto.enable` is set to `true`
- **THEN** `services.chhoto-url.enable` SHALL be set to `true` in the NixOS configuration

### Requirement: Environment files option for secrets
The module SHALL expose `elastinix.services.chhoto.environmentFiles` as an option of type `lib.types.listOf lib.types.path`. This option SHALL be passed directly to `services.chhoto-url.environmentFiles` for secret injection (password, API key).

#### Scenario: Secrets provided via environment files
- **WHEN** `elastinix.services.chhoto.environmentFiles` is set to `["/run/agenix/chhoto-env"]`
- **THEN** `services.chhoto-url.environmentFiles` SHALL contain `["/run/agenix/chhoto-env"]`

#### Scenario: No environment files provided
- **WHEN** `elastinix.services.chhoto.environmentFiles` is not set
- **THEN** `services.chhoto-url.environmentFiles` SHALL default to an empty list `[]`

### Requirement: Port option
The module SHALL expose `elastinix.services.chhoto.port` as an option of type `lib.types.port`. This option SHALL be passed to `services.chhoto-url.settings.port`.

#### Scenario: Custom port configured
- **WHEN** `elastinix.services.chhoto.port` is set to `4567`
- **THEN** `services.chhoto-url.settings.port` SHALL be `4567`

### Requirement: Site URL option
The module SHALL expose `elastinix.services.chhoto.siteUrl` as an option of type `lib.types.nullOr lib.types.str` defaulting to `null`. This option SHALL be passed to `services.chhoto-url.settings.site_url`.

#### Scenario: Site URL configured
- **WHEN** `elastinix.services.chhoto.siteUrl` is set to `"https://go.example.com"`
- **THEN** `services.chhoto-url.settings.site_url` SHALL be `"https://go.example.com"`

#### Scenario: Site URL not configured
- **WHEN** `elastinix.services.chhoto.siteUrl` is not set
- **THEN** `services.chhoto-url.settings.site_url` SHALL be `null` (upstream default)

### Requirement: Module structure follows Elastinix conventions
The module file SHALL be located at `modules/nixos/services/service-chhoto.nix`. It SHALL use `let cfg = config.elastinix.services.chhoto;` and wrap all configuration in `config = lib.mkIf cfg.enable { ... }`.

#### Scenario: Module file structure
- **WHEN** the module file is loaded
- **THEN** it SHALL define options under `options.elastinix.services.chhoto` and configuration under `config = lib.mkIf cfg.enable`

### Requirement: Upstream systemd hardening preserved
The module SHALL NOT override or weaken the upstream `services.chhoto-url` systemd security hardening. The upstream module already provides PrivateTmp, ProtectSystem, NoNewPrivileges, and other hardening settings.

#### Scenario: Security hardening active
- **WHEN** the service is enabled
- **THEN** the upstream systemd hardening settings SHALL remain in effect (not overridden by the Elastinix module)
