---
# elastinix-wx2c
title: prometheus-alertmanager-cognito-auth
status: completed
type: epic
priority: high
created_at: 2026-09-04T09:07:58Z
updated_at: 2026-09-04T10:30:00Z
openspec-link: openspec/changes/archive/2026-09-04-grafana-prometheus-cognito-auth
---

Put Prometheus and Alertmanager behind Cognito SSO in the `grafana-prometheus`
monitoring stack, reusing the same OIDC identity provider that already fronts
Grafana. Today the module publishes `prometheus.<domain>` and
`alertmanager.<domain>` nginx vhosts with **no authentication**, and
`prometheus.nix` opens raw ports `9090 9100 9115 9109` on the host firewall —
every scrape target is `localhost`, so those ports serve no function and are
pure attack surface.

## Goal

Add an `oauth2-proxy` service to the stack that authenticates against an OIDC
provider (AWS Cognito), and protect the Prometheus and Alertmanager vhosts via
nginx `auth_request`. Authorization is group-gated (e.g. `grafana-admin`), so
TechNative and customer administrators reuse the groups they already have.
Bind Prometheus, its exporters and Alertmanager to `127.0.0.1` so the public
raw ports become inert, and drop them from the firewall.

## Design decisions (from exploration)

- **Reverse-proxy auth, not native.** Prometheus/Alertmanager have no OIDC
  login; only HTTP basic auth. `oauth2-proxy` + nginx `auth_request` is the way
  to reuse Cognito and get SSO consistent with Grafana.
- **Same user pool + groups, separate app client.** The consuming stack creates
  a dedicated Cognito app client; the module only needs issuer URL, client id,
  client-secret path, cookie-secret path, and an allowed-groups list.
- **Single oauth2-proxy for both subdomains** via `--cookie-domain=.<domain>`
  gives SSO across prometheus + alertmanager (and the Grafana session).
- **Localhost binding neutralizes the open ports** even before the firewall is
  tightened — nothing external ever talks to the exporters.

## Scope note

The core work (vhosts, firewall, exporter bind addresses) lives in the
`wearetechnative/monitoring` module wrapped by elastinix
`service-grafana.nix`. The core module work (oauth2-proxy service, nginx auth_request,
localhost binding, firewall) lives in the `wearetechnative/monitoring` epic
`monitoring-pkc2`. THIS epic covers only the elastinix wrapper: exposing the
oauth2-proxy option surface through `elastinix.services.grafana-prometheus`
(service-grafana.nix) and elastinix-side docs.

Consumed by the IIT monitoring host (separate epic in
`improvement_it-iit_servers`).
