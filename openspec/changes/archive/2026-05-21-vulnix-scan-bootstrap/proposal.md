## Why

De huidige `service-vulnix-scan.nix` werkt niet op kleine EC2 instances (t3.small, 1.9GB RAM, geen swap): de initiële opbouw van de NVD ZODB-cache verbruikt ~1GB RAM en wordt door de OOM killer afgebroken. Daarnaast genereert de service zijn eigen packages.json via `nix-store -qR`, terwijl de deploy-wrapper (workloads repo) die al aanlevert bij elke deployment.

## What Changes

- **`service-vulnix-scan.nix`**: bootstrap-mechanisme toegevoegd — bij lege cache (Data.fs < 1MB) wordt tijdelijk een 1.5GB swapfile aangemaakt, de NVD database opgebouwd (~2 min), en de swapfile daarna verwijderd. Disk-check vooraf: minimaal 2GB vrij vereist op het filesystem.
- **`service-vulnix-scan.nix`**: `generatePackagesJson` stap verwijderd — de service leest voortaan `/var/lib/sbom/packages.json` dat door de deploy-wrapper bij elke deployment wordt geüpload. Geen `nix-store -qR` meer nodig.
- **`service-vulnix-scan.nix`**: cache verplaatst van `/var/lib/sbom/cache` naar `/var/lib/vulnix-cache` voor scheiding van verantwoordelijkheden.
- **`ExecStopPost`** toegevoegd om swapfile op te ruimen bij een onverwacht afbreken.

## Capabilities

### New Capabilities

- `vulnix-scan-bootstrap`: Bootstrap-mechanisme voor initiële NVD cache-opbouw op memory-constrained hosts.

### Modified Capabilities

- `vulnix-scan`: packages.json wordt niet meer door de service zelf gegenereerd maar door de deploy-wrapper aangeleverd; cache-locatie gewijzigd; bootstrap-logica toegevoegd.

## Impact

- `modules/nixos/services/service-vulnix-scan.nix`: alle wijzigingen in dit bestand
- Vereist dat de deploy-wrapper (workloads repo) `/var/lib/sbom/packages.json` aanlevert vóór de eerste scan
- Geen breaking change voor hosts waar de service al actief is — swapfile-logica wordt alleen getriggerd bij lege cache
