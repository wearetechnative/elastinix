# Hostinfo Service

The Hostinfo service (`elastinix.services.hostinfo`) exposes system information as JSON files via a lightweight HTTP server. It is designed for automated consumption by monitoring tools, dashboards, and lambdas.

## Features

- **Services inventory**: Daily-generated JSON listing all enabled elastinix services and programs (optional, on by default)
- **Extensible**: Any JSON file placed in `/var/lib/hostinfo/` is automatically served
- **Optional packages**: Exposes an externally-uploaded `packages.json` from `/var/lib/packages/`
- **Optional in-use sampling**: Records which store paths running processes have mapped into a daily record under `observations/`
- **Optional socket observation**: Records listening sockets with their bind address, and the user each unit runs as, into the same daily record
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
| `enableInUseSampler` | boolean | `false` | Periodically record which store paths running processes have mapped; expose as `observations/<date>.json`. |
| `enableSocketObservation` | boolean | `false` | Also record listening sockets with bind address, and unit-to-user mapping, into the same daily record. Requires `enableInUseSampler`. |
| `inUseSamplerIntervalSeconds` | positive int | `300` | Seconds between samples. Also written into the record so consumers can detect sampling gaps. |
| `inUseSamplerGapIntervals` | positive int | `2` | How many intervals a gap may span before it counts as a missed sample. A longer gap is attributed to downtime or to a stalled sampler by the host's own uptime. |
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

### `observations/` (when `enableInUseSampler = true`)

`/var/lib/hostinfo/observations/`, holding **one record per day** plus an
`index.json` naming which days are sealed.

A CVE reported against a package says only that the package is *present*. These
records answer whether its code is ever actually executed — the evidence needed
to argue a finding is not exploitable — and bound that answer to a period
someone chose rather than to whatever has elapsed since the last deploy.

```
GET /observations/index.json     -> { "current": "2026-08-31",
                                      "sealed": ["2026-08-29", "2026-08-30"],
                                      "schemaVersion": 2 }
GET /observations/2026-08-30.json
```

```json
{
  "schemaVersion": 2,
  "date": "2026-08-30",
  "sealed": true,
  "complete": true,
  "intervalSeconds": 300,
  "firstSample": "2026-08-30T00:02:00Z",
  "lastSample": "2026-08-30T23:57:00Z",
  "sampleCount": 288,
  "observedSeconds": 86400,
  "unobservedSeconds": 0,
  "downtimeSeconds": 0,
  "haspHash": "b388ba9f918c77ad",
  "aws": { "tier": "api", "lastCollected": "2026-08-30T00:02:00Z", "facts": { } },
  "awsChangedKeys": [],
  "inuse": { "observed": { "openssl-3.6.0": { "samples": 288,
                                              "lastSeen": "2026-08-30T23:57:00Z",
                                              "units": ["quiqr-server.service"] },
                           "curl-8.21.0":   { "samples": 4,
                                              "lastSeen": "2026-08-30T03:11:00Z",
                                              "units": ["vulnerability-scan-central.service"] } } },
  "sockets": { "observed": { }, "current": [ ], "clientPortRange": [32768, 60999],
               "clientSocketsLastSample": 3 },
  "units": { "user": { } }
}
```

**One series, not four.** The record carries the `haspHash` in force that day and
the `hasp-aws` values with their `changedKeys`, so a package, the machine's
declared attack surface and the AWS facts behind it are all read from the same
day rather than from three documents with three different notions of "now".

#### Sealing

The record for today is rewritten every sample. When the date rolls over, the
previous day is stamped `sealed: true`, its completeness is computed, and it is
never written again — so a consumer that has fetched a sealed day never needs to
fetch it twice, and a sealed day cannot drift.

`index.json` names `current` and every `sealed` day, so a consumer needs no
calendar arithmetic and no directory listing.

#### A complete day is all *uptime* within the day

Not 24 hours of observation. compute5-prod carries
`InstanceScheduler = "6:30am-to-10pm-everyday"` and is stopped 8.5 hours a night;
a 24-hour rule would mark it incomplete every day forever while its sampler works
perfectly.

Each sample reads `/proc/uptime`, which is what makes the distinction possible.
For a gap since the previous sample:

| gap | uptime at this sample | attributed to | day stays complete |
|---|---|---|---|
| within `inUseSamplerGapIntervals` intervals | — | `observedSeconds` | yes |
| longer | shorter than the gap | `downtimeSeconds` — the host rebooted | yes |
| longer | longer than the gap | `unobservedSeconds` — the host was up, the sampler was not | **no** |

`complete` is exactly `unobservedSeconds == 0`. Verified against a host with 5.5
hours of uptime: a 300-second gap credited 321s observed; a 7,200-second gap on a
long-running host recorded 6,900s unobserved and marked the day incomplete; a
23,283-second gap on a host that had just booted recorded 22,983s downtime and
left the day complete.

The direction of the remaining error is deliberate. A gap credits one interval of
observation rather than its full length, which understates observed time and makes
a stalled sampler easier to catch, not harder.

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

**`samples` per package matters too.** 288/288 in a day means constantly
resident; 4/288 means it runs occasionally — in that example, `curl` during the
weekly vulnerability scan and nothing else. A boolean would lose that
distinction.

#### Reading it honestly

- **The observed set grows within a day and resets with it.** A package observed
  once that day stays recorded until the day is sealed. Across a reporting period
  a consumer unions the days, so counts of "never observed" still *decrease* as
  rarely-executed code is eventually caught — but only within the period being
  reported on, which is the point.
- **"Never observed" means "never observed at this cadence."** At the default
  five minutes, long-running daemons are caught reliably and a three-second
  timer job essentially never is. Do not present absence as proof that code
  never runs.
- **A single sample proves nothing.** Claims are expressed over the reporting
  period — "not observed on any of the 31 days of August, every day complete" —
  which is why each record carries its own date and completeness rather than a
  running total.
- **Gaps are recorded, not inferred.** A lapse in sampling puts seconds in
  `unobservedSeconds` and marks the day incomplete, so a consumer cannot mistake
  an outage for evidence. Both the normalizer and the exporter report `unknown`
  for a period with no complete day.

### Socket observation (when `enableSocketObservation = true`)

The same sampler run also records **listening sockets** and **which user each
unit actually runs as**. Both are collected rather than derived, because neither
is derivable: nothing in the Nix configuration or the AWS API states which
address a process bound to.

The `sockets` and `units` blocks of the same daily record:

```json
{
  "sockets": {
    "observed": {
      "5432/tcp/loopback": { "samples": 288, "lastSeen": "2026-08-30T23:57:00Z",
                             "addresses": ["127.0.0.1"],
                             "units": ["postgresql.service"], "users": ["postgres"] },
      "3333/tcp/wildcard": { "samples": 288, "lastSeen": "2026-08-30T23:57:00Z",
                             "addresses": ["0.0.0.0"],
                             "units": ["elastinix-hostinfo-server.service"], "users": ["nobody"] }
    },
    "current": [
      { "port": 5432, "proto": "tcp", "address": "127.0.0.1",
        "bindClass": "loopback", "unit": "postgresql.service", "user": "postgres" }
    ],
    "clientPortRange": [32768, 60999],
    "clientSocketsLastSample": 3
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

**Coverage is judged per day, not against an accumulated window.** Each record
states its own `observedSeconds`, `unobservedSeconds` and `downtimeSeconds`, so a
consumer counts days rather than reconciling a numerator and a denominator that
were measured over different periods. See *A complete day is all uptime within the
day*, above.

**Ephemeral client sockets are not listeners.** `ss` reports UDP sockets with no
state, so a port `systemd-timesyncd` bound to receive one NTP reply looks
identical to a service. Because the observed set accumulates within the day and the kernel
hands out a different port each time, every sample used to add a new phantom
listener: measured on compute1-prod, 23 of 32 recorded keys were single-sample
UDP in the ephemeral range, growing by exactly one per sample — roughly 8,600
phantoms a month at a five-minute interval.

UDP sockets inside the kernel's own `ip_local_port_range` are therefore counted
as client sockets and not accumulated. The range is read from
`/proc/sys/net/ipv4/ip_local_port_range` rather than assumed, and published as
`sockets.clientPortRange` with a per-sample `sockets.clientSocketsLastSample`
count, so the sockets are evidenced rather than silently dropped. No purge is
needed: each day starts from an empty set.

TCP is exempt: `LISTEN` state is unambiguous, so a service on a high port is
still recorded as a listener.

**`samples` counts samples, not sockets.** A listener bound on both `0.0.0.0` and
`[::]` is two sockets under one `port/proto/bindClass` key, so the count is
incremented once per sample rather than once per socket. Without that, a
dual-stack listener would report twice as many samples as were ever taken —
observed live on compute2-prod, where every dual-stack entry read `4` after two
samples. `addresses`, `units` and `users` still accumulate from every socket
sharing the key.

#### Negative claims must use `observed`, not `current`

A package observed once proves it executes. A socket observed once proves only
that it was bound *then*. So `current` is a point-in-time snapshot for reporting,
and any claim that a port was **never** externally bound must cite the `observed`
set across every day of the period — a service that binds an external listener
briefly under load would be absent from most snapshots.

#### `units.user` is a list, not a string

A unit whose main process runs as root and drops privileges in a child would lose
the root fact if collapsed to one value. For privilege context, "does any process
of this unit run as root" is the question that matters.

Joined against `inuse.observed`, this gives the sentence neither document can
produce alone: *"openssl-3.6.0 is executed by `quiqr-server.service`, which runs
as root, in a process listening on all interfaces."*

#### One document, no projection

Earlier versions kept an accumulating store and projected a second document from
it in an older shape. Both are gone: there is one daily record and one reader of
it. Nothing is seeded from previous state on upgrade — the first day after
deploying is simply the first day of the new series, and until a day is sealed and
complete every consumer reports `unknown` rather than a negative claim it cannot
support.

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

### Moving state into the served directory (one-time)

Hosts deployed before this change keep state at the old paths and reach it through
symlinks that **tmpfiles will not clean up**: its remove pass runs only at boot, and
a `d` rule follows an existing symlink instead of replacing it. On a host with weeks
of uptime the records therefore keep living at the old path, where an ordinary
cleanup deletes them.

`hasp-aws.json` heals itself — the collector renames a file over that path, which
replaces the symlink. A *directory* symlink never heals, because the sampler writes
inside it and never touches the link.

So `observations/` needs doing by hand, once, per host:

```bash
systemctl stop elastinix-inuse-sampler.timer
cp -a /var/lib/inuse-sampler/daily /var/lib/hostinfo/observations.new
rm /var/lib/hostinfo/observations                        # the symlink, not the records
mv /var/lib/hostinfo/observations.new /var/lib/hostinfo/observations
systemctl start elastinix-inuse-sampler.timer
stat -c %F /var/lib/hostinfo/observations                # must say: directory
```

`cp -a` rather than `mv`, so the records survive a mistake. Once `stat` reports a
directory and the record count matches, remove `/var/lib/inuse-sampler` and
`/var/lib/docker-inventory`.

The sampler reports both ways of getting this wrong, on every run:

| State | What it prints |
|---|---|
| `observations` is still a symlink | that records are not stored where they are served, and deleting the old directory destroys them |
| symlink gone, records left behind | how many are stranded, and that the period a negative claim rests on has started over |

`index.json` is excluded from that count: it is rewritten every run, so it is not
evidence and must not keep the warning alive after the records have moved.

Newly deployed hosts never hit this — no symlink is created, so there is nothing to
repair.

### The served directory is also the state directory

Every document this module produces is written **where it is served**, rather
than written elsewhere and symlinked in:

| Path | Written by |
|---|---|
| `services.json` | `elastinix-hostinfo-inventory` |
| `observations/<date>.json` | `elastinix-inuse-sampler` |
| `hasp-aws.json` | `elastinix-hasp-aws-collector` (the HASP module) |
| `docker-images.json` | `elastinix-docker-inventory` |

Only two documents remain symlinks, both because another owner writes them:

| Path | Links to | Owner |
|---|---|---|
| `hasp.json` | a Nix store path | the build — it is a pure build product with no runtime state to place |
| `packages.json` | `/var/lib/packages/packages.json` | Terraform, outside NixOS entirely |
| `vulnix-report.json` | `/var/lib/vulnix/output.json` | the central scanner, when it runs on this host |

For a document produced outside this module, the link *is* the interface: it
decouples where the producer writes from where we serve.

**What this costs.** A writer that renames a temporary file into place needs write
access to the containing directory, so `elastinix-hasp-aws-collector` and
`elastinix-docker-inventory` hold `ReadWritePaths=/var/lib/hostinfo` where they
previously held only their own directory. The sampler stays narrower — it owns
`observations/` outright. Their `.tmp` files also appear briefly in directory
listings, which is why every writer renames rather than truncating in place: a
consumer must never be able to fetch a half-written document and read it as fact.

To add custom JSON to the hostinfo server, drop files into `/var/lib/hostinfo/`.

## Systemd Units

| Unit | Type | Description |
|------|------|-------------|
| `elastinix-hostinfo-inventory.service` | oneshot | Generates `services.json` with current timestamp (only when `enableInventory = true`) |
| `elastinix-hostinfo-inventory.timer` | timer | Triggers inventory generation daily (only when `enableInventory = true`) |
| `elastinix-hostinfo-server.service` | simple | Python HTTP server serving `/var/lib/hostinfo/` |
| `elastinix-inuse-sampler.service` | oneshot | Samples store paths mapped by running processes, plus listening sockets and unit users when `enableSocketObservation = true` |
| `elastinix-inuse-sampler.timer` | timer | Triggers sampling every `inUseSamplerIntervalSeconds`; no `Persistent`, since a missed window is a real gap in observation and must not be papered over |
| `elastinix-docker-inventory.service` | oneshot | Writes `docker-images.json` via a temporary file and a rename, because the destination is served over HTTP |

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
curl http://localhost:3333/observations/index.json | jq .
curl http://localhost:3333/observations/2026-08-30.json \
  | jq '{date, sealed, complete, observedSeconds, unobservedSeconds, sampleCount,
         inuse: (.inuse.observed | length)}'

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
