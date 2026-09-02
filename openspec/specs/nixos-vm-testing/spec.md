# nixos-vm-testing Specification

## Purpose
TBD - created by archiving change nixos-documenso-service. Update Purpose after archive.

## Requirements

### Requirement: NixOS VM test validates module
The module SHALL include automated VM test in modules/nixos/tests/documenso.nix.

#### Scenario: Test suite execution
- **WHEN** nix-build nixos-module-test.nix runs
- **THEN** VM boots with Documenso service configured

#### Scenario: Health endpoints tested
- **WHEN** service starts in test VM
- **THEN** /api/health and /api/certificate-status return 200 OK

### Requirement: Test coverage includes key scenarios
The test SHALL verify critical functionality.

#### Scenario: Environment file created
- **WHEN** test runs
- **THEN** /var/lib/documenso/.env exists with mode 0600

#### Scenario: Certificate auto-generated
- **WHEN** signing.autoGenerate = true in test
- **THEN** /var/lib/documenso/cert.p12 exists with mode 0400

#### Scenario: Database migrations executed
- **WHEN** test runs
- **THEN** _prisma_migrations table exists in PostgreSQL

#### Scenario: Redis configured correctly
- **WHEN** BullMQ enabled
- **THEN** Redis responds to PING and has appendonly=yes
