# Vulnix Scan (Removed)

> **This service has been removed.** The local `elastinix.services.vulnix-scan` module no longer exists.
>
> Use **[Vulnerability Scan Central](vulnerability-scan-central.md)** instead — a central scanner that fetches `packages.json` from multiple hosts via hostinfo and runs vulnix (and trivy) centrally.

## Migration

Replace local scanning with central scanning:

1. On each compute host, enable `hostinfo.enablePackages`:
   ```nix
   elastinix.services.hostinfo = {
     enable = true;
     enablePackages = true;
   };
   ```

2. On the central scanner host, configure `vulnerability-scan-central`:
   ```nix
   elastinix.services.vulnerability-scan-central = {
     enable = true;
     hosts = [
       { name = "compute1-prod"; url = "http://10.0.1.10:3333"; enableDockerScan = false; }
     ];
   };
   ```

See [vulnerability-scan-central.md](vulnerability-scan-central.md) for full documentation.
