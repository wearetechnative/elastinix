## ADDED Requirements

### Requirement: Bootstrap bij lege NVD cache
De service SHALL detecteren of de NVD cache leeg is en indien zo een tijdelijke swapfile aanmaken om de initiële database-opbouw mogelijk te maken.

#### Scenario: Bootstrap gedetecteerd
- **WHEN** `/var/lib/vulnix-cache/Data.fs` niet bestaat of kleiner is dan 1MB
- **THEN** SHALL de service bootstrap-modus activeren

#### Scenario: Disk-check vóór bootstrap
- **WHEN** bootstrap-modus geactiveerd wordt
- **THEN** SHALL de service controleren of minimaal 2GB vrij is op het filesystem van `/var/lib/vulnix-cache`
- **THEN** SHALL de service bij onvoldoende ruimte een waarschuwing loggen en de scan overslaan zonder te falen

#### Scenario: Swapfile aangemaakt en geactiveerd
- **WHEN** bootstrap-modus actief is en voldoende disk beschikbaar
- **THEN** SHALL een swapfile van 1.5GB aangemaakt worden op `/var/lib/vulnix-cache/swap`
- **THEN** SHALL de swapfile geactiveerd worden via `mkswap` en `swapon`

#### Scenario: Swapfile verwijderd na bootstrap
- **WHEN** de NVD cache succesvol opgebouwd is
- **THEN** SHALL de swapfile gedeactiveerd worden via `swapoff` en verwijderd worden via `rm`

#### Scenario: Swapfile opgeruimd bij crash
- **WHEN** de service stopt (ook bij failure) en de swapfile bestaat
- **THEN** SHALL `ExecStopPost` de swapfile deactiveren en verwijderen

### Requirement: Persistente NVD cache op /var/lib/vulnix-cache/
De NVD ZODB-cache SHALL opgeslagen worden in `/var/lib/vulnix-cache/` zodat wekelijkse scans incrementeel updaten.

#### Scenario: Cache directory aangemaakt
- **WHEN** de service enabled is
- **THEN** SHALL `/var/lib/vulnix-cache` bestaan met permissions 0755 owned by root

#### Scenario: Cache overleeft reboot
- **WHEN** de host herstart
- **THEN** SHALL `/var/lib/vulnix-cache/Data.fs` aanwezig blijven en hergebruikt worden

#### Scenario: Incrementele update na bootstrap
- **WHEN** de cache gevuld is (Data.fs > 1MB) en de laatste NVD update minder dan 7 dagen geleden is
- **THEN** SHALL vulnix alleen de `modified` NVD feed downloaden
