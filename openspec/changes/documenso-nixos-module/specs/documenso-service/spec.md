## ADDED Requirements

### Requirement: Service namespace and enable option
The service SHALL be available under the `elastinix.services.documenso` namespace and SHALL provide a top-level `enable` boolean option.

#### Scenario: Service enabled
- **WHEN** user sets `elastinix.services.documenso.enable = true`
- **THEN** the Documenso service is activated and started on system boot

#### Scenario: Service disabled by default
- **WHEN** user does not configure the service
- **THEN** the Documenso service SHALL NOT be enabled or started

### Requirement: Public URL configuration
The service SHALL require a public URL configuration that defines where Documenso is accessible.

#### Scenario: Public URL configured
- **WHEN** user sets `publicUrl = "https://documenso.example.com"`
- **THEN** the service SHALL use this URL for all external references and redirects

#### Scenario: Missing public URL
- **WHEN** user enables service without setting publicUrl
- **THEN** system SHALL fail evaluation with a clear error message

### Requirement: Database configuration
The service SHALL support external PostgreSQL database configuration with connection parameters and password file.

#### Scenario: Complete database configuration
- **WHEN** user provides database host, port, name, user, and passwordFile
- **THEN** the service SHALL connect to the specified PostgreSQL database

#### Scenario: Database connection string generation
- **WHEN** database configuration is provided
- **THEN** system SHALL generate proper PostgreSQL connection URL with credentials from passwordFile

#### Scenario: Default database port
- **WHEN** user omits database.port configuration
- **THEN** system SHALL use port 5432 as default

### Requirement: SMTP configuration
The service SHALL support SMTP configuration for sending email notifications.

#### Scenario: Basic SMTP configuration
- **WHEN** user provides smtp.host, smtp.port, smtp.fromAddress, and smtp.fromName
- **THEN** the service SHALL send emails through the specified SMTP server

#### Scenario: SMTP with authentication
- **WHEN** user provides optional smtp.username and smtp.passwordFile
- **THEN** the service SHALL authenticate with SMTP server using provided credentials

#### Scenario: Default SMTP relay
- **WHEN** user sets smtp.host = "localhost" and smtp.port = 25
- **THEN** the service SHALL use local Postfix relay (typical AWS SES setup)

### Requirement: S3 storage configuration
The service SHALL support S3-compatible storage for document management.

#### Scenario: S3 configuration
- **WHEN** user provides storage.bucket, storage.endpoint, storage.region, and storage.credentialsFile
- **THEN** the service SHALL store all PDFs in the specified S3 bucket

#### Scenario: S3 credentials from file
- **WHEN** storage.credentialsFile contains AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
- **THEN** the service SHALL read and use these credentials for S3 access

#### Scenario: MinIO compatibility
- **WHEN** user sets storage.endpoint to MinIO server URL
- **THEN** the service SHALL work with S3-compatible MinIO storage

### Requirement: Background job provider selection
The service SHALL support multiple job providers for background task processing.

#### Scenario: BullMQ job provider
- **WHEN** user sets jobs.provider = "bullmq"
- **THEN** the service SHALL use Redis-based BullMQ for job processing

#### Scenario: Local job provider
- **WHEN** user sets jobs.provider = "local"
- **THEN** the service SHALL use PostgreSQL-based job processing without Redis

### Requirement: Security secrets configuration
The service SHALL require three security-related secret files for authentication and encryption.

#### Scenario: Required security secrets
- **WHEN** user enables the service
- **THEN** system SHALL require secrets.nextAuthSecretFile, secrets.encryptionKeyFile, and secrets.encryptionSecondaryKeyFile

#### Scenario: Missing security secrets
- **WHEN** user enables service without providing all required secret files
- **THEN** system SHALL fail evaluation with clear error indicating which secrets are missing

### Requirement: Optional feature flags
The service SHALL support optional feature configuration for signup control and telemetry.

#### Scenario: Disable signup
- **WHEN** user sets features.disableSignup = true
- **THEN** the service SHALL prevent new user registrations

#### Scenario: Domain-restricted signup
- **WHEN** user provides features.allowedSignupDomains = ["example.com"]
- **THEN** the service SHALL only allow signups from specified email domains

#### Scenario: Disable telemetry
- **WHEN** user sets features.disableTelemetry = true
- **THEN** the service SHALL NOT send usage data to Documenso telemetry servers

### Requirement: Optional OAuth configuration
The service SHALL support optional OAuth provider configuration for authentication.

#### Scenario: Google OAuth configuration
- **WHEN** user provides oauth.google.clientId and oauth.google.clientSecretFile
- **THEN** the service SHALL enable Google OAuth authentication

#### Scenario: OAuth disabled by default
- **WHEN** user does not configure OAuth providers
- **THEN** the service SHALL use email/password authentication only

### Requirement: Docker image configuration
The service SHALL support specifying the Documenso Docker image and tag.

#### Scenario: Default Docker image
- **WHEN** user does not specify custom image
- **THEN** the service SHALL use "documenso/documenso:latest" as default

#### Scenario: Custom Docker image
- **WHEN** user sets image = "documenso/documenso:1.5.0"
- **THEN** the service SHALL use the specified image version

### Requirement: User and group configuration
The service SHALL run under a dedicated non-root user with configurable user and group.

#### Scenario: Default service user
- **WHEN** user does not specify custom user/group
- **THEN** the service SHALL create and use "documenso" user and group

#### Scenario: Custom service user
- **WHEN** user sets user = "custom-user" and group = "custom-group"
- **THEN** the service SHALL run as the specified user and group
