## ADDED Requirements

### Requirement: Optional HASP profile exposure
The hostinfo service SHALL expose `hasp.json` when the HASP module is enabled, as
a symlink into the system closure, and `hasp-aws.json` when fact collection is
enabled, as a symlink to the collector's state directory.

#### Scenario: Profile served from the closure
- **WHEN** `elastinix.hasp.enable` is true and the hostinfo server is running
- **THEN** `hasp.json` is retrievable over the configured port
- **AND** the served path is a symlink into `/nix/store`

#### Scenario: Collected facts served from state
- **WHEN** fact collection is enabled
- **THEN** `hasp-aws.json` is retrievable over the configured port once the first collection has succeeded

#### Scenario: Not served when disabled
- **WHEN** the HASP module is disabled
- **THEN** neither document is present in the served directory

#### Scenario: Collection disabled leaves only the profile
- **WHEN** the module is enabled but collection is `none`
- **THEN** `hasp.json` is served and `hasp-aws.json` is not

### Requirement: Optional runtime facts exposure
The hostinfo service SHALL expose the observed runtime facts document when socket
observation is enabled.

#### Scenario: Runtime facts served
- **WHEN** socket observation is enabled
- **THEN** `runtime-facts.json` is retrievable over the configured port

### Requirement: Served documents are readable by the server user
Every document placed in the served directory MUST be readable by the unprivileged
user the HTTP server runs as. Any document written by a process running as root
SHALL be given world-readable permissions explicitly.

#### Scenario: Document written atomically by a root process
- **WHEN** a root-owned process writes a served document via a temporary file and rename
- **THEN** the resulting file is world-readable
- **AND** the HTTP server returns it rather than a 404

#### Scenario: Permission regression is detectable
- **WHEN** a served document exists but is not readable by the server user
- **THEN** the request returns 404 and this is treated as a fault rather than as an absent document
