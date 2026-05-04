# Vulnix Scan

Weekly automated vulnerability scanning for NixOS systems using [vulnix](https://github.com/nix-community/vulnix). Scans the running system closure (`/run/current-system`) for packages with known CVEs and writes the results to disk.

## Features

- Scans the full NixOS system closure including all dependencies
- Runs weekly via systemd timer (catches newly disclosed CVEs between deploys)
- Writes raw JSON vulnerability report to `/var/lib/sbom/system.json`
- Logs results to the systemd journal
- Runs with systemd security hardening
- Works with `nix-copy-closure` deployments (no `.drv` files required on target)

## How It Works

Vulnix normally needs `.drv` files to identify packages, but these are not available on hosts deployed via `nix-copy-closure`. Instead, this service:

1. Generates a `packages.json` manifest by parsing store path names from the system closure
2. Feeds this manifest to vulnix via `--from-file`, bypassing the need for `.drv` files
3. Vulnix queries the NIST NVD database for known CVEs matching the package names and versions

## Configuration

```nix
elastinix.services.vulnix-scan = {
  enable = true;
};
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable weekly vulnerability scanning |

## Usage

### Check scan results

View the latest vulnerability report:

```bash
cat /var/lib/sbom/system.json | jq .
```

View journal output from the last scan:

```bash
journalctl -u vulnix-scan --no-pager -l
```

### Trigger a scan manually

```bash
systemctl start vulnix-scan.service
```

### Check timer status

```bash
systemctl status vulnix-scan.timer
systemctl list-timers vulnix-scan.timer
```

## Troubleshooting

### Empty or missing SBOM file

If `/var/lib/sbom/system.json` does not exist or is empty, check the journal for errors:

```bash
journalctl -u vulnix-scan -e
```

### Scan takes a long time

Vulnix queries the NIST NVD database on each scan. Network latency or a large number of packages can slow things down. Check progress via the journal.

### False positives

Because the service cannot read `.drv` files on the target, it does not know which CVE-fixing patches have been applied. This may result in some false positives. Use vulnix whitelists to suppress known false positives.

### Service shows "failed" status

The service is designed to always exit successfully, even when vulnerabilities are found (vulnix exit code 2). If the service reports failure, check the journal for unexpected errors.
