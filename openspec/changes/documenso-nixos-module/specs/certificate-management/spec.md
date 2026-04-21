## ADDED Requirements

### Requirement: Certificate file path configuration
The service SHALL support configuring the path to PDF signing certificate file.

#### Scenario: Default certificate path
- **WHEN** user does not specify signing.certificateFile
- **THEN** system SHALL use /var/lib/documenso/cert.p12 as default path

#### Scenario: Custom certificate path
- **WHEN** user sets signing.certificateFile = "/opt/documenso/custom-cert.p12"
- **THEN** the service SHALL use the specified certificate path

### Requirement: Certificate passphrase configuration
The service SHALL require a passphrase file for certificate encryption.

#### Scenario: Certificate passphrase required
- **WHEN** user enables the service
- **THEN** system SHALL require signing.passphraseFile to be configured

#### Scenario: Missing certificate passphrase
- **WHEN** user enables service without signing.passphraseFile
- **THEN** system SHALL fail evaluation with error message

### Requirement: Certificate auto-generation
The service SHALL support automatic generation of self-signed certificates for development and testing.

#### Scenario: Auto-generation enabled
- **WHEN** user sets signing.autoGenerate = true and certificate file does not exist
- **THEN** system SHALL generate self-signed certificate before service starts

#### Scenario: Auto-generation disabled
- **WHEN** user does not set signing.autoGenerate or sets it to false
- **THEN** system SHALL NOT generate certificate and SHALL fail if file is missing

#### Scenario: Existing certificate preserved
- **WHEN** signing.autoGenerate = true and certificate file already exists
- **THEN** system SHALL NOT overwrite existing certificate

### Requirement: Self-signed certificate generation process
The service SHALL generate self-signed certificates using OpenSSL with proper parameters.

#### Scenario: Certificate generation with OpenSSL
- **WHEN** auto-generating certificate
- **THEN** system SHALL use OpenSSL to create RSA 2048-bit key and X.509 certificate valid for 365 days

#### Scenario: Certificate PKCS#12 format
- **WHEN** auto-generating certificate
- **THEN** system SHALL create PKCS#12 (.p12) bundle containing private key and certificate

#### Scenario: Certificate passphrase application
- **WHEN** auto-generating certificate
- **THEN** system SHALL encrypt PKCS#12 bundle with passphrase from signing.passphraseFile

### Requirement: Certificate file permissions
The service SHALL set secure file permissions on certificate files.

#### Scenario: Certificate file ownership
- **WHEN** certificate is generated or service starts
- **THEN** system SHALL set certificate file owner to service user (documenso)

#### Scenario: Certificate file permissions
- **WHEN** certificate is generated or service starts
- **THEN** system SHALL set certificate file permissions to 0400 (read-only for owner)

### Requirement: Certificate generation logging
The service SHALL log certificate generation activities for auditing.

#### Scenario: Auto-generation logged
- **WHEN** certificate is auto-generated
- **THEN** system SHALL log warning message indicating self-signed certificate is for development only

#### Scenario: Certificate generation failure
- **WHEN** certificate auto-generation fails
- **THEN** system SHALL log error and fail service startup

### Requirement: Certificate validation
The service SHALL validate certificate file exists and is readable before starting application.

#### Scenario: Certificate file missing
- **WHEN** certificate file does not exist and autoGenerate = false
- **THEN** system SHALL fail service startup with clear error message

#### Scenario: Certificate file unreadable
- **WHEN** certificate file exists but is not readable by service user
- **THEN** system SHALL fail service startup with permission error

### Requirement: Certificate subject configuration
The service SHALL support configuring certificate subject fields for auto-generated certificates.

#### Scenario: Default certificate subject
- **WHEN** user does not specify certificate subject fields
- **THEN** system SHALL use CN=<hostname> as default subject

#### Scenario: Custom certificate subject
- **WHEN** user provides signing.subject.country, signing.subject.organization, etc.
- **THEN** system SHALL use specified values in generated certificate subject

### Requirement: Certificate contents alternative
The service SHALL support providing certificate contents directly instead of file path.

#### Scenario: Base64 certificate contents
- **WHEN** user sets signing.certificateContents with base64-encoded PKCS#12 data
- **THEN** system SHALL decode and write certificate to signing.certificateFile path

#### Scenario: Certificate contents takes precedence
- **WHEN** both signing.certificateFile and signing.certificateContents are provided
- **THEN** system SHALL use certificateContents and write to certificateFile path
