# Elastinix Services Documentation

This directory contains documentation for all Elastinix services. Each service has its own detailed documentation page.

## Available Services

### Integration Services
Services that integrate with external systems and APIs.

- **[Jira Sync](services/jirasync.md)** - Multi-instance Jira synchronization service with flexible scheduling and age-encrypted configuration support
- **[Jira Ticket Create](services/jiraticketcreate.md)** - Scheduled Jira ticket creation per client and check type, with systemd timer-based scheduling

### Infrastructure Services
Services that provide infrastructure-level functionality.

- **[Postfix AWS SES Relay](services/postfix-relay-aws.md)** - Centralized mail relay for AWS SES with SASL authentication, network security, and sender address rewriting

### Security Services
Services that provide security scanning and compliance functionality.

- **[Vulnerability Scan Central](services/vulnerability-scan-central.md)** - Combined central vulnerability scanner: vulnix for NixOS packages (all hosts) and trivy for Docker images (per host via `enableDockerScan`)
- **[Vulnerability Prometheus Exporter](services/vulnerability-prometheus-exporter.md)** - Prometheus exporter exposing per-host vulnerability metrics from vulnix and trivy scan results

### Monitoring Services

- **[Grafana / Prometheus](services/grafana-prometheus.md)** - Grafana, Prometheus, Alertmanager and exporters behind nginx, with optional OIDC/Cognito authentication (oauth2-proxy) for Prometheus and Alertmanager and localhost-bound metrics endpoints
- **[Hostinfo](services/hostinfo.md)** - Lightweight HTTP server exposing system inventory JSON (enabled services, NixOS version, optional SBOM) for monitoring and dashboard use

### Application Services
Services that provide application-level functionality.

- **[Atuin](services/atuin.md)** - Self-hosted Atuin shell-history sync server (native `services.atuin`) with local or external PostgreSQL and nginx TLS termination
- **[Badgersbay](services/badgersbay.md)** - File processing service with HTTP endpoint for receiving and storing files
- **[Chhoto](services/chhoto.md)** - Lightweight self-hosted URL shortener with SQLite storage
- **[Documenso](services/documenso.md)** - Open-source document signing platform (DocuSign alternative) with PDF signing, BullMQ job processing, and S3 storage
- **[OptScale](services/optscale.md)** - Full OptScale FinOps appliance (20 services + 6 datastores + React UI) on one instance, with agenix-managed secrets, substrate version pinning, and a TLS-fronted UI

## General Information

### Common Patterns

All Elastinix services follow these conventions:

1. **Namespace**: Services are configured under `elastinix.services.<service-name>`
2. **Enable option**: All services have an `enable` option to activate them
3. **Security**: Services run with systemd security hardening by default
4. **Secrets**: Sensitive configuration uses agenix for encryption

### Example Service Configuration

```nix
elastinix.services.<service-name> = {
  enable = true;
  # Service-specific options...
};
```

### Multi-Instance Services

Some services support multiple instances:

```nix
elastinix.services.<service-name> = {
  enable = true;
  instances = {
    instance-1 = {
      # Instance-specific configuration
    };
    instance-2 = {
      # Instance-specific configuration
    };
  };
};
```

## Contributing Documentation

When adding a new service to Elastinix:

1. Create a new markdown file in `docs/services/<service-name>.md`
2. Follow the template structure from existing service docs
3. Add a link to the service in this README
4. Include:
   - Service description and features
   - Configuration options (in table format)
   - Usage examples
   - Common troubleshooting steps

## Getting Help

- Check the service-specific documentation in the `services/` directory
- Review the main [Elastinix README](../README.md)
- Open an issue on the Elastinix repository

## Service Documentation Template

When documenting a new service, include these sections:

1. **Title and Overview** - What the service does
2. **Features** - Key capabilities
3. **Configuration** - Options and examples
4. **Usage** - How to use the service
5. **Troubleshooting** - Common issues and solutions
6. **Implementation Details** - Technical information

See [jirasync.md](services/jirasync.md) for a complete example.
