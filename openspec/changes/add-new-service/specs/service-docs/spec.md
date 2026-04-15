## ADDED Requirements

### Requirement: Service documentation file
A documentation file SHALL be created at `docs/services/<service-name>.md` for every new service.

#### Scenario: Documentation file created
- **WHEN** a new service module is added
- **THEN** a corresponding `docs/services/<service-name>.md` file SHALL be created

### Requirement: Documentation content
The documentation file SHALL contain at minimum: a title and description of the service, an options table listing all exposed Elastinix options with their types and defaults, a configuration example, and a secrets setup section if the service uses secrets.

#### Scenario: Options table present
- **WHEN** the documentation is written
- **THEN** it SHALL include a markdown table with columns: Option, Type, Default, Description

#### Scenario: Configuration example present
- **WHEN** the documentation is written
- **THEN** it SHALL include at least one NixOS configuration example showing typical usage

#### Scenario: Secrets section present when applicable
- **WHEN** the service uses secrets (environment files, password files, API keys)
- **THEN** the documentation SHALL include a section showing how to set up secrets with agenix

### Requirement: Service index entry
The service SHALL be added to `docs/README.md` under the appropriate category section (Integration Services, Infrastructure Services, Monitoring Services, or Application Services).

#### Scenario: README index updated
- **WHEN** a new service is added
- **THEN** `docs/README.md` SHALL contain a new bullet entry linking to the service documentation with a brief description
