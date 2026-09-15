## 1. Wrapper option surface (elastinix-p2ku)

- [x] 1.1 Add an `oauth2Proxy` option group to `elastinix.services.grafana-prometheus` in `modules/nixos/services/service-grafana.nix`: `enable`, `oidcIssuerUrl`, `clientId`, `clientSecretFile`, `cookieSecretFile`, `allowedGroups`, `groupsClaim`
- [x] 1.2 Pass the options through to `services.grafana-prometheus.oauth2Proxy` in the wrapper `config` block

## 2. Documentation (elastinix-cli9)

- [x] 2.1 Create `docs/services/grafana-prometheus.md` documenting the stack wrapper and the `oauth2Proxy` option surface, required Cognito app client + callback URLs, the two secret files, and SSO / group-based authorization
- [x] 2.2 Add a `grafana-prometheus` entry to `docs/README.md` services index

## 3. Verification

- [x] 3.1 Evaluate a throwaway NixOS system that imports the elastinix wrapper (with the `grafana-prometheus` input overridden to the local monitoring worktree) and enables `oauth2Proxy`; assert the options reach `services.grafana-prometheus.oauth2Proxy` and produce the oauth2-proxy unit
- [x] 3.2 Assert the wrapper still evaluates with `oauth2Proxy.enable = false`
- [x] 3.3 `openspec validate --strict`
