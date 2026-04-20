## ADDED Requirements

### Requirement: Systemd security hardening applied
The module SHALL apply systemd security directives to restrict service capabilities.

#### Scenario: Security directives configured
- **WHEN** service unit is created
- **THEN** NoNewPrivileges, PrivateTmp, ProtectSystem=strict, ProtectHome are set

#### Scenario: State directory writable
- **WHEN** ProtectSystem=strict applied
- **THEN** ReadWritePaths includes /var/lib/documenso

### Requirement: Service runs as dedicated user
The module SHALL create and use dedicated documenso user.

#### Scenario: Non-root execution
- **WHEN** service starts
- **THEN** process runs as documenso user, not root

#### Scenario: User auto-creation
- **WHEN** module enabled
- **THEN** documenso user and group created automatically
