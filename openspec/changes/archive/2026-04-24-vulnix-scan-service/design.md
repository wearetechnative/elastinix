## Context

NixOS hosts have no automated vulnerability scanning. The existing `service-vulnix-scan.nix` attempted a terraform wrapper approach (running vulnix on the build machine and uploading results via SSH), but it was structurally broken — wrong Nix syntax and wrong architecture.

The target hosts are deployed via `nix-copy-closure` which only copies runtime outputs, not `.drv` files. Vulnix's default scan modes (`--system`, `--requisites`) require `.drv` files to map store paths to package names, making them unusable on these deployed hosts.

Vulnix supports an alternative input mode: `--from-file packages.json` which accepts a JSON manifest with pre-computed package names. This bypasses the need for `.drv` files entirely.

## Goals / Non-Goals

**Goals:**
- Provide weekly automated vulnerability scanning on NixOS hosts
- Work with the existing deploy workflow (no deploy script changes)
- Write raw vulnix JSON output to a well-known path for manual inspection
- Log scan results to the systemd journal
- Follow existing elastinix service conventions
- Always exit successfully regardless of vulnerability findings

**Non-Goals:**
- Email or external notifications (future work)
- Activation-triggered scanning (only timer-based for now)
- SBOM metadata wrapping (raw vulnix JSON only)
- Multi-instance support (single scan per host is sufficient)
- Alerting integration
- Patch-aware scanning (see trade-offs)

## Decisions

### 1. Use `vulnix --from-file packages.json` instead of `--system` or `--requisites`

Vulnix's `--system` and `--requisites` modes call `nix show-derivation` on each store path, which requires `.drv` files. These files are not present on target hosts because `nix-copy-closure` only transfers runtime outputs, and `nix-collect-garbage` removes anything extra.

Instead, the service generates a `packages.json` at scan time by parsing store path names from `nix-store -qR /run/current-system`. The store path format `/nix/store/<hash>-<name>-<version>` contains the same derivation name that vulnix would extract from `.drv` files. Vulnix's `load_pkgs_json` accepts this directly.

**Alternatives considered:**
- `--system` / `--requisites`: Rejected because `.drv` files unavailable on target
- `keep-derivations = true`: Only prevents GC of `.drv` files already present; doesn't help when they were never copied
- Changing deploy script to copy `.drv` files: Rejected to avoid coupling vulnix-scan to deployment tooling
- Build-time SBOM generation in system closure: Rejected due to circular dependency (`config.system.build.toplevel` cannot reference itself)

### 2. Generate packages.json on the target at scan time

Rather than baking the package list into the system closure at build time (which has circular dependency issues), generate it fresh on the target each scan. This is simple and has no build-time cost.

### 3. Single-instance service (no `instances` attrset)

Each host has exactly one `/run/current-system`. A simple `enable` toggle is sufficient.

### 4. Run as root

Needs read access to the Nix store to query requisites. Matches the elastinix default.

### 5. Systemd oneshot service + weekly timer

Follows the jirasync pattern: `Type=oneshot` service triggered by a timer with `OnCalendar=weekly` and `Persistent=true`.

### 6. Output to `/var/lib/sbom/system.json`

Standard systemd state directory path. Created via `systemd.tmpfiles.rules`.

### 7. Handle vulnix exit codes

Vulnix returns exit code 2 when vulnerabilities are found. The wrapper script catches this and exits 0.

### 8. Systemd security hardening

Standard elastinix hardening with `ReadWritePaths=/var/lib/sbom`.

## Risks / Trade-offs

- **[No patch awareness]** The generated `packages.json` does not include patch information. Vulnix normally uses patches from `.drv` files to suppress CVEs that are already fixed. Without this, some false positives may appear. Mitigation: use vulnix whitelists to suppress known false positives.
- **[Store path name parsing]** Some store paths may not follow the standard `name-version` format (e.g., `source`, `builder.sh`). These won't match any CVEs, so they're harmless noise. Vulnix's regex silently skips entries it can't parse.
- **[Package list fixed at deploy time]** The scan covers the system closure at deploy time. Manual `nix-env` installs won't be included. Mitigation: for terraform-managed servers, the system IS the closure — no manual installs expected.
