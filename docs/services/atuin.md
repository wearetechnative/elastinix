# Atuin Shell-History Sync Server

The Atuin service (`elastinix.services.atuin`) wraps the NixOS `services.atuin` module to run a self-hosted [Atuin](https://atuin.sh) server for syncing encrypted shell history across machines, fronted by nginx with automatic TLS.

> **Migration note**: This service previously ran Atuin as an OCI/Docker container (`docker-atuin.nix`). It now uses the native `services.atuin` NixOS module. The option API changed accordingly — see [Migration from the Docker module](#migration-from-the-docker-module).

## Features

- **Native module**: Runs `atuin server start` directly via systemd, no container runtime required
- **Security hardening**: Upstream systemd hardening (`DynamicUser`, `ProtectSystem`, `PrivateTmp`, `NoNewPrivileges`, syscall filtering)
- **Local or external database**: Provision a local PostgreSQL database automatically, or point at an external one via a secret
- **Secret injection**: External database URI supplied via an environment file (agenix compatible), never written to the Nix store
- **Loopback by default**: The server binds to `127.0.0.1`; only the local nginx reverse proxy reaches it
- **Registration closed by default**: New-user registration is disabled unless explicitly enabled

## Configuration

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the Atuin server |
| `package` | package | `pkgs.atuin` | The Atuin package to run as the server |
| `host` | string | `"127.0.0.1"` | Address the server listens on (loopback so only nginx reaches it) |
| `port` | port | `8888` | Port the server listens on (proxied by nginx) |
| `open_registration` | boolean | `false` | Allow new user registrations |
| `max_history_length` | int | `8192` | Maximum length of each stored history item |
| `create_postgresql_database` | boolean | `true` | Create and manage a local PostgreSQL database/user (`atuin`) over a unix socket |
| `environment_file` | null or path | `null` | Environment file (e.g. agenix secret) providing `ATUIN_DB_URI`; required when `create_postgresql_database` is `false` |

The service is published at `atuin.${environment_domain}` (from `tfvars`) with ACME/`forceSSL` enabled, proxying to `127.0.0.1:<port>`.

### Basic Example (local database)

```nix
elastinix.services.atuin = {
  enable = true;
  # create_postgresql_database defaults to true: a local PostgreSQL
  # database and user named "atuin" are provisioned automatically.
};
```

### External Database with Agenix

Set `create_postgresql_database = false` and provide the connection string via an environment file. Create the file with the `ATUIN_DB_URI` variable:

```
ATUIN_DB_URI=postgres://atuin:your-secret-password@db.example.com/atuin
```

Encrypt it with agenix and reference it in `environment_file`:

```nix
age.secrets.atuin-db = {
  file = ./secrets/atuin-db.age;
  owner = "root";  # hardcoded; read by systemd before the service drops privileges
  group = "root";
};

elastinix.services.atuin = {
  enable = true;
  create_postgresql_database = false;
  environment_file = config.age.secrets.atuin-db.path;
};
```

The file is read by systemd as root, so the unprivileged (`DynamicUser`) service never needs read access to the secret.

## Advanced Configuration

For settings not exposed by the Elastinix wrapper, use the upstream NixOS options directly alongside the Elastinix module — for example to open the server port in the firewall (off by default since nginx fronts the service):

```nix
services.atuin.openFirewall = true;
```

## Migration from the Docker module

| Old (`docker-atuin.nix`) | New (`service-atuin.nix`) |
|--------------------------|---------------------------|
| `forward_port` (string) | `port` (port, int) |
| `database_host` + hardcoded `atuin:atuin` credentials in the URI | `create_postgresql_database` (local) **or** `environment_file` (external, secret) |
| `version` (container image tag) | `package` (from nixpkgs) |
| `ATUIN_OPEN_REGISTRATION = "true"` (hardcoded, open) | `open_registration` (default `false`) |
| Container bound to `0.0.0.0:<port>` | Server bound to `127.0.0.1` |

## Troubleshooting

### Service Status

```bash
systemctl status atuin.service
journalctl -u atuin.service -f
```

### Common Issues

- **`Postgresql must be enabled to create a local database`**: This assertion comes from the upstream module; it is satisfied automatically when `create_postgresql_database = true`.
- **Missing `environment_file`**: When `create_postgresql_database = false`, the wrapper asserts that `environment_file` is set (it must define `ATUIN_DB_URI`).
- **Database connection failures (external)**: Verify the agenix secret is decrypted, the `environment_file` path is correct, and the `ATUIN_DB_URI` host/credentials are reachable from the server.
- **Registration rejected**: `open_registration` is `false` by default; set it to `true` to allow sign-ups.
