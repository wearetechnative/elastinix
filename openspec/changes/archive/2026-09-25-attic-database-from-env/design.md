## Context

See proposal.md - Why. The relevant mechanics:

- attic `server/src/config.rs` declares `#[serde(default = "load_database_url_from_env")] pub url: String`
  on `DatabaseConfig`; `heartbeat` also has a serde default. An empty
  `[database]` table therefore parses, and the environment variable is read
  only when the key is absent.
- The upstream module (`nixos/modules/services/networking/atticd.nix`) sets
  `services.atticd.settings.database.url = lib.mkDefault "sqlite:///var/lib/atticd/server.db?mode=rwc"`,
  renders `settings` with `pkgs.formats.toml` into `/nix/store`, and runs
  `atticd --mode check-config` on it with `ATTIC_SERVER_DATABASE_URL="sqlite://:memory:"`
  exported - so a TOML without `database.url` still passes the build check.
- The unit uses `EnvironmentFile = cfg.environmentFile`, `DynamicUser = true`
  and `StateDirectory = "atticd"` (`/var/lib/private/atticd`, on the root
  volume on EC2). `atticd-atticadm` passes the same environment file.
- `hasLocalPostgresDB` reads `cfg.settings.database.url or ""`; with the key
  absent it is false, which is right for the remote database the hosts use.

## Goals / Non-Goals

**Goals:**
- Database URL from the agenix environment file is what atticd actually uses.
- No credential ever rendered into the store.
- SQLite remains possible, but only by writing it down.

**Non-Goals:**
- Provisioning the PostgreSQL database or role (the shared instance already
  has them; that is host/infra work).
- Fixing the doubled `-${infra_environment}` bucket suffix seen on production;
  the deploy itself is elastinix-dxps.
- Adding a local-PostgreSQL mode to the module.

## Decisions

### Nullable `database_url`, `null` meaning "from the environment file"

Alternatives: a boolean `database_url_from_env`, or an enum backend option.
A single nullable string says both things in one place - "no URL here" and
"this exact URL" - and matches the bean's suggestion. `null` as default
matches how every current host is configured (URL already in the secret), so
no host config changes.

### Clear the section with `lib.mkForce { }`

`services.atticd.settings.database = lib.mkForce { }` when `database_url` is
null; `database.url = cfg.database_url` (normal priority, beats the upstream
`mkDefault`) otherwise. `mkForce` on the whole `database` attribute is needed
because a lower-priority definition cannot remove a key another module set;
force priority discards the upstream `mkDefault` definition entirely. Setting
`url = ""` instead would not work: serde would take the empty string, not the
fallback.

### Refuse passwords by pattern, as an assertion

`database_url` is matched against `^[^:]+://[^/@]*:[^/@]*@.*` (userinfo with a
password) and `.*[?&]password=.*` (libpq-style query parameter). An assertion
rather than a warning, because the damage (password in every closure copy) is
done by the build, before anyone reads a warning. Heuristic, not exhaustive
- it catches the two forms attic's sqlx URL parser accepts.

### Test as a NixOS VM test in `flake.nix` `checks`

The flake has no `checks` yet. It is added through flake-parts `perSystem`,
only for Linux systems (`lib.optionalAttrs pkgs.stdenv.isLinux`), so the
Darwin systems keep evaluating. The test file lives at `tests/attic-database.nix`,
outside `modules/nixos/`, because `import-tree` imports every `.nix` file
under the module directories as a NixOS module.

The test imports the real `service-attic.nix` with `tfvars` passed through
`node.specialArgs`, runs a local PostgreSQL with password auth over TCP, and
writes the environment file at run time (so the test does not ship a secret in
its own derivation beyond throwaway values). S3 storage is kept as configured;
creating a cache and reading its config do not touch storage. ACME is pointed
at nothing reachable - the nginx vhost is not under test.

## Risks / Trade-offs

- [Hosts without `ATTIC_SERVER_DATABASE_URL` stop starting] → Intentional;
  documented as BREAKING. Both known consumers (compute3 np/prod) carry the
  variable already.
- [First start against an existing PostgreSQL schema runs migrations] → Moot
  for compute3: both attic databases were recreated empty (elastinix-eyrj).
- [Password heuristic misses an exotic form] → Documented; the option
  description says secret URLs belong in the environment file.
- [VM test runs slowly without KVM] → Acceptable; it is a check, not part of
  host builds.

## Migration Plan

1. Merge; consumers bump elastinix.
2. Deploy compute3-nonprod, verify with the recipe in elastinix-dewz (no
   `server.db` fd, connection to 5432, 200 for an existing cache).
3. Production follows in elastinix-dxps.

Rollback: set `database_url = "sqlite:///var/lib/atticd/server.db?mode=rwc"`
on the host, which reproduces the previous behaviour exactly.
