<!-- Epic: .beans/elastinix-0r1b--optscale-finops-appliance-service.md -->

## Why

Deploying the OptScale FinOps appliance to AWS today means hand-assembling ~20 systemd services + 6 datastores. `optscale-nixified` now packages the whole thing as a self-contained `nixosModules.optscale-appliance` (one import + `services.optscale.enable`, both architectures) with secrets supplied via a systemd `EnvironmentFile`. This change surfaces it as a first-class elastinix service so an environment can run OptScale on a single EC2 instance with agenix-managed secrets and a TLS-fronted UI, consistent with every other elastinix service.

## What Changes

- Add flake input `optscale` (`github:wearetechnative/optscale-nixified`, `nixpkgs.follows`).
- Import `inputs.optscale.nixosModules.optscale-appliance` in the live and VM system assemblies (`lib/os_config_live.nix`, `lib/os_config_vm.nix`), alongside the other external nixosModules.
- Add `modules/nixos/services/service-optscale.nix` exposing `elastinix.services.optscale`:
  - `enable` → `services.optscale.enable = true` (the whole appliance).
  - `secretsFile` (agenix path) → `services.optscale.secrets.environmentFile` (the EnvironmentFile productionization already in optscale-nixified).
  - Applies OptScale's substrate-pins overlay (`inputs.optscale.overlays.default`) + `allowUnfreePredicate` (mongodb) / `allowInsecurePredicate` (minio) to the machine's pkgs, gated by `enable`, so ClickHouse/RabbitMQ are pinned to OptScale's tested versions and the datastores are permitted.
  - Fronts the ngui UI (`127.0.0.1:4000`) with an nginx virtualHost `optscale.${environment_domain}` (ACME + forceSSL).
- Document the agenix secret contract (one shared file read by the configurator (root) **and** minio (minio group): `owner=root; group=minio; mode=0440`; a valid `Fernet.generate_key()` `ENCRYPTION_KEY`).

## Capabilities

### New Capabilities
- `optscale-service`: The elastinix service that runs the full OptScale appliance on one instance — enable switch, agenix secrets, substrate pinning + datastore allowances, and a TLS-fronted UI.

### Modified Capabilities

## Impact

- **New file**: `modules/nixos/services/service-optscale.nix`.
- **Edited**: `flake.nix` (input), `lib/os_config_live.nix` + `lib/os_config_vm.nix` (import the appliance module).
- **New flake input**: `optscale` (pulls its input closure — uv2nix/pyproject-nix/the pinned OptScale source).
- **New docs**: `docs/services/optscale.md` + index link.
- **Per-environment**: the machine config declares `age.secrets.optscale` (owner root / group minio / mode 0440) and sets `elastinix.services.optscale.{enable, secretsFile}`.
- **Scope**: one appliance per environment on a single instance (not multi-tenant); the appliance's datastores are local. Building the OptScale closure (Python venvs via uv2nix, ngui via pnpm) is heavy but cached; aarch64 (Graviton) is supported by the appliance module.
- **Note**: applying OptScale's overlay changes `pkgs.clickhouse`/`pkgs.rabbitmq-server` on the machine — safe because an OptScale box is dedicated; the overlay/allowances are gated by `enable`.
