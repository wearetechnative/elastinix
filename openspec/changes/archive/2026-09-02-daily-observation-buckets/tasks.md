## 1. Sampler: write and seal a day

- [x] 1.1 Write the current day's observations to a dated record under the sampler's state directory, verified by reading it after three samples
- [x] 1.2 Seal the previous day and start a new record when the first sample of a new date is taken, verified by backdating a record's date and confirming a new one appears
- [x] 1.3 Verify a sealed record is not modified by any later sample, by comparing its digest before and after further samples
- [x] 1.4 Record that day's in-use observations with per-package sample counts, and verify a package observed only on an earlier day is absent from today's record
- [x] 1.5 Record that day's socket observations with port, protocol, bind classification and owning unit, and verify the ephemeral-port classification still applies within a day
- [x] 1.6 Name the profile hash in force during the day, taken from `hasp.json` unchanged, verified equal to the value on disk
- [x] 1.7 Record the infrastructure fact values and the keys that changed during the day, verified against `hasp-aws.json`
- [x] 1.8 Write each record atomically with mode 0644, so the unprivileged hostinfo server can serve it and a crash cannot publish a truncated record

## 2. Sampler: uptime accounting

- [x] 2.1 Read `/proc/uptime` each run and record the observed and unobserved seconds the day accounts for, verified against a host whose boot time is known
- [x] 2.2 Attribute a gap longer than the threshold to downtime when uptime is shorter than the gap, verified by simulating a reboot
- [x] 2.3 Attribute it to unobserved time when uptime is longer than the gap, verified by backdating the previous sample without a reboot
- [x] 2.4 Mark a day complete when observation covered the host's uptime, verified on compute1-prod at 24 h and compute5-prod at 15.5 h — both complete
- [x] 2.5 Mark a day incomplete when it accounts for unobserved time while the host ran, and verify the record states which portion
- [x] 2.6 Strict: any time the host ran while nothing sampled it leaves the day incomplete; downtime does not, because no observation was owed. `inUseSamplerGapIntervals` default lowered 3 -> 2 so a genuinely missed sample is not hidden by the timer's own accuracy

## 3. Sampler: remove the accumulating window

- [x] 3.1 Remove `observedWindowSeconds`, `samplesInObservedWindow` and `observedWindowEpoch`, verified absent from the emitted documents
- [x] 3.2 Remove the cumulative in-use and socket document, verified that no host writes it after deploy
- [x] 3.3 Verify the sampler no longer carries any field whose value depends on a previous deploy

## 4. Hostinfo: serve the records

- [x] 4.1 Serve the sealed records over hostinfo, verified by fetching one by name
- [x] 4.2 Verify the record for the day in progress is distinguishable from a sealed one, so a consumer can skip it
- [x] 4.3 The host prunes nothing; retention lives on S3. About 20 kB a day, 7 MB a year, and nothing is lost if the scan is skipped for weeks

## 5. Scanner: fetch and upload

- [x] 5.1 Fetch every sealed record a host offers that is not already stored locally, verified against a host with six days sealed
- [x] 5.2 Skip the record for the day in progress, verified from the run log
- [x] 5.3 Record a SHA-256 of the received bytes per record
- [x] 5.4 Log a warning and continue when a host offers no records
- [x] 5.5 Upload each record to `<prefix>/daily/<host>/<date>.json`, verified against a test bucket
- [x] 5.6 Skip a record whose key already exists without treating the run as failed, verified by uploading twice
- [x] 5.7 Verify only object creation is used, so the existing write-only policy remains sufficient

## 6. Coverage in both consumers

- [x] 6.1 Judge coverage in the normalizer from the daily records, counting complete days, verified against a fixture with a mix of complete and incomplete days
- [x] 6.2 Report `unknown` when no record exists for the period, verified with an empty series
- [x] 6.3 Record the period examined, the days examined and the days complete per host in the bundle, verified with `jq`
- [x] 6.4 Remove the paired-window guard and the fallback to elapsed time from the normalizer
- [x] 6.5 Apply the identical coverage change to the exporter
- [x] 6.6 Expose days examined and days complete per host as metrics
- [x] 6.7 Verify the exporter's `inuse` labels match the bundle's values host for host on the same input

## 7. Integration and documentation

- [x] 7.1 Build the `nixos-system` toplevel for a scanned host and a scanner host and verify evaluation succeeds
- [x] 7.2 Run the sampler across a simulated day boundary on real host data and verify the seal, the uptime accounting and the completeness verdict
- [x] 7.3 Verify a bundle built from daily records reports the same in-use verdicts as the current bundle for a host whose coverage is complete
- [x] 7.4 Document the record, its fields, the completeness rule and the uptime attribution in `docs/services/hostinfo.md`
- [x] 7.5 Document the fetch list, the upload layout and the coverage derivation in `docs/services/vulnerability-scan-central.md`
- [x] 7.6 Document in `docs/vulnix-cve-automation.md` that a negative claim is bounded by the reporting period, and what that does not cover
- [x] 7.7 Add a CHANGELOG entry recording that the in-use baseline resets and that every finding reports `unknown` for one day
- [x] 7.8 Note the S3 lifecycle rule for the `daily/` prefix as a deployment prerequisite outside this repository
