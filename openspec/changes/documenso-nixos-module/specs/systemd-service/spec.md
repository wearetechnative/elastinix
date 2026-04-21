## ADDED Requirements

### Requirement: Systemd service unit
The service SHALL create a systemd service unit named documenso.service.

#### Scenario: Service unit created
- **WHEN** elastinix.services.documenso.enable = true
- **THEN** system SHALL create systemd unit file for documenso.service

#### Scenario: Service enabled on boot
- **WHEN** service is configured
- **THEN** documenso.service SHALL be enabled to start on system boot

### Requirement: Service dependencies
The service SHALL declare proper systemd dependencies on required services.

#### Scenario: PostgreSQL dependency
- **WHEN** service is configured
- **THEN** documenso.service SHALL have After=postgresql.service dependency

#### Scenario: Network dependency
- **WHEN** service is configured
- **THEN** documenso.service SHALL have After=network.target dependency

#### Scenario: Redis dependency with BullMQ
- **WHEN** jobs.provider = "bullmq"
- **THEN** documenso.service SHALL have After=redis-documenso.service and Requires=redis-documenso.service

### Requirement: Database migration execution
The service SHALL run database migrations before starting the application.

#### Scenario: Migration in ExecStartPre
- **WHEN** service starts
- **THEN** system SHALL execute "npx prisma migrate deploy" in ExecStartPre

#### Scenario: Migration working directory
- **WHEN** migrations run
- **THEN** system SHALL use /var/lib/documenso as working directory

#### Scenario: Migration failure stops service
- **WHEN** database migration fails
- **THEN** service SHALL NOT start and SHALL report error to journald

### Requirement: Application startup
The service SHALL start the Documenso application server using Docker container.

#### Scenario: Docker container execution
- **WHEN** service starts application
- **THEN** system SHALL run OCI container with specified Docker image

#### Scenario: Container port binding
- **WHEN** container starts
- **THEN** system SHALL bind container port 3000 to host port 3000

#### Scenario: Container environment
- **WHEN** container starts
- **THEN** system SHALL load environment variables from /var/lib/documenso/.env

### Requirement: Service user and permissions
The service SHALL run as dedicated non-root user with proper working directory.

#### Scenario: Service user
- **WHEN** service is configured
- **THEN** system SHALL create and use dedicated "documenso" user and group

#### Scenario: Working directory
- **WHEN** service starts
- **THEN** system SHALL use /var/lib/documenso as WorkingDirectory

#### Scenario: Working directory permissions
- **WHEN** system creates working directory
- **THEN** system SHALL set owner to service user with mode 0700

### Requirement: Security hardening
The service SHALL apply systemd security hardening options.

#### Scenario: Basic security options
- **WHEN** service is configured
- **THEN** system SHALL set NoNewPrivileges=true, PrivateTmp=true, ProtectSystem=strict, and ProtectHome=true

#### Scenario: File system isolation
- **WHEN** service runs
- **THEN** system SHALL use ReadWritePaths=/var/lib/documenso to limit write access

#### Scenario: Network restrictions
- **WHEN** service runs
- **THEN** system SHALL set RestrictAddressFamilies to AF_INET and AF_INET6 only

#### Scenario: Capability restrictions
- **WHEN** service runs
- **THEN** system SHALL limit capabilities to minimum required set

### Requirement: Service restart behavior
The service SHALL automatically restart on failure with backoff.

#### Scenario: Automatic restart
- **WHEN** service crashes or exits with error
- **THEN** system SHALL automatically restart the service

#### Scenario: Restart delay
- **WHEN** service restarts
- **THEN** system SHALL wait 10 seconds before attempting restart (RestartSec=10)

#### Scenario: Restart policy
- **WHEN** service is configured
- **THEN** system SHALL use Restart=always policy

### Requirement: Service logging
The service SHALL log all output to systemd journal.

#### Scenario: Stdout to journal
- **WHEN** service produces output
- **THEN** system SHALL send stdout to journald

#### Scenario: Stderr to journal
- **WHEN** service produces errors
- **THEN** system SHALL send stderr to journald

#### Scenario: Structured logging
- **WHEN** service logs to journal
- **THEN** logs SHALL include service identifier and unit name

### Requirement: Health check integration
The service SHALL support health check monitoring.

#### Scenario: Health check endpoint available
- **WHEN** service is running
- **THEN** application SHALL provide /api/health endpoint on port 3000

#### Scenario: Health check timeout
- **WHEN** performing health check
- **THEN** system SHALL allow reasonable timeout for response

### Requirement: Service lifecycle management
The service SHALL support standard systemctl operations.

#### Scenario: Service start
- **WHEN** user runs "systemctl start documenso.service"
- **THEN** system SHALL start service with migrations and application

#### Scenario: Service stop
- **WHEN** user runs "systemctl stop documenso.service"
- **THEN** system SHALL gracefully stop container and service

#### Scenario: Service restart
- **WHEN** user runs "systemctl restart documenso.service"
- **THEN** system SHALL stop service, run migrations, and start again

#### Scenario: Service status
- **WHEN** user runs "systemctl status documenso.service"
- **THEN** system SHALL display current service state and recent logs

### Requirement: State directory management
The service SHALL automatically create and manage state directory.

#### Scenario: State directory creation
- **WHEN** service is enabled
- **THEN** system SHALL create /var/lib/documenso with proper ownership

#### Scenario: State directory persistence
- **WHEN** service is stopped or restarted
- **THEN** system SHALL preserve state directory contents

### Requirement: Volume mounts for container
The service SHALL mount required directories into Docker container.

#### Scenario: Certificate mount
- **WHEN** container starts
- **THEN** system SHALL mount certificate file into container as read-only

#### Scenario: Data directory mount
- **WHEN** container starts
- **THEN** system SHALL mount /var/lib/documenso to container's data directory

### Requirement: Service timeout configuration
The service SHALL configure appropriate timeouts for startup and shutdown.

#### Scenario: Startup timeout
- **WHEN** service starts
- **THEN** system SHALL allow sufficient time for migration and application startup

#### Scenario: Shutdown timeout
- **WHEN** service stops
- **THEN** system SHALL allow graceful shutdown before forcing termination

### Requirement: Systemd service type
The service SHALL use appropriate systemd service type for container execution.

#### Scenario: Service type
- **WHEN** service is configured
- **THEN** system SHALL use Type=simple or Type=notify as appropriate

#### Scenario: Service remains active
- **WHEN** application is running
- **THEN** systemd SHALL consider service active and healthy
