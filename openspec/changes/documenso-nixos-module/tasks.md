## 1. Module Structure Setup

- [x] 1.1 Create service module file at modules/nixos/services/service-documenso.nix
- [x] 1.2 Define module configuration options structure under elastinix.services.documenso namespace
- [x] 1.3 Add module imports to flake.nix if needed

## 2. Core Configuration Options

- [x] 2.1 Implement enable option and module assertions
- [x] 2.2 Implement publicUrl configuration option with validation
- [x] 2.3 Implement database configuration options (host, port, name, user, passwordFile)
- [x] 2.4 Implement SMTP configuration options (host, port, fromAddress, fromName, optional auth)
- [x] 2.5 Implement S3 storage configuration options (bucket, endpoint, region, credentialsFile)
- [x] 2.6 Implement jobs configuration options (provider, redis settings)
- [x] 2.7 Implement security secrets options (nextAuthSecretFile, encryptionKeyFile, encryptionSecondaryKeyFile)
- [x] 2.8 Implement signing certificate options (certificateFile, passphraseFile, autoGenerate)
- [x] 2.9 Implement optional features options (disableSignup, allowedSignupDomains, disableTelemetry)
- [x] 2.10 Implement optional OAuth configuration options
- [x] 2.11 Implement user, group, and image configuration options

## 3. Redis Integration

- [x] 3.1 Implement conditional Redis service enablement when jobs.provider = "bullmq"
- [x] 3.2 Configure Redis server settings (bind, port, persistence)
- [x] 3.3 Add Redis password support via jobs.redis.passwordFile
- [x] 3.4 Configure Redis AOF and RDB persistence settings
- [x] 3.5 Set Redis key prefix configuration

## 4. Environment Variable Generation

- [x] 4.1 Create environment file generation logic for /var/lib/documenso/.env
- [x] 4.2 Generate authentication environment variables (NEXTAUTH_SECRET, encryption keys)
- [x] 4.3 Generate URL environment variables (NEXT_PUBLIC_WEBAPP_URL, internal URL)
- [x] 4.4 Generate database connection URL from configuration with password file
- [x] 4.5 Generate SMTP environment variables
- [x] 4.6 Generate S3 storage environment variables with credentials from file
- [x] 4.7 Generate background jobs environment variables (provider, Redis URL)
- [x] 4.8 Generate certificate signing environment variables
- [x] 4.9 Generate optional feature flags environment variables
- [x] 4.10 Generate OAuth environment variables when configured
- [x] 4.11 Implement environment file permissions (0400, service user ownership)

## 5. Certificate Management

- [x] 5.1 Create ExecStartPre script for certificate auto-generation
- [x] 5.2 Implement OpenSSL commands for self-signed certificate generation
- [x] 5.3 Implement PKCS#12 bundle creation with passphrase
- [x] 5.4 Add certificate file existence check and validation
- [x] 5.5 Set proper certificate file permissions (0400) and ownership
- [x] 5.6 Add logging for certificate auto-generation with development warning
- [x] 5.7 Implement certificate contents support (base64 decode to file)

## 6. Systemd Service Configuration

- [x] 6.1 Create systemd service unit configuration
- [x] 6.2 Configure service dependencies (network.target, postgresql.service, conditional redis)
- [x] 6.3 Implement ExecStartPre for database migrations (npx prisma migrate deploy)
- [x] 6.4 Configure OCI container execution with Docker image
- [x] 6.5 Set working directory to /var/lib/documenso
- [x] 6.6 Configure environment file loading
- [x] 6.7 Apply systemd security hardening options (NoNewPrivileges, PrivateTmp, ProtectSystem, etc.)
- [x] 6.8 Configure restart behavior (Restart=always, RestartSec=10)
- [x] 6.9 Set service user and group
- [x] 6.10 Configure container volume mounts (certificate, state directory)
- [x] 6.11 Configure container port binding (3000:3000)
- [x] 6.12 Set appropriate service timeout values

## 7. User and Directory Management

- [x] 7.1 Create dedicated documenso system user and group
- [x] 7.2 Create state directory /var/lib/documenso with proper permissions
- [x] 7.3 Configure StateDirectory in systemd unit for automatic management

## 8. Testing and Validation

- [x] 8.1 Test module evaluation with nix build or nixos-rebuild dry-run
- [x] 8.2 Test with minimal configuration (local job provider)
- [x] 8.3 Test with BullMQ configuration (Redis auto-provisioning)
- [x] 8.4 Test certificate auto-generation
- [x] 8.5 Test environment variable generation with mock secret files
- [x] 8.6 Verify systemd service dependencies are correct
- [x] 8.7 Verify security hardening options are applied

## 9. Documentation

- [ ] 9.1 Create comprehensive service documentation at docs/services/documenso.md
- [ ] 9.2 Document all configuration options with examples
- [ ] 9.3 Create basic deployment example configuration
- [ ] 9.4 Create production deployment example with agenix
- [ ] 9.5 Document certificate management options and security considerations
- [ ] 9.6 Document Redis integration and job provider options
- [ ] 9.7 Document required external services (PostgreSQL, S3, SMTP)
- [ ] 9.8 Document upgrade procedure and migration behavior
- [ ] 9.9 Document health check endpoints and monitoring
- [ ] 9.10 Add troubleshooting section with common issues
- [ ] 9.11 Update docs/README.md to include documenso service link

## 10. Example Configurations

- [ ] 10.1 Create basic example configuration file
- [ ] 10.2 Create production example with external services
- [ ] 10.3 Create agenix integration example
- [ ] 10.4 Create reverse proxy (nginx/traefik) integration examples
