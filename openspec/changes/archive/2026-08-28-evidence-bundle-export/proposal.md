## Why

The central scanner collects vulnerability and attack-surface evidence but overwrites `output.json` on every run, so no finding history survives and no period-over-period ISO 27001 evidence ("14 opened, 9 closed this month") can be produced. The HASP documents that make triage possible are served by every host but never fetched. And the evidence only exists on compute5's local disk, reachable only by someone with shell access, which makes report generation an interactive infrastructure task rather than a repeatable one.

This change turns the scanner's output into a durable, self-describing evidence bundle in S3, so an ISO 27001 audit report can be generated from a single immutable snapshot with no live access to hosts or AWS.

## What Changes

- Vulnix and trivy outputs are additionally written as timestamped snapshots, retained locally for a configurable number of days. `output.json` remains as the current-run pointer so the Prometheus exporter is unaffected.
- Each scan run writes a persistent log file recording the run's actions, retained alongside the snapshots.
- The scanner fetches `hasp.json`, `hasp-aws.json` and `runtime-facts.json` from each host's hostinfo endpoint, in addition to the existing `packages.json`, `inuse.json` and `docker-images.json`.
- A normalizer merges every source into one schema-versioned `evidence.json`: run identity, fleet coverage (configured / collected / skipped with reasons), and per host the declared and derived profile, network exposure, findings with in-use status, container image findings, and a SHA-256 for every source artifact.
- The bundle is uploaded to a versioned S3 bucket under a per-run prefix. Upload is opt-in and parameterised; elastinix ships no bucket name. The scan log stays local and is not uploaded.
- The instance profile requires `s3:PutObject` only. No delete or overwrite permission, so a compromised scanner host cannot erase its own evidence history.

Not in scope: the isotto report tool that renders the bundle, and the AI triage engine that produces the not-affected and accepted-risk registers. Both are separate changes in their own repositories.

## Capabilities

### New Capabilities

- `evidence-bundle`: normalization of all per-host scan and profile artifacts into a single schema-versioned `evidence.json`, including fleet coverage accounting, per-source content hashes, and staleness marking.
- `evidence-s3-upload`: opt-in upload of the evidence bundle to a versioned S3 bucket under a per-run prefix, with write-only credentials and non-fatal failure handling.

### Modified Capabilities

- `vulnerability-scan-central`: adds fetching of the three HASP artifacts per host, timestamped snapshot retention with local rotation, and a persistent per-run scan log. Existing output paths and exit behaviour are unchanged.
- `hostinfo-socket-observation`: pins the meaning of a socket entry's sample count, which was ambiguous and implemented as one increment per socket rather than per sample.
- `hasp-host-profile`: makes the firewall facts self-describing — whether the firewall is running, and open ports per protocol — because a port allow-list emitted for a host with no firewall understates its exposure.

## Impact

- `modules/nixos/services/service-vulnerability-scan-central.nix` — fetch loop gains three artifacts, snapshot and log writing, normalizer invocation, upload step, and new options (`enableEvidenceUpload`, `evidenceBucket`, `evidencePrefix`, `snapshotRetentionDays`).
- New normalizer script, run as part of the existing scan unit rather than a separate service.
- `/var/lib/vulnix` gains timestamped files and log files; local disk growth is bounded by the retention setting.
- The Prometheus exporter is unaffected: it reads `output.json` and `inuse.json`, both of which keep their paths and meaning.
- Deployment prerequisite outside this repo: an S3 bucket with versioning and encryption enabled, and an instance profile granting `s3:PutObject` on the evidence prefix.
- Consumed downstream by a new isotto tool (separate repository, separate change) which reads only `evidence.json`.

## Task

`.beans/elastinix-w5a8--evidence-bundle-export-for-iso-27001-vulnerability.md`
