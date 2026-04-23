## ADDED Requirements

### Requirement: S3 storage configuration
The module SHALL configure S3-compatible storage for PDF documents.

#### Scenario: S3 enabled
- **WHEN** storage.type = "s3"
- **THEN** NEXT_PUBLIC_UPLOAD_TRANSPORT = "s3"

#### Scenario: S3 credentials from file
- **WHEN** storage.credentialsFile provided
- **THEN** AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY loaded from file

### Requirement: S3 credentials file format
The module SHALL support KEY=value format for credentials file.

#### Scenario: Credentials file sourced
- **WHEN** credentials file contains AWS_ACCESS_KEY_ID=... and AWS_SECRET_ACCESS_KEY=...
- **THEN** environment generation script sources file and exports variables
