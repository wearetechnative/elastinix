## Context

Two ad-hoc NixOS lib files in `technative-awsaccounts-workloads` currently handle host inventory:
- `lib/elastinix-inventory.nix`: generates a static `services.json` at build time and runs a Python HTTP server on port 3333
- `lib/elastinix-sbom.nix`: creates a symlink from `/var/lib/sbom/system.json` into the inventory directory

These are consumed only by `stack/ec2_compute2`. Making them an elastinix service makes the pattern reusable across all elastinix deployments.

## Goals / Non-Goals

**Goals:**
- Provide a reusable `elastinix.services.hostinfo` module
- Generate `services.json` at runtime (daily) with a real `buildTime` timestamp, keeping the Nix build pure
- Serve all files in `/var/lib/hostinfo/` via Python `http.server`
- Support optional SBOM exposure via `enableSbom` flag
- Follow the vulnix-scan pattern: systemd timer + oneshot service

**Non-Goals:**
- Nginx vhost (tracked in bean `elastinix-n3zn`)
- Renaming `buildTime` to `lastUpdated` (tracked in bean `elastinix-vtja`, requires lambda update)
- Authentication or access control on the HTTP endpoint
- Multi-instance support (one hostinfo server per host is sufficient)

## Decisions

### Static template in Nix store, timestamp at runtime

**Decision**: Write a JSON template (without `buildTime`) to the Nix store as a `pkgs.writeText` derivation. A daily systemd oneshot service reads the template, injects `buildTime` via `date`, and writes the result to `/var/lib/hostinfo/services.json`.

**Why**: `builtins.currentTime` makes the build impure, breaking Nix caching. Runtime injection keeps the build pure while still providing a meaningful timestamp.

**Alternative considered**: `builtins.currentTime` — rejected due to cache invalidation on every rebuild.

### Python `http.server` over nginx static file serving

**Decision**: Use `${pkgs.python3}/bin/python -m http.server` to serve `/var/lib/hostinfo/`.

**Why**: Zero configuration, no external dependency, already available via nixpkgs. The directory model means new JSON sources (fastfetch, etc.) are exposed automatically without any server reconfiguration.

**Alternative considered**: nginx `root` directive — requires nginx to be enabled, tightly coupling hostinfo to the nginx service.

### `enableSbom` as opt-in flag

**Decision**: SBOM symlink is disabled by default (`enableSbom = false`). When enabled, creates `L+ /var/lib/hostinfo/sbom.json → /var/lib/sbom/system.json`.

**Why**: Not all hosts run vulnix-scan. Opt-in prevents a broken symlink on hosts without SBOM data.

### Port 3333, configurable

**Decision**: Default port `3333`, exposed as `port` option. Firewall opened automatically.

**Why**: Consistent with existing compute2 setup. Configurability avoids port conflicts on multi-service hosts.

## Risks / Trade-offs

- **Broken symlink for sbom.json** → Mitigation: `enableSbom` defaults to `false`; document that `elastinix.services.vulnix-scan` should be enabled alongside
- **`services.json` absent on first boot** → Mitigation: timer uses `Persistent = true` so it runs at boot if the daily run was missed; also add `wantedBy = multi-user.target` on the oneshot so it runs on first activation
- **Public HTTP endpoint** → Mitigation: only system metadata is exposed (no secrets); nginx vhost with auth can be added later (bean `elastinix-n3zn`)
- **`buildTime` field name** → Mitigation: kept as-is for lambda compatibility; tracked in bean `elastinix-vtja`

## Migration Plan

1. Implement `service-hostinfo.nix` in elastinix
2. Release/tag elastinix
3. In `technative-awsaccounts-workloads`:
   - Remove `lib/elastinix-inventory.nix` and `lib/elastinix-sbom.nix`
   - Update `stack/ec2_compute2/nix/hostconf.nix`: remove the two imports, add `elastinix.services.hostinfo = { enable = true; enableSbom = true; };`
   - Update elastinix flake input to new version
4. Deploy compute2

**Rollback**: revert hostconf.nix imports — the old lib files can be restored from git.

## Open Questions

- Should the daily timer also run on NixOS activation (not just boot)? Currently `Persistent = true` handles missed runs but not mid-day redeploys. Low priority since the data is static between deploys.
