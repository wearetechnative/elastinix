## 1. Flake input

- [x] 1.1 Add `optscale.url = "github:wearetechnative/optscale-nixified"` + `optscale.inputs.nixpkgs.follows = "nixpkgs"` to `flake.nix`.
- [x] 1.2 `nix flake lock` and confirm the input resolves (has `nixosModules.optscale-appliance` + `overlays.default`).

## 2. Wire the appliance module into the system assemblies

- [x] 2.1 Add `inputs.optscale.nixosModules.optscale-appliance` to the module list in `lib/os_config_live.nix` (with the other external nixosModules).
- [x] 2.2 Same in `lib/os_config_vm.nix`.

## 3. The service module

- [x] 3.1 Create `modules/nixos/services/service-optscale.nix`: options `elastinix.services.optscale.{enable, subdomain (default "optscale"), secretsFile}`.
- [x] 3.2 `config = mkIf enable`: `services.optscale.enable = true`; `services.optscale.secrets.environmentFile = cfg.secretsFile`.
- [x] 3.3 Apply `nixpkgs.overlays = [ inputs.optscale.overlays.default ]` + `nixpkgs.config.allowUnfreePredicate`(mongodb) + `allowInsecurePredicate`(minio), gated by enable.
- [x] 3.4 nginx virtualHost `${subdomain}.${environment_domain}` (enableACME, forceSSL) → `proxyPass http://127.0.0.1:4000` (proxyWebsockets).
- [x] 3.5 Document in the `secretsFile` option description: the required env-var set, `owner=root/group=minio/mode=0440`, and a valid Fernet `ENCRYPTION_KEY`.

## 4. Acceptance (evaluation-level; live smoke is a deploy step)

- [x] 4.1 `nix flake check`/eval: the flake evaluates with the new input.
- [x] 4.2 Evaluate a system with `elastinix.services.optscale.enable = true` + a dummy `secretsFile` and confirm `.config.system.build.toplevel.drvPath` resolves on x86_64 and aarch64 (the appliance + overlay + nginx wire up).
- [x] 4.3 Confirm a machine WITHOUT the service enabled is unaffected (no OptScale units, overlay not applied).

## 5. Docs

- [x] 5.1 Add `docs/services/optscale.md` (enable, agenix secret contract + ownership + Fernet, domain, one-instance scope) and link it in `docs/README.md`.
