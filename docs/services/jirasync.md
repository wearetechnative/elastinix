# Jira Sync Service

The Jira Sync service (`elastinix.services.jirasync`) is a multi-instance service that performs **one-way synchronization** of Jira issues from a remote/client board to your own organization's board. This enables better DevOps and Agile workflows by maintaining a unified view of work across organizational boundaries.

## Use Case

When working with external clients or partners who have their own Jira instances, you often need visibility into their issues within your own development workflow. The Jira Sync service solves this by:

- **One-way sync**: Automatically copies issues from a remote client Jira board to your organization's Jira board
- **Maintaining separation**: Keeps client and internal boards separate while ensuring visibility
- **Supporting DevOps practices**: Enables teams to plan and track work that depends on external issues
- **Improving collaboration**: Provides a single source of truth for cross-organizational dependencies

**Important**: This is a one-way synchronization. Issues are copied from the remote/client board (source) to your organization's board (target). Changes made in your organization's board are **not** synced back to the client's board.

## Features

- **Multi-instance support**: Run multiple sync jobs for different boards or configurations
- **Flexible scheduling**: Use systemd timer syntax for precise scheduling
- **Dry-run mode**: Test configurations without making actual changes
- **Security hardening**: Runs with extensive systemd security restrictions
- **Age-encrypted configuration**: Secrets are managed via agenix

## Prerequisites: Jira API Setup

Before configuring the Jira Sync service, you need to set up API access in Jira.

### Creating a Jira API Token

You need to create **one API token** for a user account in your own organization's Jira. This user must have access to both:
- The client's/remote board (read access)
- Your organization's board (read and write access)

**Steps to create the API token:**

1. Log in to your Atlassian account at [https://id.atlassian.com](https://id.atlassian.com)
2. Navigate to **Security** → **API tokens**
3. Click **Create API token**
4. Give your token a descriptive name (e.g., "Elastinix Jira Sync")
5. Copy the generated token immediately - you won't be able to see it again

**Important**: API tokens inherit the permissions of the user account that created them. The token can perform any action that the user is allowed to perform.

**Note**: The client/remote organization must grant your user account access to their Jira board with at least read permissions. This is typically done by inviting your user to their Jira project or workspace.

For detailed instructions, see the [official Atlassian documentation on managing API tokens](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/).

### Required Jira Permissions

The user account (in your organization) associated with the API token must have the following permissions:

#### Source Board/Project Permissions (Client's/Remote Board)

Your user account must be granted access to the client's Jira board with these permissions to read and query issues:

| Permission | Purpose | Required |
|------------|---------|----------|
| **Browse Projects** | View the project and its issues | ✅ Yes |
| **View Development Tools** | Access board information | ⚠️ Recommended |

#### Target Board/Project Permissions (Your Organization's Jira)

The user needs these permissions to create and update synchronized issues in your own Jira instance:

| Permission | Purpose | Required |
|------------|---------|----------|
| **Browse Projects** | View the project and its issues | ✅ Yes |
| **Create Issues** | Create new issues in the target project | ✅ Yes |
| **Edit Issues** | Modify existing issues | ✅ Yes |
| **Assign Issues** | Assign issues to users | ⚠️ If syncing assignees |
| **Transition Issues** | Change issue status | ⚠️ If syncing status |
| **Add Comments** | Add comments to issues | ⚠️ If syncing comments |

**Note**: Some permissions have dependencies. For example, to edit an issue, the user must also have the "Browse Projects" permission. To transition issues (change status), both "Transition Issues" and specific workflow permissions are required.

### Permission Schemes

Jira permissions are managed through [permission schemes](https://support.atlassian.com/jira-cloud-administration/docs/manage-project-permissions/), which define who can perform which actions in a project. To grant the necessary permissions:

1. Navigate to **Project Settings** → **Permissions** in your Jira project
2. Ensure the user is assigned to a role (e.g., Developer, Administrator) that has the required permissions
3. Verify permissions by checking the permission scheme assigned to the project

For more information about Jira permissions and roles, see:
- [Managing project permissions](https://support.atlassian.com/jira-cloud-administration/docs/manage-project-permissions/)
- [Jira permissions overview](https://support.atlassian.com/jira/kb/jira-permissions-general-overview/)
- [Jira Cloud Platform REST API - Permissions](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-permissions/)

### Service Account Recommendation

For production use, it's recommended to create a dedicated service account user in **your organization's Jira**:

1. Create a new user account in your organization specifically for API integration (e.g., `jirasync-service@mycompany.com`)
2. Assign this user to the appropriate project roles in your organization's boards with minimal required permissions
3. Request the client to grant this service account read access to their Jira board
4. Generate an API token for this service account
5. Use this dedicated account instead of a personal user account

This provides:
- Better audit trails (actions are clearly identified as automated)
- Security isolation (token compromise doesn't affect personal accounts)
- Easier permission management across client and organization boards
- Compliance with principle of least privilege

**Client Access Setup**: The client organization must:
1. Invite the service account user to their Jira workspace/project
2. Grant the user at least "Browse Projects" permission on their board
3. Ensure any IP restrictions or security policies allow access

For service account management, see [Atlassian's service account documentation](https://support.atlassian.com/user-management/docs/manage-api-tokens-for-service-accounts/).

## Configuration

### Basic Example

```nix
elastinix.services.jirasync = {
  enable = true;
  instances = {
    acme-corp = {
      configFile = config.age.secrets.jirasync-acme-corp.path;
      daysToSync = 90;
      interval = "*-*-* 07..17:00:00";  # Every hour from 7 AM to 5 PM
    };
  };
};

# Age secret for the configuration
age.secrets.jirasync-acme-corp = {
  file = ../secrets/jirasync-acme-corp.json.age;
};
```

### Multiple Instances

You can configure multiple sync instances for different clients or projects:

```nix
elastinix.services.jirasync = {
  enable = true;
  instances = {
    acme-widgets = {
      configFile = config.age.secrets.jirasync-acme-widgets.path;
      daysToSync = 90;
      interval = "*-*-* 07..17:00:00";
    };
    globex-inc = {
      configFile = config.age.secrets.jirasync-globex-inc.path;
      daysToSync = 30;
      interval = "daily";
    };
  };
};

# Corresponding age secrets
age.secrets = {
  jirasync-acme-widgets.file = ../secrets/jirasync-acme-widgets.json.age;
  jirasync-globex-inc.file = ../secrets/jirasync-globex-inc.json.age;
};
```

## Configuration Options

### Service-level Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Enable the Jira sync service |
| `instances` | attrset | `{}` | Set of named sync instances |

### Instance Options

Each instance in the `instances` attribute set supports the following options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `configFile` | string | - | **Required**. Path to the Jira sync configuration file (typically an age secret path) |
| `daysToSync` | integer | `90` | Number of days to look back for issues |
| `dryRun` | boolean | `false` | Run in dry-run mode without making changes |
| `interval` | string | `"hourly"` | Systemd timer interval (OnCalendar syntax) |
| `user` | string | `"root"` | User to run the service as |
| `group` | string | `"root"` | Group to run the service as |

## Systemd Timer Intervals

The `interval` option uses systemd's `OnCalendar` syntax. Common examples:

- `"hourly"` - Every hour at minute 0
- `"daily"` - Every day at midnight
- `"*-*-* 07..17:00:00"` - Every hour from 7 AM to 5 PM
- `"*:0/30"` - Every 30 minutes
- `"Mon,Wed,Fri *-*-* 09:00:00"` - Monday, Wednesday, Friday at 9 AM

See `man systemd.time` for complete syntax documentation.

## Configuration File Format

The configuration file (typically encrypted with age) should be a JSON file containing your Jira API credentials and sync settings:

```json
{
  "source_jira_url": "https://acme-corp.atlassian.net",
  "source_project_key": "ACME",
  "source_board_id": 123,
  "target_jira_url": "https://mycompany.atlassian.net",
  "target_jira_user": "jirasync-service@mycompany.com",
  "target_jira_token": "ATATT3xFfGF0...",
  "target_project_key": "INT",
  "target_board_id": 456
}
```

### Field Descriptions

**Source Configuration (Client/Remote - Read From):**

| Field | Description | Example |
|-------|-------------|---------|
| `source_jira_url` | Source Jira instance URL (client's/remote Jira where issues are read from) | `https://acme-corp.atlassian.net` |
| `source_project_key` | The source Jira project key to sync from (client's board) | `ACME` |
| `source_board_id` | The board ID in the source Jira instance | `123` |

**Target Configuration (Your Organization - Write To):**

| Field | Description | Example |
|-------|-------------|---------|
| `target_jira_url` | URL of your organization's Jira instance (where issues are synced to) | `https://mycompany.atlassian.net` |
| `target_jira_user` | Email address of your organization's user who created the API token | `jirasync-service@mycompany.com` |
| `target_jira_token` | The API token created by your organization's user (see Prerequisites section) | `ATATT3xFfGF0...` |
| `target_project_key` | The target project key in your organization's Jira | `INT` |
| `target_board_id` | The board ID in your organization's Jira instance | `456` |

**Important**: You only need **one API token** - created by a user in your own organization's Jira (`target_jira_user` / `target_jira_token`). This user must be granted access by the client to read their Jira board (source), and must have write permissions on your organization's target board.

**Security Notes:**
- Always encrypt this file using agenix - never commit unencrypted credentials
- Use a dedicated service account for API access
- Rotate API tokens regularly
- Store API tokens securely and limit access

The exact format depends on your sync script requirements. Consult your specific sync script documentation for additional fields.

## Security

### Default Security Features

The service runs with the following systemd security hardening:

- `PrivateTmp=true` - Private /tmp directory
- `ProtectSystem=strict` - Read-only /usr, /boot, /efi
- `ProtectHome=true` - Home directories inaccessible
- `NoNewPrivileges=true` - Cannot gain new privileges
- Network restrictions (AF_INET, AF_INET6 only)
- System call filtering
- And more...

### Running as Non-Root

While the default is to run as root, you can configure instances to run as a different user:

```nix
instances = {
  my-instance = {
    configFile = config.age.secrets.jirasync-config.path;
    user = "jirasync";
    group = "jirasync";
    # ...
  };
};

# Corresponding age secret must have matching owner/group
age.secrets.jirasync-config = {
  file = ../secrets/jirasync-config.json.age;
  owner = "jirasync";
  group = "jirasync";
};
```

## Systemd Service Names

Each instance creates a systemd service and timer with the name `jirasync-<instance-name>`:

- Service: `jirasync-acme-corp.service`
- Timer: `jirasync-acme-corp.timer`

### Useful Commands

```bash
# Check service status
systemctl status jirasync-acme-corp.service

# View timer schedule
systemctl list-timers jirasync-*

# Manually trigger a sync
systemctl start jirasync-acme-corp.service

# View logs
journalctl -u jirasync-acme-corp.service

# Follow logs in real-time
journalctl -u jirasync-acme-corp.service -f
```

## Dry-Run Mode

To test a configuration without making actual changes, enable dry-run mode:

```nix
instances = {
  test-instance = {
    configFile = config.age.secrets.jirasync-test.path;
    dryRun = true;  # Enable dry-run mode
    # ...
  };
};
```

## Troubleshooting

### Service fails to start

1. Check the service logs: `journalctl -u jirasync-<instance>.service`
2. Verify the configuration file exists and is readable
3. Test the configuration file manually
4. Check age secret permissions

### Timer not triggering

1. Verify timer is enabled: `systemctl list-timers jirasync-*`
2. Check timer configuration: `systemctl cat jirasync-<instance>.timer`
3. Verify OnCalendar syntax is correct

### Permission errors

1. Ensure age secret owner/group match the service user/group
2. Check that the user has permission to read the config file
3. Verify network access if the service needs external connectivity

### Jira API authentication errors

1. Verify the API token is valid and hasn't expired
2. Check that the `jira_user` email matches your organization's account that created the API token (e.g., `jirasync-service@mycompany.com`)
3. Confirm your user account has been granted access by the client to their Jira board
4. Verify the user has the required permissions on both client (source) and your organization's (target) boards
5. Test API access to both Jira instances manually using curl:
   ```bash
   # Test access to client's Jira
   curl -u "jirasync-service@mycompany.com:API_TOKEN" \
     -H "Accept: application/json" \
     "https://acme-corp.atlassian.net/rest/api/3/myself"

   # Test access to your organization's Jira
   curl -u "jirasync-service@mycompany.com:API_TOKEN" \
     -H "Accept: application/json" \
     "https://mycompany.atlassian.net/rest/api/3/myself"
   ```

### Jira permission errors

If you see "403 Forbidden" or "You do not have permission" errors:

1. **Client's board (source)**:
   - Verify your organization's user has been invited to the client's Jira workspace/project
   - Confirm the user has at least "Browse Projects" permission on the client's board
   - Check if the client has IP allowlists or security restrictions that block your access

2. **Your organization's board (target)**:
   - Verify your user has "Create Issues" and "Edit Issues" permissions
   - Check the user's project role and assigned permissions

3. Check the user's project role in both Jira instances
4. Review the permission schemes assigned to both projects
5. Contact the client's Jira administrator if source board access is denied

## Example: Conditional Deployment

Deploy only in production environment:

```nix
elastinix.services.jirasync = lib.mkIf (infra_environment == "prod") {
  enable = true;
  instances = {
    production-sync = {
      configFile = config.age.secrets.jirasync-prod.path;
      daysToSync = 90;
      interval = "*-*-* 07..17:00:00";
    };
  };
};
```

## Implementation Details

- **Package**: Python script with requests library
- **Location**: `/nix/store/.../bin/jirasync`
- **Script**: `modules/nixos/services-scripts/jirasync.py`
- **Service definition**: `modules/nixos/services/service-jirasync.nix`

## Related Documentation

- [Systemd Timers](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)
- [Agenix](https://github.com/ryantm/agenix)
- [NixOS Service Hardening](https://nixos.org/manual/nixos/stable/index.html#sec-systemd-hardening)
