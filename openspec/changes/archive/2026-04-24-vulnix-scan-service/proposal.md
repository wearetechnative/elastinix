## Why

NixOS hosts running in production have no visibility into known vulnerabilities (CVEs) affecting their installed packages. Vulnix can scan a NixOS system closure and report which derivations have known CVEs, but there is no automated scanning in place. A weekly scan provides ongoing vulnerability awareness without requiring manual intervention.

## What Changes

- Add a new `elastinix.services.vulnix-scan` NixOS module that runs vulnix on a weekly timer
- The service generates a `packages.json` manifest from store paths in `/run/current-system` and feeds it to vulnix via `--from-file`, avoiding the need for `.drv` files on the target
- Vulnerability findings are written as raw JSON to `/var/lib/sbom/system.json` and logged to the systemd journal
- The service always exits successfully (vulnix exit code 2 = vulnerabilities found is not a failure)
- **BREAKING**: Replaces the existing `service-vulnix-scan.nix` which was a broken terraform wrapper approach

## Capabilities

### New Capabilities
- `vulnix-scan`: Weekly timer-based vulnerability scanning of the running NixOS system closure, writing SBOM output to disk and logging results to the journal

### Modified Capabilities

## Impact

- **New file**: `modules/nixos/services/service-vulnix-scan.nix` (replaces broken existing file)
- **New dependency**: `pkgs.vulnix` (available in nixpkgs, no flake input needed)
- **New directory on target hosts**: `/var/lib/sbom/` created via systemd tmpfiles
- **No deploy script changes required**: Works with existing `nix-copy-closure` workflow
- **Documentation**: `docs/services/vulnix-scan.md`
- **Docs index**: `docs/README.md` updated with link
