# Vaultwarden

Runs Vaultwarden, the Bitwarden-compatible password server
(`services.vaultwarden` from nixpkgs), with the PostgreSQL backend and an
nginx virtual host `vaultwarden.<environment_domain>` with ACME TLS. nginx
proxies to Vaultwarden on `127.0.0.1:8222`.

## Options

All options live under `elastinix.services.vaultwarden`.

| Option             | Type    | Default              | Description                                |
| ------------------ | ------- | -------------------- | ------------------------------------------ |
| `enable`           | bool    | `false`              | Enable Vaultwarden                         |
| `source`           | enum    | `"nixpkgs"`          | Where the default `package` comes from     |
| `package`          | package | selected by `source` | Vaultwarden package to run                 |
| `environment_file` | str     | —                    | Path to the Vaultwarden environment file   |

`environment_file` is a path string, so its secrets (`DATABASE_URL`,
`ADMIN_TOKEN`, SMTP credentials, …) never enter the Nix store. Point it at an
agenix secret (`config.age.secrets.<name>.path`).

```nix
elastinix.services.vaultwarden = {
  enable = true;
  environment_file = config.age.secrets.vaultwarden-env.path;
};
```

## `source` and `package`

`source` picks the default of `package`:

| `source`   | Package                                                        | Version (2026-11) |
| ---------- | -------------------------------------------------------------- | ----------------- |
| `nixpkgs`  | `pkgs.vaultwarden` (nixos-26.05)                               | 1.37.4            |
| `pinned`   | `pkgs.callPackage <elastinix>/pkgs/vaultwarden/package.nix { }`| 1.37.5            |
| `unstable` | `vaultwarden` from the `nixpkgs-unstable` input                | 1.37.2            |

Use `pinned` when nixpkgs lags behind a Vaultwarden release you need, for
example a security fix:

```nix
elastinix.services.vaultwarden.source = "pinned";
```

Every package is selected per service, not through an overlay, so
`pkgs.vaultwarden` stays the nixpkgs package for every other module. The web
vault always comes from the selected package (`package.webvault`), so server
and web vault stay matched. `unstable` follows the `nixpkgs-unstable` lock,
which documenso shares.

An explicit `package` wins over `source`:

```nix
elastinix.services.vaultwarden.package = myVaultwarden;
```

A custom package without a `webvault` attribute gets the web vault of
`pkgs.vaultwarden`.

The pinned build is not on cache.nixos.org, so a host compiles it unless it
pulls from the `technative:tn-infra` attic cache. Push it there when a host
uses `pinned`.

## Minimum version and downgrades

Vaultwarden migrates its database forward only. The module warns at build
time when the package is older than its minimum version (`minimumVersion` in
`service-vaultwarden.nix`, now **1.37.2**, what production runs). The build
still succeeds.

Before running an older release than the database has seen, restore a
psqldump backup taken before the upgrade. Raise `minimumVersion` after every
production upgrade.

## Where the pinned version is set

`pkgs/vaultwarden/source.json` is the single source of truth for `pinned`:

```json
{
  "owner": "dani-garcia",
  "repo": "vaultwarden",
  "rev": "6ed6921cc2b0e03b4d74189574d2a5e71c512e97",
  "hash": "sha256-7r4vTThc98coMIOxPA61X/A8pLiAfPVJxJlWQY8yELw=",
  "cargoHash": "sha256-onyxPAt3bVsF9Zj0Z+rnXoUA0NQLabYxxGqzhnVHz/E=",
  "version": "1.37.5",
  "webvault": {
    "version": "2026.10.1",
    "hash": "sha256-02Zo+Ih5HzFQENUV1URGg2OlLkhMOMpnOPPjj/xvjI0="
  }
}
```

The rest of `pkgs/vaultwarden/`:

- `package.nix`: the server build, a copy of the nixpkgs recipe. It uses Rust 1.98, because Vaultwarden 1.37.5 needs at least 1.97.1 and the default rustc in nixos-26.05 is 1.95.
- `webvault.nix`: the prebuilt web vault from the `dani-garcia/bw_web_builds` releases, at the version the server tag names in `docker/DockerSettings.yaml`.
- `update.sh` and `update.nix`: the update script and its wrapper.

The flake exposes the server as `packages.<system>.vaultwarden` for
`x86_64-linux` and `aarch64-linux`, built for PostgreSQL:

```bash
nix build .#vaultwarden
./result/bin/vaultwarden --version
```

## Updating the pinned version

1. Regenerate `source.json` for an upstream tag. This also looks up and
   prefetches the matching web vault:

   ```bash
   nix run --impure --expr \
     '(import (builtins.getFlake (toString ./.)).inputs.nixpkgs {}).callPackage ./pkgs/vaultwarden/update.nix {}' \
     -- 1.37.6 ./pkgs/vaultwarden
   ```

2. `cargoHash` is now empty. Build, and paste the `got:` hash into
   `cargoHash`:

   ```bash
   nix build .#vaultwarden
   ```

3. Build again and check `./result/bin/vaultwarden --version`.
4. If the new release needs a newer Rust than `rustPackages_1_98`, change it
   in `package.nix`.

## Notes

- Elastinix systemd hardening is the upstream module's; this module only adds
  `/vaultwarden` to `ReadWritePaths`.
- `pkgs.system-sendmail` is installed for Vaultwarden's sendmail mail
  transport.
