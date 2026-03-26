# Badgersbay File Processing Service

The Badgersbay service (`elastinix.services.badgersbay`) is a daemon service that opens a network port to receive and process files. It provides a simple HTTP endpoint for file upload and processing workflows.

## Use Case

Badgersbay enables automated file processing workflows by providing a persistent service that:

- **Accepts file uploads**: Listens on a configurable network port for incoming files
- **Persistent storage**: Stores received files in a dedicated storage directory
- **Always available**: Runs as a long-running daemon service with automatic restart on failure
- **Secure**: Runs under a dedicated system user with restricted permissions

## Features

- **Configurable port**: Choose any available port (default: 9117)
- **Flexible storage**: Specify storage location for processed files
- **Dedicated user**: Runs under its own system user for security isolation
- **Automatic directory creation**: Storage directory is created with proper permissions
- **Firewall integration**: Automatically opens the configured port in the firewall
- **Security hardening**: Runs with extensive systemd security restrictions
- **Automatic restart**: Service automatically restarts on failure

## Configuration

### Basic Example

```nix
elastinix.services.badgersbay = {
  enable = true;
  port = 9117;                      # Optional, this is the default
  storagePath = "/data/badgersbay"; # Optional, this is the default
};
```

### Custom Configuration

```nix
elastinix.services.badgersbay = {
  enable = true;
  port = 8080;
  storagePath = "/var/lib/badgersbay/files";
  user = "badgersbay";   # Optional, this is the default
  group = "badgersbay";  # Optional, this is the default
};
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the Badgersbay service |
| `port` | port (1-65535) | `9117` | Network port for the service to listen on |
| `storagePath` | string | `"/data/badgersbay"` | Path where files are stored and processed |
| `user` | string | `"badgersbay"` | User to run the service as |
| `group` | string | `"badgersbay"` | Group to run the service as |

## Storage Directory

The storage directory (`storagePath`) is automatically created with the following properties:

- **Ownership**: Set to the configured user and group
- **Permissions**: `0750` (rwxr-x---)
- **Created at boot**: Uses systemd tmpfiles.d to ensure directory exists

The service has read and write access to this directory while the rest of the filesystem remains protected by security hardening.

## Firewall Configuration

The service automatically opens the configured port in the NixOS firewall. No manual firewall configuration is required.

**Example**: If you configure `port = 9117`, the service will automatically add `9117` to `networking.firewall.allowedTCPPorts`.

## Security

### Dedicated System User

By default, the service runs as the `badgersbay` system user (not root). This user:

- Has minimal privileges
- Cannot log in interactively
- Only has access to the storage directory
- Is automatically created by the NixOS module

### Systemd Security Hardening

The service runs with extensive systemd security restrictions:

- `PrivateTmp=true` - Private /tmp directory
- `ProtectSystem=strict` - Read-only /usr, /boot, /efi
- `ProtectHome=true` - Home directories inaccessible
- `NoNewPrivileges=true` - Cannot gain new privileges
- `PrivateDevices=true` - No access to physical devices
- Network restrictions (AF_INET, AF_INET6 only)
- System call filtering
- Protection against kernel tunable modifications

### Write Permissions

The service only has write access to the configured `storagePath`. All other directories are read-only or inaccessible, minimizing the impact of potential security issues.

## Systemd Service

The service is named `badgersbay.service` and runs as a daemon (Type=simple).

### Useful Commands

```bash
# Check service status
systemctl status badgersbay.service

# View logs
journalctl -u badgersbay.service

# Follow logs in real-time
journalctl -u badgersbay.service -f

# Restart the service
systemctl restart badgersbay.service

# Stop the service
systemctl stop badgersbay.service

# Start the service
systemctl start badgersbay.service
```

## Automatic Restart

The service is configured to automatically restart on failure:

- **Restart policy**: `on-failure`
- **Restart delay**: 10 seconds
- **Service type**: Simple (long-running daemon)

If the badgersbay process crashes or exits unexpectedly, systemd will automatically restart it after 10 seconds.

## Network Access

### Testing the Service

You can test if the service is running and accessible:

```bash
# Check if the port is listening
ss -tlnp | grep 9117

# Test with curl (adjust URL based on your badgersbay API)
curl http://localhost:9117/health

# Upload a file (example - adjust based on your badgersbay API)
curl -X POST -F "file=@example.txt" http://localhost:9117/upload
```

### Remote Access

If you need to access the service from other machines:

1. The firewall port is automatically opened for TCP traffic
2. Ensure your network security groups or cloud firewall rules allow incoming connections
3. Consider using HTTPS/TLS for production deployments

## Troubleshooting

### Service fails to start

1. Check the service logs:
   ```bash
   journalctl -u badgersbay.service -n 50
   ```

2. Verify the storage directory exists and has correct permissions:
   ```bash
   ls -ld /data/badgersbay
   # Should show: drwxr-x--- badgersbay badgersbay
   ```

3. Check if the port is already in use:
   ```bash
   ss -tlnp | grep 9117
   ```

4. Verify the badgersbay package is available:
   ```bash
   which badgersbay
   ```

### Port already in use

If you see "address already in use" errors:

1. Check what's using the port:
   ```bash
   ss -tlnp | grep 9117
   ```

2. Either stop the conflicting service or configure badgersbay to use a different port:
   ```nix
   elastinix.services.badgersbay.port = 9118;  # Use different port
   ```

### Permission denied errors

If you see permission denied errors in the logs:

1. Verify storage directory permissions:
   ```bash
   ls -ld /data/badgersbay
   ```

2. Check systemd service configuration:
   ```bash
   systemctl cat badgersbay.service
   ```

3. Ensure the storage path is included in ReadWritePaths:
   ```bash
   systemctl show badgersbay.service | grep ReadWritePaths
   ```

### Firewall blocking connections

If connections are refused from remote machines:

1. Verify the firewall is open:
   ```bash
   nft list ruleset | grep 9117
   ```

2. Check your cloud provider's security groups/firewall rules

3. Test locally first to isolate the issue:
   ```bash
   curl http://localhost:9117/
   ```

### Service keeps restarting

If the service is stuck in a restart loop:

1. Check logs for crash information:
   ```bash
   journalctl -u badgersbay.service -f
   ```

2. Verify the configuration is correct

3. Check system resources (disk space, memory)

4. Temporarily increase restart delay:
   ```nix
   # In your configuration (requires module modification)
   systemd.services.badgersbay.serviceConfig.RestartSec = "30s";
   ```

## Example: Custom Storage and Port

```nix
elastinix.services.badgersbay = {
  enable = true;
  port = 8080;
  storagePath = "/mnt/data/processing";
};
```

This configuration:
- Listens on port 8080
- Stores files in `/mnt/data/processing`
- Automatically opens port 8080 in the firewall
- Creates the storage directory with proper permissions

## Example: Conditional Deployment

Deploy only in specific environments:

```nix
elastinix.services.badgersbay = lib.mkIf (infra_environment == "prod") {
  enable = true;
  port = 9117;
  storagePath = "/data/badgersbay";
};
```

## Implementation Details

- **Package**: Python HTTP service
- **Source**: https://github.com/wearetechnative/badgersbay
- **Service type**: Simple daemon (long-running)
- **Service definition**: `modules/nixos/services/service-badgersbay.nix`

## Monitoring

### Health Checks

Consider implementing health checks for the service:

```bash
# Example systemd timer for health check
systemd.timers.badgersbay-health = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "minutely";
    Unit = "badgersbay-health.service";
  };
};

systemd.services.badgersbay-health = {
  script = ''
    ${pkgs.curl}/bin/curl -f http://localhost:9117/health || {
      echo "Badgersbay health check failed"
      exit 1
    }
  '';
};
```

### Log Rotation

Logs are automatically handled by systemd journal. To configure retention:

```nix
services.journald.extraConfig = ''
  SystemMaxUse=500M
  MaxRetentionSec=30day
'';
```

## Performance Considerations

- **Concurrent connections**: Depends on the badgersbay implementation
- **Storage space**: Monitor disk usage in the storage directory
- **Network bandwidth**: Consider rate limiting if needed
- **File size limits**: Configure based on your use case

## Related Documentation

- [Systemd Service Hardening](https://nixos.org/manual/nixos/stable/index.html#sec-systemd-hardening)
- [NixOS Firewall](https://nixos.org/manual/nixos/stable/index.html#sec-firewall)
- [Systemd tmpfiles.d](https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html)
