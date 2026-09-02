# certificate-management Specification

## Purpose
TBD - created by archiving change nixos-documenso-service. Update Purpose after archive.

## Requirements

### Requirement: PDF signing certificate configuration
The module SHALL configure PKCS#12 certificate for PDF signing.

#### Scenario: User-provided certificate
- **WHEN** signing.certificateFile and signing.passphraseFile provided
- **THEN** certificate path and passphrase configured in environment

### Requirement: Certificate auto-generation
The module SHALL optionally generate self-signed certificate.

#### Scenario: Auto-generate enabled
- **WHEN** signing.autoGenerate = true and certificate doesn't exist
- **THEN** ExecStartPre generates certificate with OpenSSL before service starts

#### Scenario: Certificate permissions
- **WHEN** certificate is generated
- **THEN** file has mode 0400 and owned by documenso user
