## ADDED Requirements

### Requirement: Automatic Redis provisioning
The service SHALL automatically enable and configure Redis when BullMQ job provider is selected.

#### Scenario: Redis enabled with BullMQ
- **WHEN** user sets jobs.provider = "bullmq"
- **THEN** system SHALL automatically enable services.redis.servers.documenso

#### Scenario: Redis not enabled with local provider
- **WHEN** user sets jobs.provider = "local"
- **THEN** system SHALL NOT enable Redis service

### Requirement: Redis connection configuration
The service SHALL support configurable Redis connection parameters for BullMQ integration.

#### Scenario: Default Redis connection
- **WHEN** user does not specify redis configuration
- **THEN** system SHALL use host = "127.0.0.1" and port = 6379 as defaults

#### Scenario: Custom Redis host and port
- **WHEN** user sets jobs.redis.host = "redis.internal" and jobs.redis.port = 6380
- **THEN** the service SHALL connect to Redis at the specified host and port

### Requirement: Redis security configuration
The service SHALL support optional Redis password protection.

#### Scenario: Redis without password
- **WHEN** user does not provide jobs.redis.passwordFile
- **THEN** Redis SHALL run without authentication (localhost-only binding)

#### Scenario: Redis with password
- **WHEN** user provides jobs.redis.passwordFile
- **THEN** Redis SHALL require authentication and Documenso SHALL use provided password

### Requirement: Redis persistence configuration
The service SHALL configure Redis with persistence for job queue durability.

#### Scenario: Redis AOF persistence
- **WHEN** Redis is automatically provisioned
- **THEN** system SHALL enable Append-Only File (AOF) persistence with appendfsync = "everysec"

#### Scenario: Redis RDB snapshots
- **WHEN** Redis is automatically provisioned
- **THEN** system SHALL configure periodic RDB snapshots for backup

### Requirement: Redis network binding
The service SHALL configure Redis to bind only to localhost for security.

#### Scenario: Localhost-only binding
- **WHEN** Redis is automatically provisioned
- **THEN** Redis SHALL bind only to 127.0.0.1 and SHALL NOT be accessible from network

### Requirement: Redis job queue prefix
The service SHALL support configurable Redis key prefix for job queue isolation.

#### Scenario: Default Redis prefix
- **WHEN** user does not specify jobs.redis.prefix
- **THEN** system SHALL use "documenso" as default key prefix

#### Scenario: Custom Redis prefix
- **WHEN** user sets jobs.redis.prefix = "documenso-prod"
- **THEN** the service SHALL use specified prefix for all Redis keys

### Requirement: Redis service dependency
The service SHALL declare proper systemd dependency on Redis service when BullMQ is used.

#### Scenario: Systemd Redis dependency
- **WHEN** jobs.provider = "bullmq"
- **THEN** documenso.service SHALL have After=redis-documenso.service and Requires=redis-documenso.service

#### Scenario: No Redis dependency with local provider
- **WHEN** jobs.provider = "local"
- **THEN** documenso.service SHALL NOT depend on Redis service
