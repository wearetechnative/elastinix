# hostinfo-docker-images Specification

## Purpose
TBD - created by archiving change vulnerability-scanning-central. Update Purpose after archive.
## Requirements
### Requirement: enableDockerImages option

The module SHALL expose `elastinix.services.hostinfo.enableDockerImages` as a boolean option with default `false`. When `true`, the module SHALL create a `elastinix-docker-inventory` oneshot service, a daily timer, and a symlink `/var/lib/hostinfo/docker-images.json` → `/var/lib/docker-inventory/images.json`.

#### Scenario: Disabled by default

- **WHEN** `enableDockerImages` is not set
- **THEN** no docker-inventory systemd units are created and no `docker-images.json` symlink exists in `/var/lib/hostinfo/`

#### Scenario: Enabled

- **WHEN** `enableDockerImages = true`
- **THEN** `elastinix-docker-inventory.service`, `elastinix-docker-inventory.timer`, and the `/var/lib/docker-inventory` directory are created, and `/var/lib/hostinfo/docker-images.json` symlinks to `/var/lib/docker-inventory/images.json`

### Requirement: Docker image inventory generation

The `elastinix-docker-inventory` oneshot service SHALL query the Docker socket API (`/images/json`) and write a JSON array to `/var/lib/docker-inventory/images.json`.

#### Scenario: Inventory generated

- **WHEN** the service runs
- **THEN** `/var/lib/docker-inventory/images.json` contains a JSON array of installed images with fields `image` and `tag`

#### Scenario: Output format

- **WHEN** images `twentyhq/twenty-server:v0.32.0` and `gotenberg/gotenberg:8.2` are installed
- **THEN** the file contains entries with `{"image": "twentyhq/twenty-server", "tag": "v0.32.0"}` for each; images tagged `<none>:<none>` are excluded and duplicates are removed

#### Scenario: No images installed

- **WHEN** no Docker images with repository tags are installed
- **THEN** the service writes an empty JSON array `[]` and exits successfully

### Requirement: Daily timer

The module SHALL create a systemd timer `elastinix-docker-inventory.timer` with `OnCalendar=daily` and `Persistent=true`.

#### Scenario: Timer fires daily

- **WHEN** a day has elapsed since the last run
- **THEN** `elastinix-docker-inventory.service` is triggered

### Requirement: Docker socket access

The `elastinix-docker-inventory` service SHALL have access to `/var/run/docker.sock`. The service user SHALL be a member of the `docker` group.

#### Scenario: Service reads Docker socket

- **WHEN** the service runs
- **THEN** it can query `/var/run/docker.sock` to list installed images

### Requirement: Storage directory

The module SHALL create `/var/lib/docker-inventory` via `systemd.tmpfiles.rules`.

#### Scenario: Directory exists on boot

- **WHEN** `enableDockerImages = true`
- **THEN** `/var/lib/docker-inventory` exists before the service starts

