## 1. Sequencing

- [x] 1.1 Code prerequisite met: `fix-cve-overcounting` is implemented in the working tree (31/35, remaining tasks are deploy + handoffs), so the exporter already deduplicates. Archiving it still precedes archiving this change
- [x] 1.2 Staleness bound: `inUseStalenessBound`, default `24h`, compared against the **fetch time** (mtime of the persisted document) rather than wall-clock now — see note below
- [x] 1.3 Sampling interval default `*:0/5` (every five minutes); recorded in the document as `intervalSeconds` so consumers can compute expected sample counts

## 2. Sampler in hostinfo

- [x] 2.1 Add `elastinix.services.hostinfo.enableInUseSampler` of type `lib.types.bool`, default `false`
- [x] 2.2 Add `elastinix.services.hostinfo.inUseSamplerIntervalSeconds` of type `lib.types.ints.positive`, default `300`, driving `OnUnitActiveSec` — seconds not OnCalendar, because the value is also written to the document and two options would drift (spec updated)
- [x] 2.3 Implement collection from all three sources: `/proc/<pid>/maps`, `/proc/<pid>/exe`, `/proc/<pid>/cmdline` — `maps` + `exe` alone found 62 paths on compute5 versus 71 with all three
- [x] 2.4 Reduce each hit to the package name, hash excluded, so `/nix/store/<hash>-glibc-2.40-66/lib/libc.so.6` records as `glibc-2.40-66` — required for the join, since vulnix output is keyed by name
- [x] 2.5 Derive systemd unit attribution from each process's cgroup
- [x] 2.6 Merge into `/var/lib/hostinfo/inuse.json` cumulatively — never replace the observed set
- [x] 2.7 Record per package: sample count, last-seen timestamp, set of owning units
- [x] 2.8 Record document-level `schemaVersion`, `intervalSeconds`, `firstSample`, `lastSample`, `sampleCount`
- [x] 2.9 Tolerate processes that exit mid-sample or have unreadable `/proc` entries; the sample must still complete
- [x] 2.10 Run as root; apply systemd hardening but **not** `ProtectProc=invisible` or `PrivateUsers`, and comment in the module why, so a later hardening sweep does not blind it
- [x] 2.11 Grant write access only to the output directory under `ProtectSystem = "strict"`
- [x] 2.12 Add the timer, and the tmpfiles entry for the output path
- [x] 2.13 Serve `inuse.json` from the hostinfo directory, matching how `packages.json` and `docker-images.json` are exposed

## 3. Sampler verification

- [x] 3.1 Enabled on compute2-prod and compute5-prod; document produced and served (HTTP 200). Required a fix: `tempfile.mkstemp` creates 0600 and `os.replace` preserves it, so the document was root-only and served 404 — now chmod 0644 before the replace
- [x] 3.2 Confirm `openssl-3.6.0` is attributed to `quiqr-server.service` on compute5, matching the prototype
- [ ] 3.3 Confirm the observed set survives a service restart and a reboot with counts intact
- [x] 3.4 Confirm a newly observed package is added without resetting other packages' counts
- [x] 3.5 Confirm sample count and window are populated and advance with each run
- [x] 3.6 Confirm the sampler observes processes owned by non-root users
- [x] 3.7 Measured on compute5: 0.107s wall, 0.05s user — negligible. 75 packages observed of 907 in closure

## 4. Central scan

- [x] 4.1 Fetch `inuse.json` per host from the hostinfo HTTP server
- [x] 4.2 Persist it to that host's vulnix output directory beside `output.json`
- [x] 4.3 Write via a temporary file moved into place on success, so a failed fetch never truncates an existing document
- [x] 4.4 Reject payloads that do not parse as JSON, leaving any previous document intact
- [x] 4.5 On non-200 or unreachable host: log, count as a warning, and continue with that host's vulnix scan and all remaining hosts
- [x] 4.6 Verified: before the sampler was enabled, both hosts produced full findings labelled `inuse="unknown"`, and compute1-prod (unreachable, no sampler) still does

## 5. Exporter join

- [x] 5.1 Load each host's persisted in-use document alongside its `output.json`
- [x] 5.2 Add the `inuse` label to `vulnix_vulnerabilities_total` with values `true`, `false`, `unknown`
- [x] 5.3 Classify by joining on package name, using the same grouping key as the deduplication from `fix-cve-overcounting`
- [x] 5.4 Resolve to `unknown` when absent, unparseable, stale beyond the bound, or gapped — never `false`. Staleness measured against the document's **fetch time** (file mtime), not wall-clock now, because the scan fetches weekly and a fresh document is legitimately days old at scrape time
- [x] 5.5 Log a warning on stale or unparseable documents, and continue serving metrics for all other hosts
- [x] 5.6 Expose per-host sampling coverage: sample count and last-sample timestamp
- [x] 5.7 Publish no coverage metric for a host with no document, rather than zero
- [x] 5.8 Confirmed: compute5 true=72 + false=204 = 276, compute2 unknown=211 — both match the pre-label totals

## 6. Exporter verification

- [x] 6.1 Confirm a host with no document labels every finding `unknown`
- [x] 6.2 Confirm an artificially stale document yields `unknown` plus a logged warning, not `false`
- [x] 6.3 Confirm a truncated document yields `unknown` for that host while other hosts still report
- [x] 6.4 Confirmed against a real sampled document: `postgresql-17.10` false, `vim-9.2.0389` false, `openssl-3.6.0` true
- [x] 6.5 Recomputed with the shipped collector: 75 packages observed of 907 in closure; **72 CVE-instances in use, 204 not in use** on compute5 (supersedes the earlier 59, which came from the 62-path two-source prototype)

## 7. Rollout

- [ ] 7.1 Enable the sampler on the remaining computes — compute2-prod and compute5-prod are done; compute1/3/4/6 still pending
- [ ] 7.2 Let observations accumulate before presenting `false` as evidence; record the window used — **superseded by bean `elastinix-sw3u`**, which owns how to bound a negative claim; the first attempt at deriving it from timer cadence was withdrawn because every monthly and quarterly unit on the fleet fires daily
- [ ] 7.3 Review existing dashboards and alert rules for queries that sum the metric without aggregating away `inuse`
- [x] 7.4 Document the cadence limitation wherever the data is presented: "never observed" means "never observed at this interval", and short-lived processes are not reliably caught
- [x] 7.5 Document that `inuse="false"` counts will decrease over time as rarely-executed code is caught, and that this is the mechanism working

## 8. Documentation

- [x] 8.1 Update `docs/services/hostinfo.md` with the two new options, the `inuse.json` format, and the hardening constraint
- [x] 8.2 Update `docs/services/vulnerability-scan-central.md` with the fetch-and-persist behaviour
- [x] 8.3 Update `docs/services/vulnerability-prometheus-exporter.md` with the `inuse` label, the coverage metric, and the fail-to-`unknown` rule
- [x] 8.4 Update `CHANGELOG.md`

## 9. Follow-up handoffs

- [ ] 9.1 Grafana panel in the `monitoring` repo: findings by `inuse`, qualified by sampling coverage
- [ ] 9.2 Alert on sampler coverage stalling, in the `monitoring` repo
- [ ] 9.3 Decide whether to reconcile the observed set against `packages.json`, so packages removed from the closure do not linger forever
- [ ] 9.4 Decide whether unit attribution should be exported as a metric or remain document-only
