## 1. Service Module

- [x] 1.1 Replace `modules/nixos/services/service-vulnix-scan.nix` with the new module: options block with `elastinix.services.vulnix-scan.enable`
- [x] 1.2 Add `systemd.tmpfiles.rules` to create `/var/lib/sbom` directory
- [x] 1.3 Add `systemd.services.vulnix-scan` as a oneshot service that runs vulnix against `/run/current-system`, writes JSON to `/var/lib/sbom/system.json`, and handles exit code 2
- [x] 1.4 Add `systemd.timers.vulnix-scan` with `OnCalendar=weekly` and `Persistent=true`
- [x] 1.5 Apply standard elastinix systemd security hardening with `ReadWritePaths=/var/lib/sbom`

## 2. Documentation

- [x] 2.1 Create `docs/services/vulnix-scan.md` with usage, configuration, and manual inspection instructions
- [x] 2.2 Add vulnix-scan link to `docs/README.md` services index

## 3. Verification

- [x] 3.1 Verify the module evaluates cleanly with `nix build`
