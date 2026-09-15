## Why

The elastinix `elastinix.services.grafana-prometheus` wrapper
(`modules/nixos/services/service-grafana.nix`) exposes the monitoring stack but
not its new authentication surface. The `wearetechnative/monitoring` module now
supports putting Prometheus and Alertmanager behind an OIDC identity provider
(AWS Cognito) via oauth2-proxy. Elastinix deployments need to configure this
through the wrapper.

Bean: `elastinix-wx2c` (epic `prometheus-alertmanager-cognito-auth`).

## What Changes

- New `elastinix.services.grafana-prometheus.oauth2Proxy` submodule (`enable`,
  `oidcIssuerUrl`, `clientId`, `clientSecretFile`, `cookieSecretFile`,
  `allowedGroups`, `groupsClaim`) passed through to the monitoring module's
  `services.grafana-prometheus.oauth2Proxy`.
- Documentation of the option surface, the required Cognito app client and
  callback URLs (`https://{prometheus,alertmanager}.<domain>/oauth2/callback`),
  and the two secret files, plus SSO / group-based authorization behaviour.
- The underlying core work (oauth2-proxy service, nginx auth_request, localhost
  binding, firewall) is delivered by the monitoring epic
  `monitoring-pkc2` and consumed via the `grafana-prometheus` flake input.

## Capabilities

### New Capabilities

- `grafana-prometheus-service`: the elastinix wrapper for the monitoring stack,
  including an `oauth2Proxy` option group that enables OIDC/Cognito
  authentication for Prometheus and Alertmanager.

## Impact

- **elastinix**: `modules/nixos/services/service-grafana.nix` (new options +
  pass-through), documentation (`docs/services/`), `docs/README.md` index.
- **Release note**: bump the `grafana-prometheus` flake input
  (`flake.lock`) to a revision of `wearetechnative/monitoring` that contains the
  `oauth2Proxy` option surface once that branch is merged. Until then the option
  only evaluates against an overridden input.
- Backwards compatible: `oauth2Proxy.enable` defaults to `false`.
