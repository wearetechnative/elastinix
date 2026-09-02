# hostinfo-inuse-sampler Specification

## Purpose
TBD - created by archiving change in-use-code-sampling. Update Purpose after archive.

## Requirements

### Requirement: In-use sampler enable option

The hostinfo module SHALL expose `elastinix.services.hostinfo.enableInUseSampler` of type `lib.types.bool`, defaulting to `false`. When disabled, no sampler service, timer or tmpfiles entry SHALL be created.

A sampling interval SHALL be configurable via `elastinix.services.hostinfo.inUseSamplerIntervalSeconds` of type `lib.types.ints.positive`, defaulting to `300`.

The interval SHALL be expressed in seconds rather than as a systemd `OnCalendar` expression, because the same value must be written into the document for consumers to compute expected sample counts. Two options — one for the timer and one for the document — would drift apart.

#### Scenario: Disabled by default

- **WHEN** `enableInUseSampler` is not set
- **THEN** no sampler units exist and `inuse.json` is not served

#### Scenario: Enabled

- **WHEN** `enableInUseSampler = true`
- **THEN** a timer-driven oneshot service SHALL sample at the configured interval
- **AND** `inuse.json` SHALL be served by the existing hostinfo HTTP server

### Requirement: Sampling identifies store paths mapped by running processes

Each sample SHALL determine which Nix store paths are in use by running processes, from three sources: `/proc/<pid>/maps` (mapped shared libraries and files), `/proc/<pid>/exe` (the running executable), and `/proc/<pid>/cmdline` (interpreted scripts and unit-script wrappers).

Store paths SHALL be reduced to their store-path root, discarding the sub-path within the package, so that `/nix/store/<hash>-glibc-2.40-66/lib/libc.so.6` is recorded as `glibc-2.40-66`.

All three sources are required: a prototype reading only `maps` and `exe` observed 62 store paths on `compute5-prod`, while adding `cmdline` observed 71.

#### Scenario: Shared library attributed to its package

- **WHEN** a process has `/nix/store/<hash>-glibc-2.40-66/lib/libc.so.6` mapped
- **THEN** `glibc-2.40-66` SHALL be recorded as observed

#### Scenario: Unit script captured

- **WHEN** a service is started via a `unit-script-*` wrapper referenced only in `/proc/<pid>/cmdline`
- **THEN** that store path SHALL be recorded as observed

#### Scenario: Sampling failure on a single process is tolerated

- **WHEN** a process exits between enumeration and reading, or its `/proc` entries are unreadable
- **THEN** the sampler SHALL skip it and complete the sample successfully

### Requirement: Observations accumulate and are attributed to units

The sampler SHALL maintain a cumulative document at `/var/lib/hostinfo/inuse.json`. Observations SHALL be merged into the existing document, never replaced, so the observed set only grows.

For each observed package the document SHALL record the number of samples in which it appeared, the timestamp it was last seen, and the set of systemd units owning the processes that had it mapped. Unit attribution SHALL be derived from the process cgroup.

The document SHALL also record its schema version, the configured sampling interval in seconds, the first sample timestamp, the last sample timestamp, and the total number of samples taken.

Package keys SHALL be plain package names with the store hash removed, so that consumers can join the document against vulnix output, which is keyed by package name. Two builds sharing a name therefore merge into one key, and the name counts as in use if either build is — the conservative direction.

#### Scenario: Per-package sample counts distinguish constant from occasional use

- **WHEN** `openssl-3.6.0` has been mapped in every sample and `curl-8.21.0` in four
- **THEN** the document SHALL show sample counts reflecting that difference, so that occasional execution is distinguishable from constant execution

#### Scenario: Unit attribution recorded

- **WHEN** `openssl-3.6.0` is mapped by a `node` process in the `quiqr-server.service` cgroup
- **THEN** `quiqr-server.service` SHALL appear in that package's recorded units

#### Scenario: Accumulation across restarts

- **WHEN** the sampler service restarts or the host reboots
- **THEN** previously observed packages SHALL remain in the document with their counts intact

#### Scenario: Package observed for the first time after weeks

- **WHEN** a package not previously observed appears in a sample
- **THEN** it SHALL be added with a sample count of one, and SHALL NOT reset the counts of other packages

### Requirement: Sampling gaps are detectable

The document SHALL carry sufficient information to detect that sampling has lapsed, so that consumers can distinguish "never observed while sampling reliably" from "not observed because sampling stopped".

Consumers SHALL treat the data as unusable when the last sample is older than a multiple of the configured interval, or when the observed sample count is materially below what the interval and window imply.

#### Scenario: Sampler stopped

- **WHEN** the timer has not run for significantly longer than the configured interval
- **THEN** the staleness SHALL be detectable from the document alone, without consulting systemd

#### Scenario: Sampling coverage is quantifiable

- **WHEN** a consumer needs to state the strength of a "never observed" claim
- **THEN** the sample count and the first/last sample timestamps SHALL be available to express it as observations over a window

### Requirement: Sampler runs privileged and documents its hardening constraint

The sampler SHALL run as root, because reading `/proc/<pid>/maps` for processes owned by other users requires it.

The unit SHALL NOT set `ProtectProc` to a value that hides other processes, and SHALL NOT set `PrivateUsers`, as either renders the sampler blind while appearing to function. This constraint SHALL be stated in a comment in the module so that later hardening work does not silently disable it.

Systemd hardening that does not interfere with `/proc` visibility SHALL be applied, and the sampler SHALL be granted write access only to its own output directory.

#### Scenario: Sampler can observe other users' processes

- **WHEN** a process owned by a non-root user has a store path mapped
- **THEN** the sampler SHALL observe it

#### Scenario: Hardening does not blind the sampler

- **WHEN** the unit is evaluated
- **THEN** `ProtectSystem` SHALL be strict with write access limited to the output directory
- **AND** no setting that restricts `/proc` visibility SHALL be present

### Requirement: Document is exposed over the hostinfo HTTP server

When the sampler is enabled, `inuse.json` SHALL be served from the hostinfo directory using the same mechanism as `packages.json` and `docker-images.json`.

The document SHALL be world-readable. The hostinfo HTTP server runs unprivileged, so a document written with the default restrictive mode of a temporary file would be served as 404 despite existing.

#### Scenario: Served once written

- **WHEN** the sampler has completed at least one sample
- **THEN** `GET /inuse.json` SHALL return the document

#### Scenario: Readable by the unprivileged HTTP server

- **WHEN** the document is written by the root sampler
- **THEN** its mode SHALL permit the unprivileged hostinfo server user to read it

#### Scenario: Not yet written

- **WHEN** the sampler is enabled but has not yet completed a sample
- **THEN** the HTTP server SHALL return 404 for that path, consistent with the behaviour of other optional documents
