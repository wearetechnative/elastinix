## Why

`elastinix.services.attic` never sets `database.url`, so the upstream NixOS
module's `lib.mkDefault "sqlite:///var/lib/atticd/server.db?mode=rwc"` always
lands in the generated `checked-attic-server.toml`. Attic reads
`ATTIC_SERVER_DATABASE_URL` only as a serde *default* for that key, so the
PostgreSQL URL the hosts already deliver through the agenix `environment_file`
is never consulted. On compute3 (non-production and production) atticd
therefore runs on an empty SQLite file on the root volume, while PostgreSQL
sits unused.

That is not just a wrong database. The per-cache signing keypair and the chunk
index live in that database, and the NARs live in S3. Replacing the instance
throws the root volume away, and with it every cache's private key: the S3
objects survive but become unreadable, and every `trusted-public-keys` entry in
the fleet points at a key that can never sign again. This blocks the workloads
change that pins one shared cache key across the fleet.

## What Changes

- **The database backend becomes an explicit option.** A new
  `elastinix.services.attic.database_url` option (nullable string):
  - `null` (the default): the generated TOML carries **no** `database.url`, so
    attic falls back to `ATTIC_SERVER_DATABASE_URL` from `environment_file`.
    The PostgreSQL password therefore never reaches `/nix/store`.
  - a string: rendered verbatim into `database.url`. Intended for non-secret
    URLs only (e.g. a local SQLite path, if someone deliberately wants one).
- **A URL containing a password is refused at evaluation time**, because
  anything in `settings` is written to the world-readable Nix store.
- **BREAKING (behaviour)**: a host that enables the service without
  `ATTIC_SERVER_DATABASE_URL` in its environment file and without setting
  `database_url` no longer starts silently on SQLite; atticd fails at start up
  instead. SQLite is still available, but only as an explicit choice.
- **The module documents what the database holds**: the per-cache signing
  keypair, so the database - not the S3 bucket - decides whether a cache
  survives an instance replacement.
- New `docs/services/attic.md`, linked from `docs/README.md`.
- A NixOS VM test (`checks.<linux-system>.attic-database`) that runs atticd
  against PostgreSQL with the URL supplied only through the environment file,
  creates a cache, wipes the local state directory and restarts, and proves
  the cache and its public key are unchanged.

## Capabilities

### New Capabilities

- `attic-service`: what the attic NixOS module configures - in this change,
  where its database is taken from, how secrets are kept out of the Nix store,
  and what an operator must know about where cache state lives.

### Modified Capabilities

None.

## Impact

- `modules/nixos/services/service-attic.nix`: new `database_url` option,
  assertion, `services.atticd.settings.database` handling, option
  descriptions.
- `docs/services/attic.md` (new), `docs/README.md` (index entry).
- `tests/attic-database.nix` (new) and a `checks` output in `flake.nix` for the
  Linux systems.
- Hosts consuming the module (compute3 in technative-awsaccounts-workloads)
  need no configuration change: their environment file already carries
  `ATTIC_SERVER_DATABASE_URL`. Deploying them is tracked by elastinix-dewz
  (non-production) and elastinix-dxps (production).

## Tracking

- Bean: [elastinix-1itf](../../../../.beans/elastinix-1itf--attic-module-make-the-database-backend-configurabl.md)
- Epic: [elastinix-mmic](../../../../.beans/elastinix-mmic--atticd-cache-state-must-survive-instance-replaceme.md)
