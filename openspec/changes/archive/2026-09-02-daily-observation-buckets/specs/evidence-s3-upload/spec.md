## ADDED Requirements

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
