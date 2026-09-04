## ADDED Requirements

### Requirement: oauth2-proxy option surface on the wrapper
The `elastinix.services.grafana-prometheus` wrapper SHALL expose an `oauth2Proxy`
option group with: `enable` (bool, default `false`), `oidcIssuerUrl` (str),
`clientId` (str), `clientSecretFile` (path), `cookieSecretFile` (path),
`allowedGroups` (list of str, default `[]`), and `groupsClaim` (str, default
`groups`).

#### Scenario: Options available on the wrapper
- **WHEN** the elastinix `service-grafana.nix` module is imported
- **THEN** `elastinix.services.grafana-prometheus.oauth2Proxy.enable` and the
  other listed options are defined and settable

### Requirement: Pass-through to the monitoring module
When `elastinix.services.grafana-prometheus.enable` is `true`, the wrapper SHALL
pass every `oauth2Proxy` value through to the monitoring module's
`services.grafana-prometheus.oauth2Proxy` unchanged.

#### Scenario: oauth2Proxy configuration forwarded
- **WHEN** `elastinix.services.grafana-prometheus.oauth2Proxy` is configured with
  `enable = true`, an issuer URL, client id, secret files and allowed groups
- **THEN** `services.grafana-prometheus.oauth2Proxy` receives the same values and
  the underlying oauth2-proxy service is configured

#### Scenario: Disabled by default
- **WHEN** `oauth2Proxy` is not configured
- **THEN** `oauth2Proxy.enable` is `false` and no oauth2-proxy authentication is
  applied, preserving the prior wrapper behaviour
