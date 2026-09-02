# database-integration Specification

## Purpose
TBD - created by archiving change nixos-documenso-service. Update Purpose after archive.

## Requirements

### Requirement: Module connects to external PostgreSQL
The module SHALL support external PostgreSQL database without bundling database service.

#### Scenario: External database connection
- **WHEN** user provides database.host, database.passwordFile
- **THEN** module connects to external database

#### Scenario: Connection string generation
- **WHEN** database config provided
- **THEN** NEXT_PRIVATE_DATABASE_URL and NEXT_PRIVATE_DIRECT_DATABASE_URL are generated

### Requirement: Automatic database migrations on startup
The module SHALL run Prisma migrations before starting application.

#### Scenario: Migrations via package wrapper
- **WHEN** systemd starts documenso service
- **THEN** pkgs.documenso wrapper runs `prisma migrate deploy` automatically

#### Scenario: Migration failure prevents startup
- **WHEN** migrations fail
- **THEN** service does not start and error is logged

### Requirement: Password loaded from file
The module SHALL read database password from file at runtime.

#### Scenario: Password from agenix
- **WHEN** database.passwordFile points to agenix secret
- **THEN** password is read and used in connection string
