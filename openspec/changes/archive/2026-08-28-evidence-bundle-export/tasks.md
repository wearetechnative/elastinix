## 1. Run identity and scan log

- [x] 1.1 Compute a single `RUN_ID` at the top of the scan script in `YYYY-MM-DDTHH-MM-SSZ` form and verify by running the script and confirming one identical id appears in every subsequent path it writes
- [x] 1.2 Write the run's output to a persistent log file named by the run id in addition to the journal, and verify the file exists after a run and contains every host fetch outcome and tool result
- [x] 1.3 Verify the log is written even when the run ends with a non-zero error count, by pointing one host at an unreachable URL and confirming the log still exists and records the failure

## 2. HASP artifact fetch

- [x] 2.1 Add fetches for `hasp.json`, `hasp-aws.json` and `runtime-facts.json` to the per-host loop, storing each under the host's output directory, and verify all three appear for a host with HASP enabled
- [x] 2.2 Validate each fetched artifact is parseable JSON before storing, keeping any previous copy on failure, and verify by serving deliberately malformed JSON and confirming the stored file is unchanged
- [x] 2.3 Confirm stored HASP files are world-readable (mode 0644) so the exporter and normalizer can read them, verified with `stat`
- [x] 2.4 Verify a host that returns non-200 for `hasp.json` logs a warning, increments `WARNINGS`, still gets its vulnix scan, and does not stop the loop
- [x] 2.5 Verify a host serving `hasp.json` but not `hasp-aws.json` (AWS collection disabled) produces a warning and no error

## 3. Timestamped snapshots and retention

- [x] 3.1 Write each vulnix result additionally as `output-<RUN_ID>.json` beside `output.json`, and verify both files exist with identical content after a run
- [x] 3.2 Write timestamped trivy snapshots beside each image's `output.json`, and verify for a host with Docker scanning enabled
- [x] 3.3 Add a `snapshotRetentionDays` option defaulting to 180 and verify snapshots and log files older than the window are deleted at end of run, using backdated fixture files
- [x] 3.4 Verify retention never deletes `output.json`, `inuse.json` or the HASP documents, by running retention with a zero-day window and confirming those files survive
- [x] 3.5 Verify the Prometheus exporter still scrapes correctly after snapshots accumulate, by querying the metrics endpoint and confirming per-host series are unchanged

## 4. Fetch outcome state

- [x] 4.1 Record each host's per-artifact fetch outcome (success, HTTP status, or skip reason) to a run-scoped state file during the loop, and verify the file contents match a run with one deliberately unreachable host
- [x] 4.2 Verify the state file distinguishes "not served" from "served but invalid JSON" for at least one artifact

## 5. Normalizer

- [x] 5.1 Add the normalizer as a separate Python script invoked once at the end of the scan, and verify it runs and produces a file without touching any path the exporter reads
- [x] 5.2 Emit `schemaVersion`, `runId` and `generatedAt` at the bundle's top level and verify with `jq` that all three are present and correctly typed
- [x] 5.3 Build `coverage` (configured / collected / skipped-with-reason) from the run state file, and verify against a run with one unreachable host that the host appears in `configured` and `skipped` but not `collected`
- [x] 5.4 Record per-source `sha256` and `fetchedAt` for every consumed artifact, and verify a digest matches `sha256sum` of the stored file
- [x] 5.5 Surface the profile hash from `hasp.json` on that source's entry and verify it equals the hash inside the document
- [x] 5.6 Omit or explicitly mark absent sources rather than fabricating a digest, verified against a host with no `hasp-aws.json`
- [x] 5.7 Populate per-host `profile` from declared, derived and AWS facts with provenance preserved, and verify each fact's provenance survives the merge
- [x] 5.8 Populate per-host `exposure` from `runtime-facts.json` with port, protocol, bind classification and owning unit, and verify against a host with known listening sockets
- [x] 5.9 Record that socket observation was not enabled when runtime facts carry no socket data, and verify the `exposure` object is still present
- [x] 5.10 Annotate every vulnix finding with `inUse` true / false / unknown, and verify all three outcomes: a package in the in-use evidence, one absent from it, and a host whose in-use evidence is missing
- [x] 5.11 Populate per-host `images` from trivy results, empty when Docker scanning is disabled, verified on one host of each kind
- [x] 5.12 Mark `hasp-aws.json` sources stale when older than the freshness window and fresh otherwise, verified with a backdated fixture and a current one
- [x] 5.13 Verify a malformed source logs a warning, is treated as not collected, and does not prevent the bundle from being written
- [x] 5.14 Verify a run where every host is unreachable still writes a bundle with empty `coverage.collected` and every host under `coverage.skipped`
- [x] 5.15 Write the bundle via temporary file plus rename with mode 0644, and verify a mid-normalization failure leaves any previously published bundle intact

## 6. S3 upload

- [x] 6.1 Add `enableEvidenceUpload` (default false), `evidenceBucket` (no default), and `evidencePrefix` (documented default) options with descriptions stating their IAM requirement, verified by reading the generated option documentation
- [x] 6.2 Add an assertion that fails evaluation when upload is enabled without a bucket, and verify the build fails with the expected message
- [x] 6.3 Verify no AWS request is made and the bundle is still written locally when upload is disabled
- [x] 6.4 Upload `evidence.json` to `<prefix>/runs/<RUN_ID>/` and verify the key appears against a test bucket or a local S3-compatible stub
- [x] 6.5 Verify the scan log is not uploaded, by listing the run prefix and confirming `evidence.json` is its only object
- [x] 6.6 Verify only object-creation requests are issued — no delete, list, versioning or lifecycle calls — by running against a policy that grants `s3:PutObject` alone
- [x] 6.7 Treat an existing run prefix as an error rather than overwriting, and verify by re-running with a fixed run id
- [x] 6.8 Verify an upload failure logs the failed object, increments the error counter, retains the local bundle, and still exits 0, by pointing at a nonexistent bucket
- [x] 6.9 Verify a permission-denied upload logs the returned status and increments the error counter
- [x] 6.10 Confirm the AWS CLI enters the closure only when upload is enabled, by comparing closure size with the option off and on

## 7. Integration and documentation

- [x] 7.1 Run a full scan against the real fleet with upload disabled and verify the bundle covers every host, all findings, and marks the one host without AWS facts correctly
- [x] 7.2 Verify the `Warnings: N, Errors: M` summary line still reports accurately with the new failure paths in place
- [x] 7.3 Build the `nixos-system` toplevel for a host using the service and verify evaluation succeeds with upload both disabled and enabled
- [x] 7.4 Document the bundle schema (every field, its provenance and its staleness semantics) in `docs/services/vulnerability-scan-central.md` so the isotto tool can be written against it
- [x] 7.5 Document the required bucket configuration and the minimal IAM policy, and verify the documented policy is sufficient by running an upload with exactly those permissions
- [x] 7.6 Add a CHANGELOG entry and update `docs/README.md` if the service description changes

## 8. Fixes from the first real fleet run

- [x] 8.1 Count `summary.packages` from packages carrying at least one reportable finding and add `packagesFlagged` for the pre-exclusion figure, verified against a fixture where one package's every CVE is vendor-excluded
- [x] 8.2 Verify `summary.packages` equals `summary.packagesFlagged` when no exclusion applies
- [x] 8.3 Record the HASP document's own schema version on the host profile, verified against a collected `hasp.json`
- [x] 8.4 Increment a socket entry's sample count once per sample rather than once per socket, verified by running the sampler three times and confirming no entry exceeds three, including dual-stack listeners
- [x] 8.5 Verify addresses, units and users still accumulate for every socket sharing a key after the counting fix
- [x] 8.6 Update the bundle schema documentation for the new and changed summary fields

## 9. Fixes from the first audit review

- [x] 9.1 Add a `network.firewallEnabled` derived fact, verified by building a host with the firewall both enabled and disabled
- [x] 9.2 Emit empty open-port lists when the firewall is disabled, with an evidence string saying so, verified on the disabled build
- [x] 9.3 Replace the merged port fact with protocol-specific `network.firewallOpenTcpPorts` and `network.firewallOpenUdpPorts`, verified against a host allowing TCP and UDP ports that differ
- [x] 9.4 Bump `registryVersion` because the registry changed, verified in the emitted document
- [x] 9.5 Cross-reference observed sockets against the protocol-specific firewall facts in the report, verified against the real allow-lists of all three prod hosts
- [x] 9.6 Treat a disabled firewall as every port reachable in the report, and state it explicitly, verified on compute5-prod
- [x] 9.7 Degrade safely on a bundle predating these facts by reporting reachability as unknown rather than asserting it, verified against the 2026-08-28 bundle

## 10. Ephemeral client socket classification

- [x] 10.1 Read the kernel's local port range at sample time and publish it alongside the socket data, verified against `/proc/sys/net/ipv4/ip_local_port_range`
- [x] 10.2 Classify UDP sockets inside that range as client sockets rather than listeners, verified by running the sampler on a host with active NTP client sockets
- [x] 10.3 Keep TCP listeners in the ephemeral range, since LISTEN state is unambiguous
- [x] 10.4 Publish a per-sample client-socket count so the sockets are evidenced rather than silently dropped
- [x] 10.5 Purge previously accumulated ephemeral entries from the cumulative set, verified by seeding three phantoms and confirming zero remain after one sample
- [x] 10.6 Verify the cumulative key count is stable across consecutive samples, so the set no longer grows once per sample
- [x] 10.7 Document the classification and its rationale in `docs/services/hostinfo.md`

