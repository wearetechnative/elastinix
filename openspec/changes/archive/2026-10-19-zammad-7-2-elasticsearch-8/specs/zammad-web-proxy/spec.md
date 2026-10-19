# Spec Delta

## Purpose

Defines how the nginx virtual host of `elastinix.services.zammad` forwards browser traffic to Zammad, including the WebSocket endpoints and the request scheme that Zammad 7.2 relies on.

## ADDED Requirements

### Requirement: HTTP proxy with forwarded scheme

The zammad nginx virtual host SHALL proxy `/` to the Zammad web port on loopback and SHALL send the standard proxy headers, including `X-Forwarded-Proto`, so Zammad sees the HTTPS scheme the client used.

#### Scenario: Forwarded headers on the root location

- **WHEN** the zammad service is enabled
- **THEN** the `/` location of `zammad.<environment_domain>` proxies to `http://127.0.0.1:<web port>` with recommended proxy headers enabled

### Requirement: WebSocket endpoints

The virtual host SHALL proxy `/cable` (ActionCable) to the Zammad web port and `/ws` (legacy WebSocket server) to the Zammad websocket port, both with WebSocket upgrade headers.

#### Scenario: Cable and ws locations upgrade connections

- **WHEN** the zammad service is enabled
- **THEN** the `/cable` location proxies to the web port with WebSocket upgrades
- **AND** the `/ws` location proxies to the websocket port with WebSocket upgrades

### Requirement: TLS termination unchanged

The virtual host SHALL keep ACME certificates and force HTTPS, as before this change.

#### Scenario: HTTPS enforced

- **WHEN** the zammad service is enabled
- **THEN** the virtual host has `enableACME` and `forceSSL` set
