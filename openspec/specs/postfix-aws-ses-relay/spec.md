# Spec: postfix-aws-ses-relay

## Purpose

A NixOS service module that configures Postfix as a mail relay through AWS Simple Email Service (SES). The module provides SASL authentication via agenix-encrypted credentials, trusted network security, sender address rewriting, local mail forwarding, SES compliance settings (rate limiting and message size), bounce handling, and TLS enforcement.

## Requirements

### Requirement: Service Enable Option
The service module SHALL provide an `enable` option under the `elastinix.services.postfix-relay-aws` namespace.

#### Scenario: Service disabled by default
- **WHEN** no configuration is set
- **THEN** the Postfix relay service SHALL NOT be enabled

#### Scenario: Service enabled
- **WHEN** `elastinix.services.postfix-relay-aws.enable` is set to `true`
- **THEN** the native NixOS `services.postfix` module SHALL be configured for AWS SES relay

### Requirement: AWS SES Connection Configuration
The service module SHALL provide options to configure the AWS SES SMTP endpoint connection.

#### Scenario: Configure SES endpoint
- **WHEN** user sets `sesEndpoint` to "email-smtp.eu-west-1.amazonaws.com"
- **THEN** Postfix SHALL relay all mail through that endpoint

#### Scenario: Configure SES port
- **WHEN** user sets `sesPort` to 587
- **THEN** Postfix SHALL connect to port 587 with STARTTLS

#### Scenario: Default port is 587
- **WHEN** no `sesPort` is specified
- **THEN** Postfix SHALL use port 587 (STARTTLS)

### Requirement: SASL Authentication with Agenix
The service module SHALL authenticate to AWS SES using SASL credentials from an agenix-encrypted file.

#### Scenario: Credentials file path
- **WHEN** user sets `credentialsFile` to an agenix secret path
- **THEN** the service SHALL read SASL credentials from that file

#### Scenario: Credentials file format
- **WHEN** credentials file contains format "[host]:port username:password"
- **THEN** Postfix SHALL parse and use these credentials for SASL authentication

#### Scenario: Credentials hashing
- **WHEN** service starts
- **THEN** credentials SHALL be hashed with `postmap` to create `/var/lib/postfix/sasl_passwd.db`

#### Scenario: Credentials file permissions
- **WHEN** credentials are processed
- **THEN** both plaintext and hashed files SHALL be owned by postfix:postfix with mode 600

### Requirement: Network Security with Trusted Subnets
The service module SHALL restrict mail relay to configured trusted networks using Postfix `mynetworks`.

#### Scenario: Configure trusted networks
- **WHEN** user sets `trustedNetworks` to ["10.0.0.0/16", "127.0.0.0/8"]
- **THEN** Postfix SHALL only accept mail from hosts in those networks

#### Scenario: Default trusted networks
- **WHEN** no `trustedNetworks` is specified
- **THEN** Postfix SHALL default to ["127.0.0.0/8", "::1/128"] (localhost only)

#### Scenario: Reject untrusted sources
- **WHEN** mail arrives from an IP not in `trustedNetworks`
- **THEN** Postfix SHALL reject the connection

### Requirement: Sender Address Rewriting
The service module SHALL rewrite sender (FROM) addresses to AWS SES-verified addresses.

#### Scenario: Default sender address
- **WHEN** user sets `defaultSenderAddress` to "noreply@example.com"
- **THEN** any mail without a proper domain SHALL be rewritten to that address

#### Scenario: Per-user sender mappings
- **WHEN** user configures `senderMaps = { "root@" = "sysadmin@example.com"; }`
- **THEN** mail from "root@any-host" SHALL be rewritten to "sysadmin@example.com"

#### Scenario: No rewriting for verified domains
- **WHEN** mail already has FROM address in a verified domain
- **THEN** sender address SHALL NOT be rewritten

#### Scenario: Sender mapping generation
- **WHEN** service is configured
- **THEN** sender maps SHALL be written to `/var/lib/postfix/generic` and hashed

### Requirement: Local Mail Forwarding
The service module SHALL forward local system mail to a configured email address.

#### Scenario: Root alias configuration
- **WHEN** user sets `rootAlias` to "sysadmin@example.com"
- **THEN** all mail to root@, postmaster@, and mailer-daemon@ SHALL be forwarded to that address

#### Scenario: Alias file generation
- **WHEN** service is configured
- **THEN** aliases SHALL be written to `/var/lib/postfix/aliases` and hashed with `postalias`

### Requirement: SES Compliance - Message Size Limit
The service module SHALL enforce AWS SES message size limits.

#### Scenario: Default 10MB limit
- **WHEN** no `messageSizeLimit` is specified
- **THEN** Postfix SHALL set `message_size_limit` to 10485760 bytes (10MB)

#### Scenario: Custom size limit
- **WHEN** user sets `messageSizeLimit` to a custom value
- **THEN** Postfix SHALL enforce that limit

#### Scenario: Reject oversized messages
- **WHEN** mail exceeds `messageSizeLimit`
- **THEN** Postfix SHALL reject the message before sending to SES

### Requirement: SES Compliance - Rate Limiting
The service module SHALL configure Postfix rate limiting for AWS SES compatibility.

#### Scenario: Destination concurrency limit
- **WHEN** service is enabled
- **THEN** Postfix SHALL set `default_destination_concurrency_limit` to 2

#### Scenario: Rate delay
- **WHEN** service is enabled
- **THEN** Postfix SHALL set `default_destination_rate_delay` to "1s"

### Requirement: Bounce and Error Handling
The service module SHALL forward bounce and error messages to the configured root alias.

#### Scenario: Bounce notices
- **WHEN** SES returns a bounce
- **THEN** bounce notice SHALL be sent to `rootAlias`

#### Scenario: Double-bounce notices
- **WHEN** a bounce message itself bounces
- **THEN** double-bounce notice SHALL be sent to `rootAlias`

#### Scenario: Error notices
- **WHEN** mail delivery encounters an error
- **THEN** error notice SHALL be sent to `rootAlias`

### Requirement: TLS Encryption
The service module SHALL enforce TLS encryption for connections to AWS SES.

#### Scenario: TLS enabled
- **WHEN** service is configured
- **THEN** Postfix SHALL set `smtp_use_tls` to "yes"

#### Scenario: TLS security level
- **WHEN** service is configured
- **THEN** Postfix SHALL set `smtp_tls_security_level` to "encrypt"

#### Scenario: STARTTLS detection
- **WHEN** service is configured
- **THEN** Postfix SHALL log STARTTLS offers with `smtp_tls_note_starttls_offer`

### Requirement: Systemd Security Hardening
The service module SHALL NOT add additional systemd security hardening beyond what native NixOS Postfix provides.

#### Scenario: Use native Postfix service
- **WHEN** service is enabled
- **THEN** the native `services.postfix` systemd service SHALL be used without modification

### Requirement: SASL Credentials Setup Service
The service module SHALL create a systemd oneshot service to prepare SASL credentials before Postfix starts.

#### Scenario: Credentials setup runs before Postfix
- **WHEN** system boots
- **THEN** `postfix-setup-sasl.service` SHALL run before `postfix.service`

#### Scenario: Credentials file installation
- **WHEN** setup service runs
- **THEN** credentials file SHALL be copied to `/var/lib/postfix/sasl_passwd`

#### Scenario: Credentials hashing in setup
- **WHEN** setup service runs
- **THEN** `postmap` SHALL generate `/var/lib/postfix/sasl_passwd.db`

#### Scenario: Setup service is oneshot
- **WHEN** setup service completes
- **THEN** it SHALL remain in "active" state (RemainAfterExit=true)
