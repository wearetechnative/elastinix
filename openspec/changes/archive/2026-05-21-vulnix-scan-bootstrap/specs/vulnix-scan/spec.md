## MODIFIED Requirements

### Requirement: Scan packages with vulnix
De service SHALL `/var/lib/sbom/packages.json` lezen (aangeleverd door de deploy-wrapper) en scannen via `vulnix --from-file`. De service SHALL geen packages.json meer zelf genereren.

#### Scenario: packages.json aanwezig
- **WHEN** `/var/lib/sbom/packages.json` bestaat
- **THEN** SHALL de service `vulnix --json --from-file /var/lib/sbom/packages.json --no-requisites --cache-dir /var/lib/vulnix-cache` uitvoeren

#### Scenario: packages.json afwezig
- **WHEN** `/var/lib/sbom/packages.json` niet bestaat
- **THEN** SHALL de service een waarschuwing loggen en stoppen met exit code 0 (geen failure)

#### Scenario: Successful scan met kwetsbaarheden
- **WHEN** vulnix exit code 2 retourneert
- **THEN** SHALL de service exit code 0 rapporteren aan systemd

## REMOVED Requirements

### Requirement: Generate package manifest from store paths
**Reason**: packages.json wordt aangeleverd door de deploy-wrapper (workloads repo) bij elke deployment. De service hoeft dit niet meer zelf te genereren.
**Migration**: Zorg dat de deploy-wrapper `/var/lib/sbom/packages.json` uploadt naar de remote host vóór de eerste vulnix-scan timer trigger.

## MODIFIED Requirements

### Requirement: Systemd security hardening
De service SHALL `ReadWritePaths` uitbreiden met zowel `/var/lib/sbom` als `/var/lib/vulnix-cache`. De service schrijft `system.json` naar `/var/lib/sbom` en de NVD cache naar `/var/lib/vulnix-cache`.

#### Scenario: Hardened service schrijft naar vulnix-cache
- **WHEN** de service bootstrap uitvoert of de NVD cache bijwerkt
- **THEN** SHALL de service schrijftoegang hebben tot `/var/lib/vulnix-cache`

#### Scenario: Hardened service leest packages.json
- **WHEN** de service de scan start
- **THEN** SHALL de service leestoegang hebben tot `/var/lib/sbom/packages.json`
