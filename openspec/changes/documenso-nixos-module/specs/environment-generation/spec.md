## ADDED Requirements

### Requirement: Environment file generation
The service SHALL generate a complete .env file at /var/lib/documenso/.env with all required environment variables.

#### Scenario: Environment file created on service start
- **WHEN** service is enabled and configuration is provided
- **THEN** system SHALL generate /var/lib/documenso/.env before starting Documenso

#### Scenario: Environment file permissions
- **WHEN** environment file is generated
- **THEN** system SHALL set file permissions to 0400 and owner to service user

### Requirement: Authentication environment variables
The service SHALL generate authentication and encryption environment variables from secret files.

#### Scenario: NextAuth secret variable
- **WHEN** secrets.nextAuthSecretFile is provided
- **THEN** system SHALL read secret and set NEXTAUTH_SECRET environment variable

#### Scenario: Encryption keys
- **WHEN** secrets.encryptionKeyFile and secrets.encryptionSecondaryKeyFile are provided
- **THEN** system SHALL set NEXT_PRIVATE_ENCRYPTION_KEY and NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY variables

### Requirement: URL environment variables
The service SHALL generate public and internal URL environment variables.

#### Scenario: Public URL variable
- **WHEN** publicUrl = "https://documenso.example.com"
- **THEN** system SHALL set NEXT_PUBLIC_WEBAPP_URL to specified URL

#### Scenario: Internal URL variable
- **WHEN** service is configured
- **THEN** system SHALL set NEXT_PRIVATE_INTERNAL_WEBAPP_URL to "http://127.0.0.1:3000"

### Requirement: Database environment variables
The service SHALL generate PostgreSQL connection URL from database configuration.

#### Scenario: Database URL generation
- **WHEN** database configuration is provided
- **THEN** system SHALL generate NEXT_PRIVATE_DATABASE_URL as "postgresql://user:password@host:port/database"

#### Scenario: Direct database URL
- **WHEN** database URL is generated
- **THEN** system SHALL also set NEXT_PRIVATE_DIRECT_DATABASE_URL to same value (no connection pooler)

#### Scenario: Database password from file
- **WHEN** database.passwordFile contains password
- **THEN** system SHALL read password and include in connection URL

### Requirement: SMTP environment variables
The service SHALL generate SMTP configuration environment variables.

#### Scenario: SMTP transport settings
- **WHEN** smtp configuration is provided
- **THEN** system SHALL set NEXT_PRIVATE_SMTP_TRANSPORT = "smtp-auth"

#### Scenario: SMTP connection variables
- **WHEN** smtp.host, smtp.port, smtp.fromName, and smtp.fromAddress are provided
- **THEN** system SHALL set corresponding NEXT_PRIVATE_SMTP_* environment variables

#### Scenario: SMTP authentication
- **WHEN** smtp.username and smtp.passwordFile are provided
- **THEN** system SHALL set NEXT_PRIVATE_SMTP_USERNAME and NEXT_PRIVATE_SMTP_PASSWORD variables

### Requirement: S3 storage environment variables
The service SHALL generate S3 storage configuration environment variables.

#### Scenario: Upload transport type
- **WHEN** storage.type = "s3"
- **THEN** system SHALL set NEXT_PUBLIC_UPLOAD_TRANSPORT = "s3"

#### Scenario: S3 connection variables
- **WHEN** storage configuration is provided
- **THEN** system SHALL set NEXT_PRIVATE_UPLOAD_ENDPOINT, NEXT_PRIVATE_UPLOAD_REGION, and NEXT_PRIVATE_UPLOAD_BUCKET

#### Scenario: S3 credentials from file
- **WHEN** storage.credentialsFile contains AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
- **THEN** system SHALL read credentials and set NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID and NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY

### Requirement: Background jobs environment variables
The service SHALL generate job provider configuration environment variables.

#### Scenario: BullMQ job provider
- **WHEN** jobs.provider = "bullmq"
- **THEN** system SHALL set NEXT_PRIVATE_JOBS_PROVIDER = "bullmq"

#### Scenario: Redis connection URL
- **WHEN** jobs.provider = "bullmq"
- **THEN** system SHALL generate NEXT_PRIVATE_REDIS_URL from jobs.redis.host and jobs.redis.port

#### Scenario: Redis password in URL
- **WHEN** jobs.redis.passwordFile is provided
- **THEN** system SHALL include password in Redis URL as "redis://:password@host:port"

#### Scenario: Redis key prefix
- **WHEN** jobs.redis.prefix is configured
- **THEN** system SHALL set NEXT_PRIVATE_REDIS_PREFIX environment variable

### Requirement: Certificate signing environment variables
The service SHALL generate PDF signing configuration environment variables.

#### Scenario: Signing passphrase
- **WHEN** signing.passphraseFile is provided
- **THEN** system SHALL read passphrase and set NEXT_PRIVATE_SIGNING_PASSPHRASE

#### Scenario: Signing certificate path
- **WHEN** signing.certificateFile is provided
- **THEN** system SHALL set NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH to certificate path

### Requirement: Optional feature environment variables
The service SHALL generate feature flag environment variables when configured.

#### Scenario: Disable signup feature
- **WHEN** features.disableSignup = true
- **THEN** system SHALL set NEXT_PUBLIC_DISABLE_SIGNUP = "true"

#### Scenario: Allowed signup domains
- **WHEN** features.allowedSignupDomains is provided
- **THEN** system SHALL set NEXT_PRIVATE_ALLOWED_SIGNUP_DOMAINS as comma-separated list

#### Scenario: Disable telemetry
- **WHEN** features.disableTelemetry = true
- **THEN** system SHALL set DOCUMENSO_DISABLE_TELEMETRY = "true"

### Requirement: OAuth environment variables
The service SHALL generate OAuth provider environment variables when configured.

#### Scenario: Google OAuth variables
- **WHEN** oauth.google.clientId and oauth.google.clientSecretFile are provided
- **THEN** system SHALL set NEXT_PRIVATE_GOOGLE_CLIENT_ID and NEXT_PRIVATE_GOOGLE_CLIENT_SECRET

### Requirement: Environment variable validation
The service SHALL validate all required environment variables are set before starting.

#### Scenario: Missing required variable
- **WHEN** required environment variable cannot be generated
- **THEN** system SHALL fail with clear error indicating which variable is missing

#### Scenario: Secret file not readable
- **WHEN** secret file path is invalid or not readable
- **THEN** system SHALL fail with error indicating which secret file has issues
