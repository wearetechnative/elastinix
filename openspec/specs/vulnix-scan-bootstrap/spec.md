# Capability: vulnix-scan-bootstrap

## Purpose

Bootstrap mechanism for the vulnix-scan service. Detects when the NVD (NIST National Vulnerability Database) ZODB cache is absent or empty and provisions a temporary swapfile to allow the initial database build to complete on memory-constrained hosts (e.g., t3.small). After bootstrap, the swapfile is removed and subsequent scans use the persistent incremental cache.

## Requirements

### Requirement: Bootstrap bij lege NVD cache
The service SHALL detect whether the NVD cache is empty and, if so, create a temporary swapfile to enable initial database construction.

#### Scenario: Bootstrap gedetecteerd
- **WHEN** `/var/lib/vulnix-cache/Data.fs` does not exist or is smaller than 1MB
- **THEN** the service SHALL activate bootstrap mode

#### Scenario: Disk-check vóór bootstrap
- **WHEN** bootstrap mode is activated
- **THEN** the service SHALL verify that at least 2GB of free space is available on the filesystem of `/var/lib/vulnix-cache`
- **THEN** if insufficient space is available, the service SHALL log a warning and skip the scan without failing

#### Scenario: Swapfile aangemaakt en geactiveerd
- **WHEN** bootstrap mode is active and sufficient disk space is available
- **THEN** a swapfile of 1.5GB SHALL be created at `/var/lib/vulnix-cache/swap`
- **THEN** the swapfile SHALL be activated via `mkswap` and `swapon`

#### Scenario: Swapfile verwijderd na bootstrap
- **WHEN** the NVD cache has been built successfully
- **THEN** the swapfile SHALL be deactivated via `swapoff` and removed via `rm`

#### Scenario: Swapfile opgeruimd bij crash
- **WHEN** the service stops (including on failure) and the swapfile exists
- **THEN** `ExecStopPost` SHALL deactivate and remove the swapfile

### Requirement: Persistente NVD cache op /var/lib/vulnix-cache/
The NVD ZODB cache SHALL be stored in `/var/lib/vulnix-cache/` so that weekly scans update incrementally.

#### Scenario: Cache directory aangemaakt
- **WHEN** the service is enabled
- **THEN** `/var/lib/vulnix-cache` SHALL exist with permissions 0755 owned by root

#### Scenario: Cache overleeft reboot
- **WHEN** the host reboots
- **THEN** `/var/lib/vulnix-cache/Data.fs` SHALL remain present and be reused

#### Scenario: Incrementele update na bootstrap
- **WHEN** the cache is populated (Data.fs > 1MB) and the last NVD update was less than 7 days ago
- **THEN** vulnix SHALL only download the `modified` NVD feed
