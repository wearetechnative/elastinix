# Elastinix Services Documentation

This directory contains documentation for all Elastinix services. Each service has its own detailed documentation page.

## Available Services

### Integration Services
Services that integrate with external systems and APIs.

- **[Jira Sync](services/jirasync.md)** - Multi-instance Jira synchronization service with flexible scheduling and age-encrypted configuration support

### Infrastructure Services
*(Documentation coming soon)*

### Monitoring Services
*(Documentation coming soon)*

### Application Services
*(Documentation coming soon)*

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
