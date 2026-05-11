## 1. Service Module

- [x] 1.1 Create `modules/nixos/services/service-hostinfo.nix` with `elastinix.services.hostinfo` options: `enable`, `port` (default 3333), `enableSbom` (default false)
- [x] 1.2 Add `systemd.tmpfiles.rules` to create `/var/lib/hostinfo` with permissions `0755 root root`
- [x] 1.3 Write static inventory template to Nix store using `pkgs.writeText` (hostname, services, programs, nixosVersion, systemStateVersion — no timestamp)
- [x] 1.4 Add `elastinix-hostinfo-inventory` oneshot systemd service that reads the template, injects `buildTime` via `date -u +%Y-%m-%dT%H:%M:%SZ`, and writes `/var/lib/hostinfo/services.json`
- [x] 1.5 Add `elastinix-hostinfo-inventory` daily systemd timer with `Persistent = true` and `wantedBy = [ "multi-user.target" ]`
- [x] 1.6 Add `elastinix-hostinfo-server` systemd service running `python3 -m http.server` on configured port, serving `/var/lib/hostinfo/`, with `Restart = always` and `RestartSec = 10s`
- [x] 1.7 Apply systemd security hardening to server service: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, `ProtectKernelTunables`, `ProtectControlGroups`, `ReadOnlyPaths = [ "/etc" "/var/lib/hostinfo" ]`
- [x] 1.8 Add `networking.firewall.allowedTCPPorts = [ cfg.port ]`
- [x] 1.9 Add `enableSbom` symlink via tmpfiles: `L+ /var/lib/hostinfo/sbom.json - - - - /var/lib/sbom/system.json` (only when `enableSbom = true`)

## 2. Documentation

- [x] 2.1 Create `docs/services/hostinfo.md` covering: purpose, configuration options, JSON output format, example `services.json`, enabling SBOM, useful commands
- [x] 2.2 Add `hostinfo` entry to `docs/README.md` services index

## 3. Verification

- [x] 3.1 Verify the module builds with `nix build` (nonProdApply or equivalent)
- [ ] 3.2 Confirm `/var/lib/hostinfo/services.json` is accessible via HTTP after deploy
- [ ] 3.3 Confirm `buildTime` is populated with current timestamp (not a placeholder)

## 4. Migration (technative-awsaccounts-workloads)

- [x] 4.1 Remove `lib/elastinix-inventory.nix`
- [x] 4.2 Remove `lib/elastinix-sbom.nix`
- [x] 4.3 Update `stack/ec2_compute2/nix/hostconf.nix`: remove the two lib imports, add `elastinix.services.hostinfo = { enable = true; enableSbom = true; };`
