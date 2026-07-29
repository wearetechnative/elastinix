## 1. Module Implementation

- [x] 1.1 Add `enableInventory` boolean option (default `true`) to `modules/nixos/services/service-hostinfo.nix`
- [x] 1.2 Wrap `systemd.services.elastinix-hostinfo-inventory` in `lib.mkIf cfg.enableInventory`
- [x] 1.3 Wrap `systemd.timers.elastinix-hostinfo-inventory` in `lib.mkIf cfg.enableInventory`
- [x] 1.4 Add `enablePackages` boolean option (default `false`) to `modules/nixos/services/service-hostinfo.nix`
- [x] 1.5 Add `lib.optional cfg.enablePackages` symlink rule in `systemd.tmpfiles.rules` pointing `/var/lib/hostinfo/packages.json` → `/var/lib/packages/packages.json`

## 2. Documentation

- [x] 2.1 Update `docs/services/hostinfo.md` with `enableInventory` and `enablePackages` option descriptions and example usage

## 3. Verification

- [x] 3.1 Build with `nix build` (nonProdApply or equivalent) and verify no evaluation errors
- [x] 3.2 Verify that `enableInventory = false` results in no `elastinix-hostinfo-inventory` systemd units
- [x] 3.3 Verify that `enablePackages = true` creates the symlink `/var/lib/hostinfo/packages.json`
