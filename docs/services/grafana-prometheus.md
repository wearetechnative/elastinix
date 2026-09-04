# Grafana / Prometheus Monitoring Stack

The `elastinix.services.grafana-prometheus` wrapper deploys the
[`wearetechnative/monitoring`](https://github.com/wearetechnative/monitoring)
module: Grafana, Prometheus, Alertmanager and a set of exporters (node,
blackbox, vulnix), published behind nginx on `grafana.<domain>`,
`prometheus.<domain>` and `alertmanager.<domain>`.

## Overview

By default the Grafana vhost carries Grafana's own OAuth, while the Prometheus
and Alertmanager vhosts are **unauthenticated**. The `oauth2Proxy` option group
puts Prometheus and Alertmanager behind an OIDC identity provider (AWS Cognito)
via nginx `auth_request`, giving single sign-on consistent with Grafana and
group-based authorization.

Prometheus, the exporters and Alertmanager bind to `127.0.0.1`; the raw metrics
ports (`9090 9100 9115 9109`) are not opened on the firewall. The only external
access path is the authenticated nginx vhost on port 443.

## Features

- Grafana + Prometheus + Alertmanager + exporters as one option surface.
- Per-customer probe files, alert rules and dashboards.
- Optional OIDC/Cognito authentication for Prometheus and Alertmanager with SSO
  across both subdomains and the Grafana session.
- Group-gated authorization via the OIDC groups claim.
- Metrics endpoints bound to localhost and dropped from the firewall.

## Configuration

### Basic

```nix
elastinix.services.grafana-prometheus = {
  enable = true;
  root_domain = "example.com";   # defaults to tfvars.environment_domain
  customers = [
    {
      name = "technative";
      probesFile = ./customers/technative/probes/urls.yaml;
      alertRules = [ ./customers/technative/alerts/alert-ssl_expiration.yml ];
      dashboardsPath = ./dashboards/technative;
    }
  ];
};
```

### Authentication (oauth2-proxy / Cognito)

```nix
elastinix.services.grafana-prometheus = {
  enable = true;
  root_domain = "example.com";

  oauth2Proxy = {
    enable = true;
    oidcIssuerUrl =
      "https://cognito-idp.eu-central-1.amazonaws.com/eu-central-1_abc123";
    clientId = "your-app-client-id";
    clientSecretFile = config.age.secrets.oauth2-proxy-client-secret.path;
    cookieSecretFile = config.age.secrets.oauth2-proxy-cookie-secret.path;
    groupsClaim = "cognito:groups";   # AWS Cognito groups claim
    allowedGroups = [ "grafana-admin" ];
  };
};
```

### `oauth2Proxy` options

| Option             | Type          | Default    | Description                                                         |
| ------------------ | ------------- | ---------- | ------------------------------------------------------------------- |
| `enable`           | bool          | `false`    | Protect Prometheus + Alertmanager with oauth2-proxy.                |
| `oidcIssuerUrl`    | str           | `""`       | OIDC issuer URL of the identity provider (Cognito user pool).       |
| `clientId`         | str           | `""`       | OIDC app client id.                                                 |
| `clientSecretFile` | path / null   | `null`     | File with the OIDC client secret (read via systemd credentials).    |
| `cookieSecretFile` | path / null   | `null`     | File with the cookie secret, 16/24/32 bytes.                        |
| `allowedGroups`    | list of str   | `[]`       | Groups allowed access. Empty = any authenticated pool member.       |
| `groupsClaim`      | str           | `"groups"` | OIDC claim carrying groups (`cognito:groups` for AWS Cognito).      |

## Cognito app client setup

Create a dedicated Cognito app client (reusing the existing user pool and groups
that already front Grafana) and register **both** callback URLs:

- `https://prometheus.<root_domain>/oauth2/callback`
- `https://alertmanager.<root_domain>/oauth2/callback`

A single oauth2-proxy instance serves both subdomains: the session cookie is
scoped to `.<root_domain>` and back-redirects are whitelisted across the domain,
so one login covers Prometheus, Alertmanager and the Grafana session.

Authorization is group-gated: only members of `allowedGroups` (matched against
the `groupsClaim`, e.g. `cognito:groups`) may access the vhosts. Leaving
`allowedGroups` empty allows any user authenticated by the pool.

## Secrets

Provide two agenix secrets. They are read at runtime through systemd
`LoadCredential`, so the files only need to be readable by root and are never
placed on the command line or in the Nix store.

```nix
age.secrets.oauth2-proxy-client-secret = {
  file = ./secrets/oauth2-proxy-client-secret.age;
  path = "/run/agenix/oauth2-proxy-client-secret";
};
age.secrets.oauth2-proxy-cookie-secret = {
  file = ./secrets/oauth2-proxy-cookie-secret.age;
  path = "/run/agenix/oauth2-proxy-cookie-secret";
};
```

Generate a cookie secret with:

```bash
openssl rand -base64 32 | head -c 32
```

## Usage

```bash
# oauth2-proxy status and logs
systemctl status oauth2-proxy.service
journalctl -u oauth2-proxy.service -f

# Confirm Prometheus/Alertmanager are localhost-only
ss -ltnp | grep -E '9090|9093|9100|9115|9109'
```

## Troubleshooting

- **Redirect loop / cookie not set** — check the cookie secret is a valid
  16/24/32 byte value and `root_domain` matches the served subdomains.
- **403 after login** — the user is authenticated but not in an
  `allowedGroups` group, or `groupsClaim` does not match the token (use
  `cognito:groups` for Cognito).
- **Callback mismatch** — both `.../oauth2/callback` URLs must be registered on
  the Cognito app client.

## Implementation Details

The wrapper (`modules/nixos/services/service-grafana.nix`) passes the
`oauth2Proxy` options straight through to the monitoring module's
`services.grafana-prometheus.oauth2Proxy`. The oauth2-proxy service, nginx
`auth_request` locations, localhost binding and firewall changes live in the
`wearetechnative/monitoring` module (flake input `grafana-prometheus`).

> **Note:** The `oauth2Proxy` option requires a `grafana-prometheus` flake-input
> revision that includes the `oauth2Proxy` option surface. Bump `flake.lock`
> (`nix flake update grafana-prometheus`) once that monitoring change is merged.
