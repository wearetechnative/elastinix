# Attic Binary Cache

The Attic service (`elastinix.services.attic`) wraps the NixOS `services.atticd` module to run an [Attic](https://github.com/zhaofengli/attic) binary cache server. Chunks are stored in S3, cache metadata in a database, and the API is published through nginx with automatic TLS.

## Features

- **S3 storage**: NAR chunks go to `<s3_bucket>-<infra_environment>` in `eu-central-1`
- **Database from the secret**: The database URL is read from the agenix environment file, never written to the Nix store
- **No accidental SQLite**: SQLite is only used when it is chosen explicitly
- **Security hardening**: Upstream systemd hardening (`DynamicUser`, `ProtectSystem`, `PrivateTmp`, `NoNewPrivileges`, syscall filtering)
- **nginx front**: `attic.${environment_domain}` (from `tfvars`) with ACME and `forceSSL`, proxying to `127.0.0.1:8080`

## Configuration

### Options

| Option             | Type           | Default | Description                                                                  |
|--------------------|----------------|---------|------------------------------------------------------------------------------|
| `enable`           | boolean        | `false` | Enable the Attic cache                                                       |
| `environment_file` | string         | —       | Absolute path to the environment file (agenix secret) for atticd            |
| `s3_bucket`        | string         | —       | S3 bucket name prefix; `-${infra_environment}` is appended                   |
| `database_url`     | null or string | `null`  | `null`: URL from `ATTIC_SERVER_DATABASE_URL`; string: rendered into the TOML |

### Environment file

The environment file must set:

```
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64 of an RSA private key>
ATTIC_SERVER_DATABASE_URL=postgresql://attic:<password>@psql.example.com/attic
```

`ATTIC_SERVER_DATABASE_URL` is required while `database_url` is `null`. Generate the token key with:

```bash
openssl genrsa -traditional 4096 | base64 -w0
```

### Example with agenix

```nix
age.secrets.attic-env = {
  file = ./secrets/attic-env.age;
  owner = "root";  # read by systemd before DynamicUser applies
  group = "root";
};

elastinix.services.attic = {
  enable = true;
  environment_file = config.age.secrets.attic-env.path;
  s3_bucket = "mycompany-attic";
};
```

## Database

### How the URL is chosen

Attic reads `ATTIC_SERVER_DATABASE_URL` only as a *fallback*: the variable is used only when the configuration file has no `database.url`. The upstream NixOS module always sets `database.url` to a SQLite file by default, so the variable in the environment file used to be ignored.

With `database_url = null` (the default) the module removes the `[database]` url from the generated `checked-attic-server.toml`. Attic then uses the URL from the environment file. If the variable is missing, atticd **fails to start**; it does not fall back to SQLite.

A `database_url` containing a password (`user:password@host` or `?password=`) is refused at evaluation time. The generated configuration lives in the world-readable `/nix/store`, so the password would be readable by every local user and copied with every closure. Put such URLs in the environment file instead.

### What the database holds

The database stores **every cache's signing keypair** and the chunk index. The S3 bucket only holds the chunks, stored under flat keys with nothing that names their cache.

That means the database, not the bucket, decides whether a cache survives:

- Lose the database and keep the bucket, and every cache is gone. The chunks cannot be read or attributed, and every `trusted-public-keys` entry for those caches on consumers can never be satisfied again.
- Keep the database (backed up, outside the instance) and the instance can be replaced freely.

Use the shared PostgreSQL instance, which is backed up, rather than instance-local storage.

### Choosing SQLite explicitly

```nix
elastinix.services.attic.database_url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
```

This puts the database in atticd's state directory (`/var/lib/private/atticd`, on the root volume on EC2), which is lost when the instance is replaced. Only use it for throwaway caches, or give that directory its own persistent, backed-up volume. This setting reproduces the module's behaviour before `database_url` existed, so it is also the rollback.

## Verification

On the host, after a deploy:

```bash
PID=$(systemctl show atticd -p MainPID --value)
ls -l /proc/$PID/fd | grep server.db   # must print nothing
# the caches must be listed in PostgreSQL (attic holds no idle connection,
# so an ss/netstat check can show nothing even when it works):
psql "$ATTIC_SERVER_DATABASE_URL" -c 'select name, created_at from cache'
grep -A2 '^\[database\]' $(systemctl show atticd -p ExecStart --value | grep -o '/nix/store/[^ ]*-checked-attic-server.toml' | head -1)
```

Cache and key check with the client:

```bash
attic cache info <cache>   # Public Key must match the key pinned on consumers
```

## Testing

A NixOS VM test runs atticd against PostgreSQL with the URL only in the environment file. It checks that atticd fails without the variable, then creates a cache, wipes the local state directory, restarts, and compares the cache's public key:

```bash
nix build .#checks.x86_64-linux.attic-database -L
```

## Troubleshooting

| Symptom                                              | Cause                                                                |
|------------------------------------------------------|----------------------------------------------------------------------|
| atticd restarts in a loop right after deploy         | `ATTIC_SERVER_DATABASE_URL` missing from the environment file        |
| Every cache answers `404 NoSuchCache`                | Server runs on an empty database (e.g. explicit SQLite, or a new DB) |
| Evaluation fails: `database_url contains a password` | Move the URL into the environment file, leave `database_url` null    |
