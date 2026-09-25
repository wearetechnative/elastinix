---
# elastinix-1itf
title: 'attic module: make the database backend configurable'
status: completed
type: task
priority: high
created_at: 2026-09-24T12:29:40Z
updated_at: 2026-09-25T06:12:24Z
parent: elastinix-mmic
openspec-link: openspec/changes/archive/2026-09-25-attic-database-from-env
---

Add a `database_url` (or equivalent) option to `elastinix.services.attic` and render it into
`services.atticd.settings.database.url`, so cache metadata can live in the shared PostgreSQL
instance instead of instance-local SQLite. Keep the SQLite default only if it is made an
explicit, documented choice rather than an accident of the upstream default.

Acceptance:
- ~~The generated `checked-attic-server.toml` contains the configured `[database] url`.~~
  Superseded by the answer below: the generated TOML must contain **no** `database.url`, so
  that attic falls back to `ATTIC_SERVER_DATABASE_URL`. Putting the URL in the TOML would
  publish the password in `/nix/store`.
- ~~Establish whether upstream attic honours `ATTIC_SERVER_DATABASE_URL`.~~ Answered below: it
  does, as a serde fallback. The variable stays in the agenix EnvironmentFile.
- Document in the module that the per-cache signing keypair is stored in this database, so
  the database, not the S3 bucket, is what determines whether a cache survives.


## Answered 2026-09-24

**Does attic honour `ATTIC_SERVER_DATABASE_URL`?** Yes, but only as a fallback. In
`server/src/config.rs` the field is declared

```rust
#[serde(default = "load_database_url_from_env")]
pub url: String,
```

so `load_database_url_from_env()` runs only when the TOML omits `database.url`. The upstream
nixpkgs module (`nixos/modules/services/networking/atticd.nix:160`) sets
`database.url = lib.mkDefault "sqlite:///var/lib/atticd/server.db?mode=rwc"`, so the key is
always present in the generated `checked-attic-server.toml` and the environment variable is
never consulted. Nothing is broken in attic or in the secret — the module simply never lets
the fallback fire.

**Do not fix this by putting the URL in `settings`.** `settings` is rendered into a file in
`/nix/store`, which is world-readable on the host; the PostgreSQL password would be readable
by every local user and would travel with every closure copy.

**Fix:** clear the section so the fallback applies, e.g.

```nix
services.atticd.settings.database = lib.mkForce { };
```

Both fields of `DatabaseConfig` carry serde defaults (`url` → env, `heartbeat` →
`default_db_heartbeat`), so an empty `[database]` table parses. Preferably expose this through
an elastinix option (e.g. `database_url_from_env`, or a nullable `database_url` where `null`
means "supplied through the EnvironmentFile"). Note that the upstream module derives
`hasLocalPostgresDB` from `cfg.settings.database.url or ""`; with an empty section that
evaluates to `""`, which is correct here because the database is remote.

**SQLite vs PostgreSQL:** PostgreSQL. The shared `poormans-db` is already backed up daily
(`prod-psql-backup.service` → `/data/psqldump/`), the URL is already in the age secret, and the
NAR storage already lives outside the instance in S3. Keeping SQLite would mean a dedicated EBS
volume for `/var/lib/private/atticd` plus its own backup path, to protect a file whose loss
silently invalidates every `trusted-public-keys` entry in the fleet.
