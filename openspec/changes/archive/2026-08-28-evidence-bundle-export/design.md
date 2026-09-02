## Context

See proposal.md — Why.

Constraints that shape the approach:

- The scan unit is a single `pkgs.writeShellScript` invoked by a timer. It already loops over hosts fetching `packages.json`, `inuse.json` and `docker-images.json` via curl, and tolerates per-host failure by counting warnings and continuing.
- The Prometheus exporter reads `/var/lib/vulnix/<host>/output.json` and `/var/lib/vulnix/<host>/inuse.json` by fixed path, and enumerates hosts by `os.listdir`. Any layout change that moves or renames those two files breaks it.
- Hosts already serve `hasp.json`, `hasp-aws.json` and `runtime-facts.json` from `/var/lib/hostinfo` on the hostinfo port. No host-side change is needed.
- `hasp.json` is a build product and only changes on rebuild. `hasp-aws.json` is refreshed by a timer on the host and changes without a rebuild. `runtime-facts.json` accumulates. Their freshness properties therefore differ and cannot be treated uniformly.
- Evaluation does not happen on the scanner host, so nothing in the bundle can be derived from Nix at report time. Everything must be present in the fetched artifacts.
- elastinix is a reusable flake consumed by several accounts. It cannot hardcode a bucket, a region or an account id.

## Goals / Non-Goals

**Goals:**

- One file downstream (`evidence.json`) fully describes a run, including what was *not* collected.
- A report can cite a digest instead of reprinting a 500-row inventory, with the digest bound to an object retrievable from S3.
- Finding history survives runs, so opened/closed counts become possible without keeping every artifact forever on local disk.
- A compromised scanner host cannot rewrite or delete evidence it previously produced.

**Non-Goals:**

- Deciding CVE relevance. The bundle carries facts and findings; whitelisting, graylisting and VEX justifications belong to the triage engine.
- Rendering. No markdown, no ISO control mapping, no report layout in this repo.
- Provisioning the bucket, its versioning, encryption, lifecycle or Object Lock. That is Terraform's job; this change consumes a bucket that already exists.
- Fleet reconciliation against AWS (detecting hosts that exist but are not configured for scanning). Coverage here is measured against the configured host list only.

## Decisions

### Normalize on the scanner, ship one bundle

The bundle is built on compute5 and only `evidence.json` is uploaded for consumers.

*Alternative considered:* upload the raw artifacts and let the consumer merge them. That keeps report iteration off the deploy path and preserves unmodified tool output as evidence, but it pushes knowledge of six formats into every consumer and makes coverage accounting a log-parsing exercise. Normalizing centrally means the producer — which is the only component that knows which fetches failed — records coverage structurally.

*Consequence accepted:* changing the bundle format requires a rebuild and deploy of the scanner host, and a normalization bug cannot be retroactively fixed in already-uploaded bundles. `schemaVersion` bounds the first problem. The second is mitigated by local snapshot retention, which keeps the raw inputs available long enough to re-normalize a recent run, and by keeping retention generous relative to the reporting cadence.

### Snapshots beside the current output, not instead of it

`output.json` keeps its exact path and meaning; a timestamped copy is written next to it. Retention deletes only timestamped files.

*Alternative considered:* make the timestamped file canonical and have the exporter glob for the newest. That is cleaner but changes the exporter's contract for no benefit to this change, and the exporter's spec explicitly commits to the current paths.

### Run id is a single timestamp threaded through the run

One `runId` is computed at the start of the scan and used for every snapshot filename, the log filename, the bundle's `runId` and the S3 prefix. Using `YYYY-MM-DDTHH-MM-SSZ` (colons replaced with hyphens) keeps it safe as both a filename and an S3 key segment while sorting lexicographically.

*Alternative considered:* per-artifact timestamps. Rejected because it makes it impossible to say which snapshots belong to the same run, which is the whole point of the run prefix.

### Coverage is structural, not parsed from the log

The fetch loop records each host's per-artifact outcome in a temporary state file; the normalizer reads it. The scan log exists for human review on the scanner host, never as an input to the bundle and never as a downstream artifact.

This is the direct consequence of normalizing centrally: the alternative — greping `WARNING: Could not fetch` out of the log — is stringly-typed and breaks the first time a message is reworded.

### Python for the normalizer, shell for the fetch loop

The fetch loop stays shell, matching the existing script. Normalization is a separate Python script invoked once at the end of the run. Merging six JSON documents, hashing, timestamp arithmetic and staleness comparison in shell with jq would be substantially worse to read and to change.

The scanner host already has Python available in the closure via the exporter; no new dependency is introduced beyond the AWS CLI needed for upload.

### `s3:PutObject` only, and a run prefix that is never reused

Upload uses object creation exclusively. The service does not delete, does not overwrite, and does not touch bucket configuration. Combined with bucket versioning provisioned outside this repo, that means the scanner cannot destroy its own history even if compromised — which is the property an auditor is actually asking about when they ask how evidence integrity is assured.

A run id collision is treated as an error rather than an overwrite, so the no-overwrite property holds even under clock anomalies.

*Alternative considered:* let the service manage lifecycle and versioning so the bucket is self-configuring. Rejected: it requires far broader permissions and inverts the security property that makes this worth doing.

### Upload failure is non-fatal

A failed upload increments the error counter, logs the object that failed, and leaves the local bundle in place. The unit still exits 0.

The scan itself succeeded; failing the unit would page someone about an S3 blip and would misrepresent collection as broken. The error count and the existing `Warnings: N, Errors: M` summary line surface it, and the missing run prefix in S3 is itself visible to the consumer.

### Staleness is per-artifact with different windows

`hasp.json` is a build product — it is stale only in the sense that the host has not rebuilt, which is not a scanner concern, so it gets no window. `hasp-aws.json` has a host-side refresh interval and therefore a real window. `runtime-facts.json` is cumulative and its liveness question is "is the sampler still running", which the exporter already answers the same way.

Marking rather than refusing: the bundle records `stale: true` and the report decides whether that is disqualifying. Refusing to write a bundle because one host's AWS facts aged out would lose the other hosts' evidence.

## Risks / Trade-offs

- **Normalization bug cannot be fixed in uploaded bundles** → `schemaVersion` lets consumers detect format changes; local snapshot retention keeps raw inputs available to re-normalize recent runs. Retention should be set generously relative to the reporting cadence.
- **Bundle format changes require deploying the scanner host** → accepted cost of normalizing centrally. Keep the schema additive wherever possible so consumers tolerate new fields without a version bump.
- **`hasp-aws.json` contains security group ids, subnet ids, VPC id and public-IP status** → the bundle is a map of the attack surface. The bucket must be private with encryption at rest and no cross-account read. This change does not provision that; it must be verified during deployment.
- **Local disk growth from snapshots** → bounded by the retention option, which defaults to a documented number of days. Volume is small (single-digit MB per run for the current fleet) but unbounded growth on a long-lived host is still a real failure mode.
- **Silent under-reporting if a host is dropped from the configured list** → coverage is measured against the configured list, so a host removed from configuration disappears from `coverage.configured` and no longer registers as skipped. Reconciling the configured list against the actual AWS fleet is out of scope and remains an open exposure.
- **AWS CLI added to the scanner's closure** → only when upload is enabled. Keep the upload path behind the enable flag so deployments that do not use it pay nothing.
- **Clock skew on the scanner host** → run ids and staleness comparisons both depend on the host clock. A badly skewed clock produces misordered run prefixes and wrong staleness marks. NTP is assumed; a collision on the run prefix is treated as an error rather than silently overwriting.

## Migration Plan

1. Deploy with `enableEvidenceUpload = false`. Snapshots, the scan log (local only), HASP fetching and local bundle generation all start working with no AWS dependency and no new permissions. Verify the bundle against a real run.
2. Provision the bucket in Terraform: versioning on, encryption on, public access blocked, lifecycle to a cheaper storage class, optionally Object Lock. Attach an instance-profile policy granting `s3:PutObject` on the evidence prefix and nothing else.
3. Set `enableEvidenceUpload = true` with the bucket and prefix. Confirm one run prefix appears and that the policy genuinely refuses a delete.
4. Build the isotto tool against a real uploaded bundle (separate change, separate repository).

Rollback: set `enableEvidenceUpload = false`. Snapshots and the local bundle are additive and can be left in place; if they must go, remove the timestamped files and the log directory. Nothing the exporter reads is touched at any point, so rollback cannot affect metrics.

## Resolved Questions

- **Retention is 180 days.** Six months of snapshots and logs are kept locally. At the current fleet size that is well under a gigabyte, and it comfortably exceeds any plausible reporting cadence, so re-normalizing an earlier run from its raw inputs stays possible for the whole period an uploaded bundle is likely to be questioned.
- **The scan log is not uploaded.** It stays on the scanner host under the same retention. Nothing downstream needs it: skipped hosts and their reasons are structural fields in the bundle's `coverage`, so a report never has to consult the log.
