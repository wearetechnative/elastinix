## Context

`service-hostinfo.nix` currently creates three things unconditionally when `enable = true`:
1. `systemd.tmpfiles.rules` — creates `/var/lib/hostinfo/` and optional symlinks
2. `elastinix-hostinfo-inventory` oneshot + timer — generates `services.json`
3. `elastinix-hostinfo-server` — Python HTTP server

The `enableVulnixReport` and `enableSbom` options already demonstrate the symlink pattern via `lib.optional` in `systemd.tmpfiles.rules`. The new options follow this established pattern exactly.

See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- Make inventory generation optional without breaking existing deployments
- Expose packages.json via the existing symlink pattern
- Zero new dependencies

**Non-Goals:**
- Generating `/var/lib/packages/packages.json` (external responsibility, created by Terraform)
- Changing the HTTP server implementation

## Decisions

### `enableInventory` defaults to `true`

Alternatives considered:
- `false` (explicit opt-in, consistent with other `enable*` options) — rejected because it would silently break existing deployments that rely on `services.json` being present

### `enablePackages` uses `lib.optional` in `systemd.tmpfiles.rules`

Same pattern as `enableVulnixReport`:
```nix
++ lib.optional cfg.enablePackages
  "L+ /var/lib/hostinfo/packages.json - - - - /var/lib/packages/packages.json"
```

The inventory systemd units are wrapped in `lib.mkIf cfg.enableInventory`:
```nix
systemd.services.elastinix-hostinfo-inventory = lib.mkIf cfg.enableInventory { ... };
systemd.timers.elastinix-hostinfo-inventory   = lib.mkIf cfg.enableInventory { ... };
```

## Risks / Trade-offs

- [Broken symlink] If `enablePackages = true` but Terraform has not yet uploaded the file → symlink exists but target is absent, HTTP returns 404. Acceptable — Python's http.server handles missing symlink targets gracefully with a 404.
- [enableInventory = false + no other files] The HTTP server starts but `/var/lib/hostinfo/` may be empty. Not harmful, just serves an empty directory listing.
