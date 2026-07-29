## Why

System information (enabled services, vulnerability data) is currently exposed via ad-hoc lib files in a downstream repo (`technative-awsaccounts-workloads`), making it unavailable to other elastinix deployments. Moving this into elastinix as a reusable service makes host introspection a first-class capability.

## What Changes

- New `elastinix.services.hostinfo` NixOS module that serves JSON files from `/var/lib/hostinfo/` via Python `http.server`
- `services.json` generated daily by a systemd timer+oneshot service, containing enabled elastinix services/programs, hostname, NixOS version, and `buildTime`
- Optional `enableSbom` flag symlinks `/var/lib/sbom/system.json` → `/var/lib/hostinfo/sbom.json`
- Firewall opens on configured port (default `3333`)
- New documentation at `docs/services/hostinfo.md`
- `lib/elastinix-inventory.nix` and `lib/elastinix-sbom.nix` in `technative-awsaccounts-workloads` become obsolete and should be removed

## Capabilities

### New Capabilities

- `hostinfo-service`: NixOS service module that generates and serves host inventory JSON (services list, buildTime, system metadata) and optionally exposes SBOM data via HTTP

### Modified Capabilities

<!-- none -->

## Impact

- **elastinix**: new service module `modules/nixos/services/service-hostinfo.nix`, new docs `docs/services/hostinfo.md`
- **technative-awsaccounts-workloads**: remove `lib/elastinix-inventory.nix` and `lib/elastinix-sbom.nix`; update `stack/ec2_compute2/nix/hostconf.nix` to use `elastinix.services.hostinfo`
- **Future work**: nginx vhost (bean `elastinix-n3zn`), rename `buildTime` → `lastUpdated` + lambda update (bean `elastinix-vtja`)
