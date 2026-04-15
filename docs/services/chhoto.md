# Chhoto URL Shortener

The Chhoto service (`elastinix.services.chhoto`) wraps the NixOS `services.chhoto-url` module to provide a lightweight, self-hosted URL shortener with SQLite storage.

## Features

- **Lightweight**: Single binary with embedded SQLite database
- **Secret injection**: Password and API key via environment files (agenix compatible)
- **Security hardening**: Upstream systemd hardening (PrivateTmp, ProtectSystem, NoNewPrivileges)
- **Minimal configuration**: Only essential options exposed, sensible upstream defaults

## Configuration

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the chhoto-url service |
| `environmentFiles` | list of paths | `[]` | Environment files for secrets (password, API key) |
| `port` | port | — | Port for the chhoto-url server |
| `siteUrl` | null or string | `null` | External URL where chhoto-url is publicly accessible |

### Basic Example

```nix
elastinix.services.chhoto = {
  enable = true;
  port = 4567;
  siteUrl = "https://go.example.com";
  environmentFiles = [
    config.age.secrets.chhoto-env.path
  ];
};
```

### Secrets Setup with Agenix

Create an environment file with the password and/or API key:

```
CHHOTO_PASSWORD=your-secret-password
```

Encrypt it with agenix and reference it in `environmentFiles`:

```nix
age.secrets.chhoto-env = {
  file = ./secrets/chhoto-env.age;
  owner = "root";
  group = "root";
};

elastinix.services.chhoto = {
  enable = true;
  port = 4567;
  environmentFiles = [
    config.age.secrets.chhoto-env.path
  ];
};
```

## Advanced Configuration

For settings not exposed by the Elastinix wrapper (e.g., `slug_style`, `redirect_method`), use the upstream NixOS options directly alongside the Elastinix module:

```nix
services.chhoto-url.settings = {
  slug_style = "UID";
  redirect_method = "TEMPORARY";
};
```

## Troubleshooting

### Service Status

```bash
systemctl status chhoto-url.service
journalctl -u chhoto-url.service -f
```

### Common Issues

- **Port conflict**: Ensure the configured port is not used by another service
- **Missing secrets**: Verify agenix secrets are decrypted and the environment file path is correct
