# Vulnix Scan (Removed)

> **This service has been removed.** The local `elastinix.services.vulnix-scan` module no longer exists.
>
> Use **[Vulnix Scan Central](vulnix-scan-central.md)** instead — a central scanner that fetches `packages.json` from multiple hosts via hostinfo and runs vulnix centrally.

## Migration

Replace local scanning with central scanning:

1. On each compute host, enable `hostinfo.enablePackages`:
   ```nix
   elastinix.services.hostinfo = {
     enable = true;
     enablePackages = true;
   };
   ```

2. On the central scanner host, configure `vulnix-scan-central`:
   ```nix
   elastinix.services.vulnix-scan-central = {
     enable = true;
     hosts = [
       { name = "compute1-prod"; url = "http://10.0.1.10:3333"; }
     ];
   };
   ```

See [vulnix-scan-central.md](vulnix-scan-central.md) for full documentation.
