# OptScale FinOps Appliance

Runs the full [OptScale](https://hystax.com/optscale/) FinOps platform as a single
appliance on one EC2 instance: ~20 native systemd services + 6 datastores (etcd,
MariaDB, MongoDB, ClickHouse, RabbitMQ, MinIO) + the React UI (ngui), bootstrapped by
a configurator oneshot. Packaged by
[optscale-nixified](https://github.com/wearetechnative/optscale-nixified) and consumed
here via its self-contained `nixosModules.optscale-appliance`.

Scope: **one appliance per environment/customer on a dedicated instance** (not
multi-tenant; datastores are local).

## Enabling

```nix
elastinix.services.optscale = {
  enable = true;
  secretsFile = config.age.secrets.optscale.path;
  # subdomain = "optscale";  # UI at optscale.<environment_domain> (default)
};
```

## Secrets (agenix)

All OptScale secrets come from **one** EnvironmentFile, supplied at runtime — nothing
secret enters the Nix store. The same file is read by the configurator (as `root`) and
by MinIO (as its `rootCredentialsFile`), so it must be readable by both:

```nix
age.secrets.optscale = {
  file = ../secrets/optscale_${infra_environment}.age;
  owner = "root";
  group = "minio";   # hardcoded group (avoids a config circular dependency)
  mode  = "0440";
};
```

The decrypted file is plain `KEY=value` lines:

```
MINIO_ROOT_USER=optscale-minio
MINIO_ROOT_PASSWORD=<random>
MARIADB_PASSWORD=<random>
RABBIT_PASSWORD=<random>
CLUSTER_SECRET=<random>
ENCRYPTION_KEY=<Fernet key>
ENCRYPTION_SALT=<random>
ENCRYPTION_SALT_AUTH=<random>
```

`ENCRYPTION_KEY` **must** be a valid Fernet key (32 url-safe-base64 bytes):

```bash
python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
```

Generate distinct values per environment.

## What enabling does

- Enables the whole OptScale appliance (`services.optscale.enable = true`).
- Wires `secretsFile` to `services.optscale.secrets.environmentFile`.
- Applies OptScale's substrate-pins overlay (ClickHouse 24.12 / RabbitMQ 4.1.4) and the
  `allowUnfree`(mongodb) / `allowInsecure`(minio) predicates to the host's package set —
  **gated by `enable`**, so other machines are unaffected.
- Fronts the UI (`127.0.0.1:4000`) with an nginx virtualHost
  `optscale.<environment_domain>` (ACME + forced SSL). Backend services stay on localhost.

## Notes

- Building the OptScale closure (Python venvs via uv2nix, ngui via pnpm, datastore
  binaries) is heavy on first build but cached afterwards. aarch64 (Graviton) is
  supported.
- The overlay changes `pkgs.clickhouse` / `pkgs.rabbitmq-server` on the host — safe
  because an OptScale box is dedicated to the appliance.
- Full end-to-end validation is a deploy-time step (the appliance is verified in
  optscale-nixified's own VM tests: smoke + FinOps round-trip).
