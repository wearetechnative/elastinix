# Badgersbay Security Report Server

The Badgersbay service (`elastinix.services.badgersbay`) is a centralized security report aggregation server for collecting vulnerability scan results from multiple hosts. It provides authenticated HTTP endpoints for report submission and a web dashboard for viewing compliance status.

**Also known as**: Honeybadger Server

## Use Case

Badgersbay enables centralized security monitoring by providing a persistent service that:

- **Collects security reports**: Receives vulnerability scans (Lynis, Trivy, Vulnix) and system info (Fastfetch) from multiple hosts
- **Tracks compliance**: Monitors which systems have submitted required reports during audit periods
- **Web dashboard**: Provides a password-protected dashboard to view compliance status
- **API authentication**: Uses Bearer token authentication for secure report submission
- **Always available**: Runs as a long-running daemon service with automatic restart on failure
- **Secure**: Runs under a dedicated system user with restricted permissions

## Features

- **Authentication required**: API token authentication for report submission, password authentication for dashboard access
- **Multiple report types**: Supports Fastfetch, Lynis, Trivy, and Vulnix reports
- **Compliance tracking**: Monitors which systems have submitted required reports
- **Audit periods**: Configurable audit months (e.g., March and September)
- **Web dashboard**: View compliance status for all systems
- **Configurable port**: Choose any available port (default: 9117)
- **Flexible storage**: Specify storage location for reports
- **Dedicated user**: Runs under its own system user for security isolation
- **Automatic directory creation**: Storage directory is created with proper permissions
- **Firewall integration**: Automatically opens the configured port in the firewall
- **Security hardening**: Runs with extensive systemd security restrictions
- **Automatic restart**: Service automatically restarts on failure

## Configuration

### Authentication Setup

**IMPORTANT**: As of version 1.1.0, authentication is mandatory. The service requires two encrypted secret files managed by agenix.

#### 1. Create Authentication Files

**Token file** (`badgersbay-tokens.yaml`):
```yaml
tokens:
  - hb_token_abc123def456
  - hb_token_xyz789ghi012
```

Generate secure tokens:
```bash
echo "hb_token_$(openssl rand -hex 16)"
```

**Password file** (`badgersbay-password.txt`):
```
your_secure_dashboard_password
```

Generate a secure password:
```bash
openssl rand -base64 24
```

#### 2. Encrypt with agenix

```bash
# Encrypt token file
agenix -e secrets/badgersbay-tokens.yaml.age

# Encrypt password file
agenix -e secrets/badgersbay-password.txt.age
```

#### 3. Configure agenix Secrets

```nix
age.secrets = {
  badgersbay-tokens = {
    file = ./secrets/badgersbay-tokens.yaml.age;
    owner = "badgersbay";  # Must match service user
    group = "badgersbay";  # Must match service group
  };
  badgersbay-password = {
    file = ./secrets/badgersbay-password.txt.age;
    owner = "badgersbay";
    group = "badgersbay";
  };
};
```

### Basic Example

```nix
elastinix.services.badgersbay = {
  enable = true;
  port = 9117;                                                      # Optional, this is the default
  storagePath = "/data/badgersbay";                                # Optional, this is the default
  tokenFile = config.age.secrets.badgersbay-tokens.path;           # Required
  dashboardPasswordFile = config.age.secrets.badgersbay-password.path; # Required
  assetRegisterFile = config.age.secrets.badgersbay-assets.path;   # Optional
};
```

### Asset Register

The asset register is the list of systems expected to report, exported from the
`Active Assets` sheet of the ISO compliance spreadsheet. It is the denominator
badgersbay measures coverage against: without it the dashboard can show what
arrived but never which systems are missing, and both its views say so.

```csv
asset_id,serial,owner,model,class,status,owner_since,valid_from,valid_to,departure_reason
TARI-00023,PF50L2MR,Wouter van der Toorren,LENOVO 21K9CTO1WW,linux,active,2024-01-01,2024-01-01,,
TARI-00045,FRANDGCPA5530200H9,Jeroen Penders,"Laptop Framework 13\" (AMD Ryzen 7040)",linux,active,2024-01-01,2024-01-01,,
```

`asset_id` is the durable identity, as the ISO register holds it. `serial` is
the hardware serial an incoming submission is matched on; one asset may have
several over its life, each as its own row with its own validity window, so a
replaced device keeps one continuous history.

The file pairs employee names with hardware serials, so encrypt it as you do
the tokens and the password:

```bash
agenix -e badgersbay-assets.age
```

and add it to `secrets.nix` beside the others:

```nix
"badgersbay-assets.age".publicKeys = users ++ systems;
```

The option is optional. A host that does not set it runs without a register,
as it did before the option existed.

**Badgersbay refuses to start on a register it cannot trust** - a duplicate
active serial, an unknown platform class, an unparseable date, or two rows
claiming one serial for overlapping periods. A compliance figure built on an
ambiguous register cannot be trusted either, so this fails loudly at deploy
time rather than quietly at read time.

An asset that disappears from a later register is reported on the dashboard
rather than silently dropped: a filtered or truncated export raises the
coverage rate, which is the one direction a compliance figure must never move
by accident.

### Custom Configuration

```nix
elastinix.services.badgersbay = {
  enable = true;
  port = 8080;
  storagePath = "/var/lib/badgersbay";
  tokenFile = config.age.secrets.badgersbay-tokens.path;
  dashboardPasswordFile = config.age.secrets.badgersbay-password.path;
  user = "badgersbay";   # Optional, this is the default
  group = "badgersbay";  # Optional, this is the default

  settings.compliance = {
    audit_months = [ 2 8 ];
    grace_weeks = 6;
  };
};
```

Everything not mentioned keeps the module's default, and keeps following it
when the module changes. See [The configuration file](#the-configuration-file).

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the Badgersbay service |
| `port` | port (1-65535) | `9117` | Network port for the service to listen on |
| `storagePath` | string | `"/data/badgersbay"` | Path where reports are stored |
| `tokenFile` | path | - | **Required**. Path to YAML file with API tokens (use agenix) |
| `dashboardPasswordFile` | path | - | **Required**. Path to file with dashboard password (use agenix) |
| `assetRegisterFile` | null or path | `null` | Path to the asset register CSV (use agenix) |
| `settings` | attribute set | see below | The server configuration, rendered to YAML |
| `configFile` | path | rendered from `settings` | Escape hatch: a configuration file to use instead |
| `user` | string | `"badgersbay"` | User to run the service as |
| `group` | string | `"badgersbay"` | Group to run the service as |

`settings` and `configFile` are two answers to the same question, so setting
both is an evaluation error. See [The configuration
file](#the-configuration-file).

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

## Restart on a changed file

The server reads its configuration, its API tokens, its dashboard password and
its asset register once, at startup. A deploy that changes one of them therefore
only takes effect if the service is restarted, so the module declares
`restartTriggers` covering all four.

Without them a changed secret lands on disk and never reaches the running
process: a rotated token where the service keeps accepting the old one and
rejecting the new one, or a reissued asset register that produces a compliance
figure quietly measured against the previous one. Nothing reports it. The
closure is new, the unit file is new, and the symptom looks like a deploy that
did not happen.

**How a change is detected.** It depends on where the file comes from:

| The file                        | What the trigger watches                     |
|---------------------------------|----------------------------------------------|
| Rendered from `settings`        | Its store path, which changes with content   |
| An agenix secret                | The `.age` source it is decrypted from       |
| Anything else                   | Its path only - see the limit below          |

An agenix secret arrives at a stable path: `/run/agenix/badgersbay-tokens` is the
same string before and after the rewrite, and the decrypted content cannot be
read at evaluation - nor should it be, since reading it would put the secret in
the world-readable store. What does change is the ciphertext, so the trigger is
the `.age` file the `age.secrets` entry names.

The restart happens after the new content is in place.
`switch-to-configuration` stops the units it must restart, runs the activation
scripts that decrypt the secrets, and only then starts them.

**Re-encrypting is enough.** Age ciphertext differs on every encryption, so
running `agenix -e` on one of these secrets restarts badgersbay even if you
change nothing in the editor - adding a host key does it too. Deliberate: a
restart nobody needed costs a few seconds during a deploy that was already
restarting things, while a restart that did not happen is the failure above.

**A restart is a real restart.** Submissions in flight fail and the submitting
host retries on its next run, and the dashboard is briefly unavailable. A
reissued register that the server rejects - a duplicate active serial, an unknown
platform class, an unparseable date - now takes the service down at deploy time
rather than at the next unrelated restart. That is the refusal arriving at the
deploy that caused it, and `systemctl status badgersbay` says so.

**The limit.** A secret file that is neither in the nix store nor produced by an
`age.secrets` entry - one placed on the host by hand, say - has nothing about it
that is readable at evaluation, so only its path is in the trigger list and a
change to its content does not restart the service. Deliver such a file through
agenix, or restart the service yourself after changing it.

## Authentication

### API Authentication (Report Submission)

All report submission endpoints require Bearer token authentication:

```bash
# Submit a report with authentication
curl -X POST http://server:9117/ \
  -H "Authorization: Bearer hb_token_abc123def456" \
  -H "Content-Type: application/json" \
  -H "X-Hostname: $(hostname)" \
  -H "X-Username: $(whoami)" \
  -H "X-Report-Type: lynis" \
  -d @lynis-report.json
```

**Authentication errors**:
- `401` + "Missing Authorization header" - No Bearer token provided
- `401` + "Invalid authentication token" - Token not found in tokens.yaml
- `401` + "Invalid Authorization header format" - Malformed header

### Dashboard Authentication

The web dashboard uses HTTP Basic Authentication. Access via browser or curl:

```bash
# Browser: Navigate to http://server:9117/
# Enter any username and the password from dashboardPasswordFile

# Command line
curl -u admin:your_password http://server:9117/
```

### Health Check (Unauthenticated)

The `/health` endpoint works without authentication for monitoring:

```bash
curl http://localhost:9117/health
```

Returns:
```json
{
  "status": "ok",
  "http_code": 200,
  "service": "honeybadger-server",
  "uptime": {"seconds": 3600, "human_readable": "1h 0m"},
  "statistics": {
    "total_report_directories": 42,
    "unique_hosts": 10,
    "reports_by_type": {"lynis": 40, "fastfetch": 42}
  }
}
```

## Network Access

### Testing the Service

```bash
# Check if the port is listening
ss -tlnp | grep 9117

# Test health check (no auth required)
curl http://localhost:9117/health

# Test authenticated API
curl -X POST http://localhost:9117/ \
  -H "Authorization: Bearer your_token" \
  -H "X-Hostname: test" \
  -H "X-Username: test" \
  -H "X-Report-Type: fastfetch" \
  -d '{"os": "NixOS"}'

# Test dashboard (requires password)
curl -u admin:your_password http://localhost:9117/
```

### Remote Access

If you need to access the service from other machines:

1. The firewall port is automatically opened for TCP traffic
2. Ensure your network security groups or cloud firewall rules allow incoming connections
3. The service is accessible via HTTPS through the nginx reverse proxy at `badgersbay.${environment_domain}`

## Troubleshooting

### Service fails to start

1. Check the service logs:
   ```bash
   journalctl -u badgersbay.service -n 50
   ```

2. **Common error: "Token file not found"**

   Verify agenix secrets are configured and accessible:
   ```bash
   # Check if secret files exist
   ls -l /run/agenix/badgersbay-*

   # Verify ownership
   stat /run/agenix/badgersbay-tokens.yaml
   # Should show owner: badgersbay
   ```

3. **Common error: "Token file missing 'tokens' key"**

   Check YAML syntax in token file:
   ```bash
   # View decrypted content (as root or badgersbay user)
   cat /run/agenix/badgersbay-tokens.yaml
   ```

   Should contain:
   ```yaml
   tokens:
     - hb_token_...
   ```

4. Verify the storage directory exists and has correct permissions:
   ```bash
   ls -ld /data/badgersbay
   # Should show: drwxr-x--- badgersbay badgersbay
   ```

5. Check if the port is already in use:
   ```bash
   ss -tlnp | grep 9117
   ```

6. Verify the badgersbay package is available:
   ```bash
   which honeybadger-server
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

### Authentication Issues

**API returns 401 Unauthorized**

1. Verify token is correct:
   ```bash
   # Check tokens in file (as root)
   cat /run/agenix/badgersbay-tokens.yaml
   ```

2. Ensure Authorization header format is correct:
   ```bash
   # Correct format
   -H "Authorization: Bearer hb_token_abc123"

   # NOT: "Token hb_token_abc123"
   # NOT: "hb_token_abc123"
   ```

3. Check token has no extra whitespace or newlines

**Dashboard password doesn't work**

1. Verify password file content:
   ```bash
   cat /run/agenix/badgersbay-password.txt
   # Should be single line, no extra whitespace
   ```

2. Try different username (username is ignored, but required for Basic Auth)

3. Clear browser cache and try again

**Health check returns 401**

This shouldn't happen - health check doesn't require auth. Check:
```bash
curl -v http://localhost:9117/health
# Should return 200 without auth
```

### Service keeps restarting

If the service is stuck in a restart loop:

1. Check logs for crash information:
   ```bash
   journalctl -u badgersbay.service -f
   ```

2. Verify authentication files are accessible:
   ```bash
   ls -l /run/agenix/badgersbay-*
   stat /run/agenix/badgersbay-tokens.yaml
   ```

3. Check system resources (disk space, memory)

4. Temporarily increase restart delay:
   ```nix
   # In your configuration (requires module modification)
   systemd.services.badgersbay.serviceConfig.RestartSec = "30s";
   ```

## Example: Complete Production Configuration

```nix
{ config, ... }:
{
  # Configure agenix secrets
  age.secrets = {
    badgersbay-tokens = {
      file = ./secrets/badgersbay-tokens.yaml.age;
      owner = "badgersbay";
      group = "badgersbay";
    };
    badgersbay-password = {
      file = ./secrets/badgersbay-password.txt.age;
      owner = "badgersbay";
      group = "badgersbay";
    };
  };

  # Enable badgersbay service
  elastinix.services.badgersbay = {
    enable = true;
    port = 9117;
    storagePath = "/data/badgersbay";
    tokenFile = config.age.secrets.badgersbay-tokens.path;
    dashboardPasswordFile = config.age.secrets.badgersbay-password.path;
  };
}
```

This configuration:
- Encrypts authentication files with agenix
- Listens on port 9117
- Stores reports in `/data/badgersbay`
- Automatically opens port 9117 in the firewall
- Creates the storage directory with proper permissions
- Accessible via HTTPS at `badgersbay.${environment_domain}`

## Example: Conditional Deployment

Deploy only in specific environments:

```nix
elastinix.services.badgersbay = lib.mkIf (infra_environment == "prod") {
  enable = true;
  port = 9117;
  storagePath = "/data/badgersbay";
};
```

## Report Types

The service accepts the following report types:

| Type | Purpose | Required |
|------|---------|----------|
| **Fastfetch** | System metadata (hostname, OS, kernel) | Mandatory |
| **Lynis** | System hardening audit | Mandatory |
| **Trivy** | Container/OS vulnerability scanner | One of Trivy or Vulnix |
| **Vulnix** | NixOS vulnerability scanner | One of Trivy or Vulnix |

A system is marked "Complete" in the dashboard when it has submitted:
- Fastfetch (system identity)
- Lynis (hardening audit)
- Trivy OR Vulnix (vulnerability scan)

## The Configuration File

The server reads a YAML configuration file. The module renders it from
`settings`, so a host changes one value rather than replacing the file:

```nix
elastinix.services.badgersbay.settings.compliance = {
  audit_months = [ 2 8 ];
  required_reports.one_of = [ "trivy" "vulnix" ];
};
```

Everything else keeps its default - and keeps following the module when that
default changes. That is the whole point of the option: the required report
type moved from `neofetch` to `fastfetch` once already, and the one host that
had replaced the configuration file never received it. Every system on it was
recorded as incomplete until its secret was reissued by hand.

### Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `networkport` | port | follows `port` | Port the server listens on |
| `storage_location` | string | `"<storagePath>/reports"` | Where submissions are written |
| `compliance.enabled` | boolean | `true` | Track audit rounds at all |
| `compliance.audit_months` | list of 1-12 | `[ 3 9 ]` | Months in which a round opens |
| `compliance.grace_weeks` | unsigned integer | `4` | Weeks past the audit month a submission still counts |
| `compliance.required_reports.mandatory` | list of string | `[ "fastfetch" "lynis" ]` | Report types every system must submit |
| `compliance.required_reports.one_of` | list of string | `[ ]` | Report types of which at least one must arrive |
| `compliance.required_reports.per_class` | class -> requirement -> types | `{ }` | Per-platform-class requirements |

Keys the table does not list are passed through unchanged, so a configuration
key badgersbay gains can be set here before this module knows about it.

`per_class` names a requirement after what it is rather than after the tool
that satisfies it, because those differ per platform and change over time:

```nix
settings.compliance.required_reports.per_class.windows = {
  sysinfo = [ "fastfetch" ];
  hardening = [ "hardeningkitty" ];
};
```

Systems must submit all required reports during each audit round to be
compliant.

### No secrets live here

The rendered file is a nix store path, and the store is world-readable on every
machine that has it. That is acceptable only because nothing in `settings` is
secret. The API tokens, the dashboard password and the asset register are
delivered as agenix secrets and the module receives their paths, never their
contents - which is why there is no `tokens = [ ... ]` option and never will
be.

For the same reason `compliance.asset_register` is not settable here: the
service passes `--asset-register`, which overrides the configuration file, so a
value set in `settings` would be silently discarded. Use `assetRegisterFile`.

### configFile: the escape hatch

`configFile` names a configuration file to use instead of the rendered one. It
replaces that file whole - the module's defaults stop reaching this host, which
is exactly the failure described above - so it is a last resort rather than a
way to change a value.

Setting `configFile` and `settings` together is an evaluation error. One of the
two would have to be discarded without a word, and being told to choose is
better than finding out months later which one lost.

**Migrating off an agenix configuration secret.** The configuration carries no
secrets, so it does not need to be one. Read the values out of the secret, put
them in `settings`, drop `configFile`, and the host follows the module again:

```nix
# before
configFile = config.age.secrets.badgersbay-config.path;

# after
settings.compliance = {
  audit_months = [ 3 9 ];
  grace_weeks = 4;
};
```

### What fails at evaluation

The module refuses a configuration it can see is wrong, rather than letting the
service fail at start where the reason is a log line on a host nobody is
watching:

| Refused | Why |
|---|---|
| `configFile` and `settings` both set | One would be discarded silently |
| `settings.networkport` differing from `port` | The firewall and the nginx proxy follow `port`, so the server would listen where neither reaches it |
| `settings.compliance.asset_register` set | `--asset-register` overrides it; use `assetRegisterFile` |
| A secret option naming a store path | The store is world-readable; this includes a path literal, which is copied there the moment the unit interpolates it |
| A secret path under `age.secretsDir` with no matching `age.secrets` entry | Nothing would write the file |
| An agenix secret the service user cannot read | agenix defaults to root-owned `0400`, so this is the usual case rather than an exotic one |

**Their limits.** These checks read the configuration, not the machine. The
last two need the agenix module imported and are skipped entirely without it,
because the module works with plain paths too. The readability check judges
numeric modes only - agenix passes `mode` to `chmod`, which also takes symbolic
forms - and leaves a numeric non-root `owner` alone rather than guessing which
user it names. A file that exists but holds the wrong thing, an unreadable path
outside `age.secretsDir`, a token that the server rejects: none of those are
visible here, and the service still has to start for you to find out.

## Implementation Details

- **Package**: Python HTTP service (honeybadger-server)
- **Source**: https://github.com/wearetechnative/badgersbay
- **Service type**: Simple daemon (long-running)
- **Service definition**: `modules/nixos/services/service-badgersbay.nix`
- **Authentication**: Bearer token (API) + HTTP Basic Auth (dashboard)
- **Reverse proxy**: Nginx provides HTTPS access

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
