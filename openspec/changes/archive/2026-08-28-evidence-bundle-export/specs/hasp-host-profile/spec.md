## ADDED Requirements

### Requirement: Firewall facts state whether the firewall is running

The profile SHALL publish whether the host firewall is enabled, so a port allow-list can never be read as a restrictive control on a host that has no firewall.

#### Scenario: Firewall enabled

- **WHEN** `networking.firewall.enable` is true
- **THEN** `network.firewallEnabled` is `true`
- **AND** the open-port facts list the configured allowed ports

#### Scenario: Firewall disabled

- **WHEN** `networking.firewall.enable` is false
- **THEN** `network.firewallEnabled` is `false`
- **AND** the open-port facts are empty rather than listing inert configuration
- **AND** each open-port fact's evidence string states that the firewall is disabled and every port of that protocol is reachable

#### Scenario: Configured ports are inert when the firewall is off

- **WHEN** a host defines `allowedTCPPorts` but sets `networking.firewall.enable = false`
- **THEN** no consumer reading the profile can obtain a non-empty allow-list for that host

### Requirement: Firewall facts are protocol-specific

The profile SHALL record open firewall ports separately per protocol, so an observed socket carrying a protocol can be matched against the correct allow-list.

#### Scenario: TCP and UDP recorded apart

- **WHEN** a host allows TCP 443 and UDP 4242
- **THEN** `network.firewallOpenTcpPorts` contains 443 and not 4242
- **AND** `network.firewallOpenUdpPorts` contains 4242 and not 443

#### Scenario: Same port number on both protocols

- **WHEN** a host allows TCP 53 and UDP 53
- **THEN** both facts contain 53 independently
