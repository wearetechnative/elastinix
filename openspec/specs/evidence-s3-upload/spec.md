# evidence-s3-upload Specification

## Purpose
Uploads the evidence bundle to a versioned S3 bucket under a per-run prefix using write-only credentials, giving ISO 27001 audits a durable, tamper-evident evidence store that a report generator can read without shell access to the scanner host.

## Requirements

### Requirement: Upload is opt-in

The service SHALL NOT upload anything unless evidence upload is explicitly enabled, so existing deployments keep working unchanged and elastinix ships no bucket of its own.

#### Scenario: Upload disabled by default

- **WHEN** the scanner is configured without enabling evidence upload
- **THEN** no S3 request is made
- **AND** the bundle is still written locally

#### Scenario: Upload enabled without a bucket

- **WHEN** evidence upload is enabled but no bucket name is configured
- **THEN** evaluation fails with an assertion naming the missing bucket option

#### Scenario: No bucket name is defaulted

- **WHEN** the module's options are inspected
- **THEN** the bucket option has no default value

### Requirement: Per-run object layout

The service SHALL upload the run's evidence bundle under a prefix identifying that run, so one prefix is exactly one point-in-time fleet snapshot.

#### Scenario: Bundle placed under the run prefix

- **WHEN** a run with id `2026-08-27T02-00-00Z` uploads successfully to bucket `example-evidence` with prefix `vulnerability`
- **THEN** the bundle is at `s3://example-evidence/vulnerability/runs/2026-08-27T02-00-00Z/evidence.json`

#### Scenario: Scan log is not uploaded

- **WHEN** an upload completes
- **THEN** the run's scan log is retained locally only
- **AND** no log object is created under the run prefix

#### Scenario: Later run does not disturb an earlier one

- **WHEN** a subsequent run uploads its bundle
- **THEN** it writes under its own run prefix
- **AND** objects under previous run prefixes are left untouched

### Requirement: Write-only credential use

The service SHALL only ever create new objects, never delete or overwrite existing ones, so it operates correctly under a policy granting `s3:PutObject` alone and cannot erase its own evidence history.

#### Scenario: No delete or list calls issued

- **WHEN** an upload runs
- **THEN** the service issues only object-creation requests
- **AND** it does not issue delete, versioning or lifecycle requests

#### Scenario: Existing run prefix is not reused

- **WHEN** a run id collides with a prefix that already exists
- **THEN** the run is treated as an error rather than overwriting the existing objects

### Requirement: Upload failure is reported but not fatal

The service SHALL treat an upload failure as an error in the run summary without failing the scan unit, so a transient S3 problem does not mask a successful collection.

#### Scenario: S3 unreachable

- **WHEN** the upload fails because S3 cannot be reached
- **THEN** a warning is logged naming the failed object
- **AND** the error counter is incremented
- **AND** the locally written bundle is retained
- **AND** the unit exits with code 0

#### Scenario: Credentials rejected

- **WHEN** the upload is refused for lack of permission
- **THEN** the failure is logged with the returned status
- **AND** the error counter is incremented

### Requirement: Configuration interface

The service SHALL expose the bucket and prefix as configuration options, so one module serves any account's evidence bucket.

#### Scenario: Prefix omitted

- **WHEN** evidence upload is enabled with a bucket but no prefix
- **THEN** a documented default prefix is used

#### Scenario: Options documented

- **WHEN** the module's options are read
- **THEN** each upload option carries a description stating its effect and any IAM requirement
### Requirement: Each daily record is uploaded under its own key

The service SHALL upload each sealed daily record to a key derived from the host and
the date, so a month of evidence can be listed and fetched without an index.

#### Scenario: Record uploaded

- **WHEN** a sealed record for `compute2-prod` dated `2026-08-31` is uploaded to bucket `example-evidence` with prefix `vulnerability`
- **THEN** it is at `s3://example-evidence/vulnerability/daily/compute2-prod/2026-08-31.json`

#### Scenario: A month can be listed

- **WHEN** a consumer lists the prefix for one host
- **THEN** every uploaded day for that host is enumerable by key alone

### Requirement: Re-uploading a record is harmless

The service SHALL skip a record whose key already exists rather than overwrite it,
so no state has to be kept about which records were already uploaded and a sealed
record can never be silently replaced.

#### Scenario: Record already uploaded

- **WHEN** a record is uploaded whose key already exists in the bucket
- **THEN** the upload is skipped and the run is not treated as failed

#### Scenario: No delete permission is required

- **WHEN** records are uploaded
- **THEN** only object creation is used, so the write-only policy remains sufficient
