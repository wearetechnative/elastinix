# In-use code sampling for vulnerability findings

Related task: [elastinix-krg3](../../../.beans/elastinix-krg3--fix-cve-overcounting-multi-output-dedup-cpe-vendor.md) (this change builds on it)

## Why

A CVE reported against a package in a host's closure says only that the package is *present*. It says nothing about whether the vulnerable code ever executes. That distinction is the whole difference between "we have 248 vulnerabilities" and "we have 248 findings, of which N are in code that actually runs" — and it is the evidence an ISO 27001 assessor asks for when we claim a finding is not exploitable.

Nothing in the current pipeline can answer it. Vulnix performs version matching only. Static reachability from the store graph was measured and rejected as insufficient: it classifies 188 of compute5's 248 distinct CVEs as service-reachable, because store references are transitive and over-approximate wildly. `curl`, `go`, `unbound`, `libssh2` and `hugo` all appear in `quiqr-server`'s closure while never being loaded.

Direct observation works. A prototype reading `/proc/<pid>/maps`, `/proc/<pid>/exe` and `/proc/<pid>/cmdline` on compute5 found only **71 store paths** mapped by running processes out of **907** in the closure, and attributed them to units — for example `openssl-3.6.0` is loaded by `node` in `quiqr-server.service`. That is a defensible audit statement rather than an inference.

The observation must be cumulative to be worth anything. A single sample is misleading: `curl` shows as not loaded most of the time but genuinely executes every week during the scan. Accumulating observations over weeks, with a sample count and window recorded, converts "not in the file" into "never observed in N samples over M days".

All computes run hostinfo, so the collection point already exists on every scanned host.

## What Changes

- **New hostinfo option `enableInUseSampler`** — a timer-driven sampler on each host records which store paths are mapped by running processes, accumulating into `/var/lib/hostinfo/inuse.json` and exposing it over the existing hostinfo HTTP server.
- The sampler records, per observed package: the number of samples it appeared in, when it was last seen, and the systemd units of the processes that had it mapped. The document also carries first-sample time, last-sample time and total sample count.
- **Central scan fetches and persists `inuse.json`** per host, alongside the existing `output.json`, so findings and their supporting evidence are co-located and share a timestamp.
- **Exporter joins the two** on package name and adds an `inuse` label to `vulnix_vulnerabilities_total`, with values `true`, `false` and `unknown`.
- Absence of sampler data, stale data, or a detected sampling gap SHALL resolve to `unknown` — never to `false`.

Not in scope: the Grafana dashboard itself (lives in the `monitoring` repo), CISA KEV and EPSS enrichment, and any whitelist or suppression. Nothing is hidden by this change; findings gain a label.

## Capabilities

### New Capabilities

- `hostinfo-inuse-sampler`: timer-driven sampling of store paths mapped by running processes, the cumulative `inuse.json` document format including sample-count and unit attribution, and gap detection.

### Modified Capabilities

- `vulnerability-scan-central`: gains requirements to fetch `inuse.json` per host and persist it beside that host's `output.json`, tolerating absence.
- `vulnerability-prometheus-exporter`: gains requirements to join the in-use document with vulnix findings and expose the `inuse` label, failing to `unknown`.

Both are expressed as **ADDED** requirements rather than modifications to existing ones. `fix-cve-overcounting` currently holds an unarchived `MODIFIED` delta against the exporter's `vulnix metrics` requirement; restating that requirement here would mean whichever change archives second overwrites the other. Adding separate requirements avoids the collision entirely.

## Impact

**Code**

- `modules/nixos/services/service-hostinfo.nix` — new option, sampler service and timer, tmpfiles entry, HTTP exposure.
- `modules/nixos/services/service-vulnerability-scan-central.nix` — fetch and persist step per host.
- `modules/nixos/services/service-vulnerability-prometheus-exporter.nix` — join and label.

**Deployment**

Requires a deploy to every scanned host, not just the scanner — this is the first part of the vulnerability pipeline that runs on the scanned hosts themselves. All computes already run hostinfo, so no new service enablement pattern is needed, but each host needs the option set.

**Security posture**

The sampler needs root to read other processes' `/proc/<pid>/maps`, and therefore cannot use `ProtectProc=invisible` — the hardening that would otherwise be reflexive here would silently render it blind. This constraint must be documented in the module so it is not "hardened" into uselessness later.

**Reporting**

`vulnix_vulnerabilities_total` gains a third label. Existing queries that sum over the metric without aggregating away `inuse` will fan out into three series per severity. Dashboards and alert rules need reviewing before rollout.

**Honest limits**

At a five-minute cadence the sampler reliably catches long-running daemons and will usually miss short-lived processes. "Never observed" therefore means "never observed at this cadence", which is weaker than it sounds and must be stated wherever the data is presented as evidence. The observed set also grows over time, so the count of `inuse="false"` findings will *decrease* as rarely-executed code is eventually caught — that is the mechanism working correctly, not a regression.

**Dependency**

Builds on `fix-cve-overcounting`, which should be implemented and archived first. That change already alters the exporter's vulnix counting loop; landing this on top of an un-deduplicated collector would produce per-store-path rows labelled by in-use status, which is not the intended reporting shape.
