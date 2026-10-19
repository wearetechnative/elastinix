# Tasks

## 1. Vendor the Zammad recipe

- [x] 1.1 Copy `pkgs/by-name/za/zammad/{package.nix,source.json,gemset.nix,fix-sendmail-location.diff,update.sh,update.nix}` from nixpkgs rev `774debe7a0d1b496e35677ad955a1011c6ff74f3` into `pkgs/zammad/`, and verify that `diff -r` against that nixpkgs path shows no differences yet
- [x] 1.2 Add `"version": "7.1.3"` to `pkgs/zammad/source.json`. Make `package.nix` read `version` from it and pass `removeAttrs source [ "version" ]` to `fetchFromGitHub`. Verify that `nix eval --impure --expr '(import <nixpkgs> {}).callPackage ./pkgs/zammad/package.nix {}' --apply 'p: p.version'` (or the flake output from 2.1) prints `7.1.3`
- [x] 1.3 Rewrite `pkgs/zammad/update.sh` to require exactly one tag argument (usage + non-zero exit otherwise), default the target dir to the script dir, write `version` into `source.json` with `jq`, drop the ftp scraping and yarn leftovers, and print the pnpm-hash reminder at the end. Use the `#!/usr/bin/env bash` shebang. Verify that running it without arguments exits non-zero and leaves `git status pkgs/zammad` clean
- [x] 1.4 Update `pkgs/zammad/update.nix`: remove `yarn`, `xidel` and `common-updater-scripts` from `buildInputs`, add `curl`/`gnutar`. Verify that `nix build --impure --expr '(import <nixpkgs> {}).callPackage ./pkgs/zammad/update.nix {}'` succeeds

## 2. Flake output

- [x] 2.1 Add `packages = lib.optionalAttrs pkgs.stdenv.isLinux { zammad = pkgs.callPackage ./pkgs/zammad/package.nix { }; };` to `perSystem` in `flake.nix`. Verify that `nix flake show` lists `packages.x86_64-linux.zammad` and `packages.aarch64-linux.zammad`, and no darwin `zammad`
- [x] 2.2 Build it: `nix build .#zammad`. Verify that the build succeeds and that `result/` contains `public/assets` plus the `config/database.yml` → `/var/lib/zammad/config/database.yml` symlink. If the pnpm hash mismatches against the main nixpkgs, update it from the `got:` value and rebuild

## 3. Service module default

- [x] 3.1 In `modules/nixos/services/service-zammad.nix`, set `package.default` to `pkgs.callPackage ../../../pkgs/zammad/package.nix { }`, add a `defaultText` (`lib.literalExpression`) and a real `description`. Verify with a `nix eval` of a minimal `nixosSystem` that imports the module with `elastinix.services.zammad.enable = true` (stub `tfvars`): `config.services.zammad.package.version` must be `7.1.3`
- [x] 3.2 Verify the override path: in the same eval with `elastinix.services.zammad.package = pkgs.zammad`, `config.services.zammad.package.version` equals the nixpkgs version (7.1.1). Also verify that `pkgs.zammad.version` stays 7.1.1 when the service is enabled (no global overlay)
- [x] 3.3 Verify that `zammad-advisory-monitor` picks up the vendored version: in the eval from 3.1, the monitor's derived `zammadVersion` evaluates to `7.1.3`

## 4. Documentation

- [x] 4.1 Write `docs/services/zammad.md`: purpose, options (incl. `package` and its vendored default), where the version is pinned (`pkgs/zammad/source.json`), and the update procedure (`update.sh <tag>` → set pnpm hash to `lib.fakeHash` → `nix build .#zammad` → paste the `got:` hash → rebuild → push to attic → bump consumers). Verify that every command in the doc runs as written (apart from the attic push credentials)
- [x] 4.2 Add a Zammad entry linking `services/zammad.md` to `docs/README.md`, and an entry to `CHANGELOG.md`. Verify that the links resolve

## 5. Integration check

- [x] 5.1 Run `nix flake check --no-build` and confirm that existing checks still evaluate. Then verify that a VM or `nonProdApply` build of a consumer host with Zammad enabled, pinned to this branch, builds against the vendored 7.1.3 package
  - Verified on a minimal NixOS host (nixos-26.05 `8eeec93`) with `elastinix.services.zammad` enabled: the system closure builds, and `zammad-web.service` runs the same `zammad-7.1.3` store path as `.#zammad`. compute3 itself (workloads) is built in its own follow-up.

## Workflow follow-up

- Push `.#zammad` to attic before consumers re-pin.
- workloads/compute3: drop the `zammad-elastinix` input and the `package = zammadPkgs.zammad` line, then re-pin elastinix (tracked in workloads, no elastinix bean).
- Delete the `update-zammad` branch in elastinix once compute3 is off it.
- Archive this change with `/opsx:archive` and add `openspec-link` to bean elastinix-do0e.
