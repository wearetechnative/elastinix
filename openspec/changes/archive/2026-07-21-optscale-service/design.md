<!-- Epic: .beans/elastinix-0r1b--optscale-finops-appliance-service.md -->

## Context

`optscale-nixified` exposes `nixosModules.optscale-appliance` (self-contained: imports substrate + configurator + secrets + all services + ngui, and wires `optscaleSrc`/`optscaleNgui`/`optscaleVenvs` from its own packages for `pkgs.system`) and a master `services.optscale.enable`. Its substrate-pins overlay and `allowUnfree`(mongodb)/`allowInsecure`(minio) config live in that flake's `pkgsFor` and are exposed as `overlays.default`; they cannot live in the modules (the VM-test framework makes a node's `nixpkgs.config` read-only). elastinix assembles systems in `lib/os_config_{live,vm,bootstrap}.nix`, auto-imports `modules/nixos/services/*` via `import-tree`, fronts web UIs with `services.nginx.virtualHosts."<sub>.${tfvars.environment_domain}"`, and manages secrets with agenix. Services follow `elastinix.services.<name>` + `enable`.

## Goals / Non-Goals

**Goals:**
- Run the full OptScale appliance on one EC2 instance via `elastinix.services.optscale.enable`.
- Secrets from agenix (one shared EnvironmentFile) → `services.optscale.secrets.environmentFile`.
- Substrate pinned to OptScale's tested versions + datastores permitted, without affecting non-OptScale machines.
- TLS-fronted UI, consistent with other elastinix services.

**Non-Goals:**
- Multi-tenant / multi-instance on one box; external managed datastores.
- Changing optscale-nixified (its appliance module + overlay are the prerequisite, already shipped).
- OptScale's internal `public_ip` rewrite for the external domain (UI is served locally and the BFF proxies the backend; revisit if cross-origin redirects surface).

## Decisions

### Decision 1: Import the appliance module in os_config, gate via the service file
Add `inputs.optscale.nixosModules.optscale-appliance` to `os_config_live.nix` and `os_config_vm.nix` (where the other external nixosModules live). `service-optscale.nix` (auto-imported) defines `elastinix.services.optscale` and, under `mkIf enable`, sets `services.optscale.enable = true`. Importing the module unconditionally only defines options + lazy `_module.args` (no runtime effect until enabled), matching how agenix/slack2zammad are always imported.

- **Alternative — import in the service file's `imports`**: elastinix's convention puts external flake modules in os_config; `inputs` there is a plain variable (not a fixpoint module arg), avoiding import-time arg subtleties.

### Decision 2: Apply the overlay + allowances in the service, gated by enable
`config = mkIf cfg.enable { nixpkgs.overlays = [ inputs.optscale.overlays.default ]; nixpkgs.config.allowUnfreePredicate = …mongodb…; nixpkgs.config.allowInsecurePredicate = …minio…; }`. The overlay only alters `clickhouse`/`rabbitmq-server`, which only OptScale uses on a dedicated box, so scoping by `enable` keeps other machines untouched. The live path sets no other `allowUnfree*`/`allowInsecure*`, so there is no predicate-merge conflict.

### Decision 3: Secrets — one agenix file, machine-declared, root+minio readable
`secretsFile` is a path option (default example `config.age.secrets.optscale.path`); the machine declares the per-environment `age.secrets.optscale` from its `.age`. The file is read by the configurator (root) AND minio (minio user), so it must be `owner=root; group=minio; mode=0440` (hardcoded group, per elastinix's circular-dependency guidance). It must carry a valid `Fernet.generate_key()` `ENCRYPTION_KEY`.

### Decision 4: nginx TLS front for the UI on :4000
`services.nginx.virtualHosts."${cfg.subdomain}.${environment_domain}"` with `enableACME`/`forceSSL`, `locations."/" = { proxyPass = "http://127.0.0.1:4000"; proxyWebsockets = true; }`. Mirrors service-hedgedoc/umami. Backend services stay on localhost (the BFF proxies them); only :4000 is fronted.

## Risks / Trade-offs

- **Heavy closure** (uv2nix venvs + pnpm ngui + datastore binaries) → cached after first build; aarch64 supported. Not a per-deploy cost.
- **Overlay changes machine-global clickhouse/rabbitmq** → gated by `enable`; a dedicated appliance box is unaffected in practice.
- **agenix ownership** → documented `owner=root/group=minio/mode=0440`; wrong ownership makes minio fail to read its root credentials.
- **Full end-to-end verification needs AWS/terraform** → this change is verified by evaluation (the system config builds/evaluates with the service enabled); a live smoke is a deploy-time step.

## Migration Plan

1. Add the flake input; `nix flake lock`.
2. Import the appliance module in os_config_live + os_config_vm.
3. Add `service-optscale.nix`.
4. Evaluate a system with `elastinix.services.optscale.enable = true` (+ a dummy secretsFile) to confirm it builds/evaluates on x86_64 and aarch64.
5. Docs + index.

Rollback: remove the service file, the two imports, and the input.

## Open Questions

- Should the service also set OptScale's `public_ip`/domain in etcd for correct absolute URLs behind the domain, or is localhost + BFF proxy sufficient? (Defer until a real deploy shows a need.)
- Add a `nixos-healthchecks` HTTP check on the UI now, or in a follow-up? (Leaning: a simple check on the vhost.)
