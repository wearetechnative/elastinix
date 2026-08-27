# Hostinfo Service

The Hostinfo service (`elastinix.services.hostinfo`) exposes system information as JSON files via a lightweight HTTP server. It is designed for automated consumption by monitoring tools, dashboards, and lambdas.

## Features

- **Services inventory**: Daily-generated JSON listing all enabled elastinix services and programs (optional, on by default)
- **Extensible**: Any JSON file placed in `/var/lib/hostinfo/` is automatically served
- **Optional packages**: Exposes an externally-uploaded `packages.json` from `/var/lib/packages/`
- **Optional in-use sampling**: Records which store paths running processes have mapped and exposes it as `inuse.json`
- **Optional socket observation**: Records listening sockets with their bind address, and the user each unit runs as, exposing them as `runtime-facts.json`
- **Optional attack surface profile**: Serves `hasp.json` and `hasp-aws.json` when [`elastinix.hasp`](hasp.md) is enabled
- **Pure builds**: Static data is embedded at build time; only the timestamp is injected at runtime
- **Configurable port**: Default `3333`, override as needed
- **Automatic firewall**: Opens the configured port without manual configuration
- **Systemd hardening**: Both the inventory generator and HTTP server run with restricted permissions

## Configuration

### Basic Example

```nix
elastinix.services.hostinfo = {
  enable = true;
};
```

### Without inventory generation

Run the HTTP server without generating `services.json` (e.g. to serve only externally-provided files):

```nix
elastinix.services.hostinfo = {
  enable = true;
  enableInventory = false;
};
```

### With packages inventory

Expose the package list uploaded by Terraform to `/var/lib/packages/packages.json`:

```nix
elastinix.services.hostinfo = {
  enable = true;
  enablePackages = true;
};
```

### With Docker image inventory

Expose the list of running Docker containers as `docker-images.json` for central trivy scanning:

```nix
elastinix.services.hostinfo = {
  enable = true;
  enableDockerImages = true;
};
```

### With in-use sampling

Record which packages running processes actually execute, for joining against
vulnerability findings:

```nix
elastinix.services.hostinfo = {
  enable = true;
  enableInUseSampler = true;
};
```

### Custom Port

```nix
elastinix.services.hostinfo = {
  enable = true;
  port = 8080;
};
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the hostinfo service |
| `port` | port (1–65535) | `3333` | Port for the HTTP server |
| `enableInventory` | boolean | `true` | Generate `services.json` via daily timer. Set to `false` to skip inventory generation. |
| `enablePackages` | boolean | `false` | Symlink `/var/lib/packages/packages.json` as `packages.json`. Source uploaded externally by Terraform. |
| `enableInUseSampler` | boolean | `false` | Periodically record which store paths running processes have mapped; expose as `inuse.json`. |
| `enableSocketObservation` | boolean | `false` | Also record listening sockets with bind address, and unit-to-user mapping; expose as `runtime-facts.json`. Requires `enableInUseSampler`. |
| `inUseSamplerIntervalSeconds` | positive int | `300` | Seconds between samples. Also written into the document so consumers can detect sampling gaps. |
| `enableDockerImages` | boolean | `false` | Generate Docker image inventory from Docker socket and expose as `docker-images.json` |
| `enableVulnixReport` | boolean | `false` | Symlink `/var/lib/vulnix/output.json` as `vulnix-report.json`. **Stale:** that path belonged to the removed local `vulnix-scan` service. Central scanning writes per-host results to `/var/lib/vulnix/<host>/output.json`, so this serves whatever leftover file happens to exist — verified serving a four-week-old report in production. Leave disabled. |

## JSON Output

### `services.json`

Generated daily at `/var/lib/hostinfo/services.json`:

```json
{
  "hostname": "compute2-prod",
  "buildTime": "2026-05-11T08:00:00Z",
  "services": {
    "badgersbay": true,
    "hostinfo": true,
    "vulnix-scan": true
  },
  "programs": {
    "awsUtils": true,
    "docker": true
  },
  "nixosVersion": "26.05.0",
  "systemStateVersion": "26.05"
}
```

| Field | Description |
|-------|-------------|
| `hostname` | NixOS hostname (`config.networking.hostName`) |
| `buildTime` | ISO 8601 UTC timestamp of last inventory generation |
| `services` | Map of enabled `elastinix.services.*` names to `true` |
| `programs` | Map of enabled `elastinix.programs.*` names to `true` |
| `nixosVersion` | Full NixOS version string |
| `systemStateVersion` | NixOS state version |

### `packages.json` (when `enablePackages = true`)

A symlink to `/var/lib/packages/packages.json`, containing the NixOS package inventory uploaded by Terraform. If the source file does not exist yet, the HTTP server returns a 404 for this path.

Each package entry carries a `patches` array. Entries may be **patch filenames**
or **bare CVE identifiers** — both are equivalent to vulnix, which joins the
array into one string and scans it with a `CVE-\d{4}-\d+` regex to suppress
already-patched CVEs. Bare identifiers let a generator declare CVEs it found
inside patch *contents* rather than in the filename, which matters because only
51 of 352 patch filenames in a measured closure carry a CVE id, while glibc's
`X.YY-master.patch` rollups carry 27 inside the file body.

```json
{
  "pkg3": {
    "name": "glibc-2.42-67",
    "patches": [
      "43b9m8jsp2sybz9n2yfjs5fpcv2x5ir3-2.42-master.patch",
      "CVE-2024-33599",
      "CVE-2024-33600"
    ]
  }
}
```

### `inuse.json` (when `enableInUseSampler = true`)

A symlink to `/var/lib/inuse-sampler/inuse.json`, recording which packages have
been observed mapped by running processes.

A CVE reported against a package says only that the package is *present*. This
document answers whether its code is ever actually executed — the evidence
needed to argue a finding is not exploitable.

```json
{
  "schemaVersion": 1,
  "intervalSeconds": 300,
  "firstSample": "2026-08-25T13:20:13Z",
  "lastSample": "2026-09-24T10:05:00Z",
  "sampleCount": 8641,
  "observed": {
    "openssl-3.6.0": {
      "samples": 8641,
      "lastSeen": "2026-09-24T10:05:00Z",
      "units": ["quiqr-server.service"]
    },
    "curl-8.21.0": {
      "samples": 4,
      "lastSeen": "2026-09-22T03:11:00Z",
      "units": ["vulnerability-scan-central.service"]
    }
  }
}
```

Each sample reads `/proc/<pid>/maps`, `/proc/<pid>/exe` and
`/proc/<pid>/cmdline` for every process. All three are needed: `maps` + `exe`
alone observed 62 store paths on a live host, while including `cmdline` — which
catches interpreted scripts and `unit-script-*` wrappers — observed 71.

Keys are package names with the store hash removed, so the document can be
joined against vulnix output. Two builds sharing a name merge into one key, and
the name counts as in use if either build is.

**`units` is the point.** It turns an inference into an observation: *"OpenSSL
3.6.0 is loaded by `quiqr-server.service`"* rather than *"OpenSSL appears to be
used"*.

**`samples` per package matters too.** 8641/8641 means constantly resident;
4/8641 means it runs occasionally — in that example, `curl` during the weekly
vulnerability scan and nothing else. A boolean would lose that distinction.

#### Reading it honestly

- **The observed set only grows.** It is merged, never replaced, so a package
  observed once stays recorded. Counts of "never observed" will therefore
  *decrease* over time as rarely-executed code is eventually caught. That is
  the mechanism working, not a regression.
- **"Never observed" means "never observed at this cadence."** At the default
  five minutes, long-running daemons are caught reliably and a three-second
  timer job essentially never is. Do not present absence as proof that code
  never runs.
- **A single sample proves nothing.** Claims should be expressed as
  observations over a window — "never observed in 8,641 samples over 30 days"
  — which is why `sampleCount`, `firstSample` and `lastSample` are recorded.
- **Gaps weaken the data silently.** If sampling lapses, "never observed"
  becomes an artefact of the outage. `intervalSeconds` plus the window lets
  consumers detect that; the vulnerability exporter treats a gap as `unknown`.

### `runtime-facts.json` (when `enableSocketObservation = true`)

The same sampler run also records **listening sockets** and **which user each
unit actually runs as**. Both are collected rather than derived, because neither
is derivable: nothing in the Nix configuration or the AWS API states which
address a process bound to.

```json
{
  "schemaVersion": 1,
  "intervalSeconds": 300,
  "firstSample": "2026-08-25T13:20:13Z",
  "lastSample": "2026-09-24T10:05:00Z",
  "sampleCount": 8641,
  "inuse": { "observed": { "openssl-3.6.0": { "samples": 8641, "units": ["quiqr-server.service"] } } },
  "sockets": {
    "observed": {
      "5432/tcp/loopback": { "samples": 8641, "lastSeen": "2026-09-24T10:05:00Z",
                             "addresses": ["127.0.0.1"],
                             "units": ["postgresql.service"], "users": ["postgres"] },
      "3333/tcp/wildcard": { "samples": 8641, "lastSeen": "2026-09-24T10:05:00Z",
                             "addresses": ["0.0.0.0"],
                             "units": ["elastinix-hostinfo-server.service"], "users": ["nobody"] }
    },
    "current": [
      { "port": 5432, "proto": "tcp", "address": "127.0.0.1",
        "bindClass": "loopback", "unit": "postgresql.service", "user": "postgres" }
    ]
  },
  "units": { "user": { "postgresql.service": ["postgres"],
                       "quiqr-server.service": ["root"] } }
}
```

**Bind address is the point.** A service bound to `127.0.0.1` is unreachable from
anywhere else whatever the security group says. `postgresql-17.10` is the
joint-largest package on compute2-prod at 26 CVEs; "5432 is not in the firewall
list" is a weak claim, while "nothing outside this machine can reach it" is a
strong one.

`bindClass` is `loopback`, `wildcard` or `specific`, kept next to the raw address
rather than replacing it. Two classification subtleties, both of which change the
answer:

- `[::]` is **wildcard**, not IPv6-only: such a socket accepts IPv4 connections
  too unless `v6only` is set.
- `::ffff:127.0.0.1` is **loopback**. It is an IPv4-mapped IPv6 address, and
  reading it as `specific` would forfeit the strongest available claim. Observed
  live on a real host, from Neo4j.

The scope suffix `ss` reports (`127.0.0.53%lo`) is stripped before
classification.

#### Negative claims must use `observed`, not `current`

A package observed once proves it executes. A socket observed once proves only
that it was bound *then*. So `current` is a point-in-time snapshot for reporting,
and any claim that a port was **never** externally bound must cite the cumulative
`observed` set — a service that binds an external listener briefly under load
would be absent from most snapshots.

#### `units.user` is a list, not a string

A unit whose main process runs as root and drops privileges in a child would lose
the root fact if collapsed to one value. For privilege context, "does any process
of this unit run as root" is the question that matters.

Joined against `inuse.observed`, this gives the sentence neither document can
produce alone: *"openssl-3.6.0 is executed by `quiqr-server.service`, which runs
as root, in a process listening on all interfaces."*

#### `inuse.json` is a projection

`runtime-facts.json` is the accumulating store; `inuse.json` is written each run
from the same state in its original shape, so existing consumers keep working
unchanged. On first run after upgrading, state is seeded from an existing
`inuse.json` — months of accumulated samples are the observation window every
"never observed" claim depends on, and discarding them would silently weaken the
evidence rather than fail.

#### Netlink is required

`ss` enumerates sockets via `sock_diag` over netlink, so the sampler unit is
granted `AF_NETLINK` when socket observation is enabled — and only then. Denying
it would make `ss` return nothing while still exiting successfully, so the
sampler would report no listening sockets on a host full of them. Same class of
failure as hiding `/proc`, below.

#### Hardening constraint

The sampler runs as **root** — reading `/proc/<pid>/maps` for processes owned by
other users is privileged.

It deliberately does **not** set `ProtectProc` or `PrivateUsers`. Either hides
other processes from `/proc`, which would make the sampler observe nothing while
still exiting successfully — it would keep reporting "not in use" for code that
is running. The module carries a comment saying so, because this is exactly the
kind of setting a well-meaning hardening pass would add.

Everything that does not affect `/proc` visibility is applied: `ProtectSystem =
"strict"` with write access limited to its own directory, `PrivateTmp`,
`NoNewPrivileges`, and no network access at all.

## Storage Directory

All files in `/var/lib/hostinfo/` are served automatically. The directory is created with permissions `0755 root root` via `systemd.tmpfiles`.

To add custom JSON to the hostinfo server, drop files into `/var/lib/hostinfo/`.

## Systemd Units

| Unit | Type | Description |
|------|------|-------------|
| `elastinix-hostinfo-inventory.service` | oneshot | Generates `services.json` with current timestamp (only when `enableInventory = true`) |
| `elastinix-hostinfo-inventory.timer` | timer | Triggers inventory generation daily (only when `enableInventory = true`) |
| `elastinix-hostinfo-server.service` | simple | Python HTTP server serving `/var/lib/hostinfo/` |
| `elastinix-inuse-sampler.service` | oneshot | Samples store paths mapped by running processes, plus listening sockets and unit users when `enableSocketObservation = true` |
| `elastinix-inuse-sampler.timer` | timer | Triggers sampling every `inUseSamplerIntervalSeconds`; no `Persistent`, since a missed window is a real gap in observation and must not be papered over |

## Useful Commands

```bash
# Check server status
systemctl status elastinix-hostinfo-server.service

# Check inventory generator
systemctl status elastinix-hostinfo-inventory.service

# Manually trigger inventory regeneration
systemctl start elastinix-hostinfo-inventory.service

# View server logs
journalctl -u elastinix-hostinfo-server.service -f

# Test HTTP endpoint
curl http://localhost:3333/services.json | jq .

# Test in-use endpoint (if enableInUseSampler = true)
curl http://localhost:3333/inuse.json | jq '{sampleCount, observed: (.observed | length)}'

# List all served files
curl http://localhost:3333/
```

## Security

The HTTP server runs as `nobody:nogroup` with extensive systemd hardening:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `ProtectKernelTunables=true`
- `ProtectControlGroups=true`
- `ReadOnlyPaths=/etc /var/lib/hostinfo`

No authentication is applied. The endpoint is intended for internal network use. For HTTPS and access control, see bean `elastinix-n3zn` (nginx vhost, planned).

## Future Work

- **nginx vhost** (`elastinix-n3zn`): HTTPS access at `hostinfo.${domain}` with optional auth
- **Rename `buildTime` to `lastUpdated`** (`elastinix-vtja`): Requires updating lambda `elastinix_services_monitor_prod`

## Implementation Details

- **Service definition**: `modules/nixos/services/service-hostinfo.nix`
- **HTTP server**: Python `http.server` (stdlib, no external deps)
- **Inventory generation**: `jq` injects `buildTime` at runtime into a pure Nix-store template (only when `enableInventory = true`)
- **Symlinks**: `systemd.tmpfiles` `L+` rules for `enablePackages`, `enableDockerImages`, `enableInUseSampler`, `enableSocketObservation`, and `enableVulnixReport`
