# jiraticketcreate

Automatically creates recurring Jira tickets on a schedule. Useful for compliance checks, periodic reviews, and recurring tasks that need to land on client boards without manual intervention.

## Overview

The service generates one systemd timer + oneshot service pair per **client × check type** combination. Each service fires daily, evaluates whether today is the configured trigger day, and creates a Jira ticket if so.

```
checkTypes × clients → N systemd units
  e.g. iit × [aws-permission-matrix, security-scan]
    → jiraticketcreate-iit-aws-permission-matrix.{service,timer}
    → jiraticketcreate-iit-security-scan.{service,timer}
```

No state is tracked — if a service runs multiple times on the trigger day (e.g. after a server restart), a duplicate ticket may be created. This is accepted as a known limitation for v1.

## Configuration

```nix
age.secrets.jira-token-iit   = { file = ./secrets/jira-token-iit.age; };
age.secrets.jira-token-acme  = { file = ./secrets/jira-token-acme.age; };

elastinix.services.jiraticketcreate = {
  enable   = true;
  jiraUrl  = "https://mycompany.atlassian.net";
  jiraUser = "jira-service@mycompany.com";

  checkTypes = {
    aws-permission-matrix = {
      schedule          = "first_working_day_of_quarter";
      titleTemplate     = "[{period}] AWS Permission Matrix Review";
      description       = "Quarterly review of AWS IAM permissions and access rights.";
      issueType         = "Task";
      dueDateOffsetDays = 14;
      status            = "In Progress";  # optional: transition ticket to this status after creation
    };
    security-scan = {
      schedule          = "first_working_day_of_month";
      titleTemplate     = "[{period}] Monthly Security Scan";
      description       = ''
        Run vulnerability scan and review findings.

        Steps:
        1. Run scanner against all production hosts
        2. Review critical and high findings
        3. Create follow-up tickets for unresolved issues
      '';
      dueDateOffsetDays = 7;
    };
  };

  clients = {
    iit = {
      board           = "IIT";
      checks          = [ "aws-permission-matrix" "security-scan" ];
      tokenSecretPath = config.age.secrets.jira-token-iit.path;
    };
    acme = {
      board           = "ACM";
      checks          = [ "aws-permission-matrix" ];
      tokenSecretPath = config.age.secrets.jira-token-acme.path;
      # acme uses a different Jira instance
      jiraUrl         = "https://acme.atlassian.net";
      jiraUser        = "integration@acme.com";
    };
  };
};
```

This generates 3 systemd units:
- `jiraticketcreate-iit-aws-permission-matrix` (quarterly)
- `jiraticketcreate-iit-security-scan` (monthly)
- `jiraticketcreate-acme-aws-permission-matrix` (quarterly, acme Jira)

## Options

### Module level

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `enable` | bool | — | `false` | Enable the service |
| `jiraUrl` | str | yes | — | Default Jira base URL for all clients |
| `jiraUser` | str | yes | — | Default Jira user email for all clients |

### `checkTypes.<name>`

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `schedule` | string or `{ calendar }` | yes | — | When to create the ticket (see below) |
| `titleTemplate` | str | yes | — | Ticket title; use `{period}` as placeholder |
| `description` | str | yes | — | Ticket description (plain text). Multiline Nix strings (`''...''`) are supported. |
| `issueType` | str | no | `"Task"` | Jira issue type name |
| `dueDateOffsetDays` | int | no | `0` | Days after trigger date to set as due date |
| `status` | str or null | no | `null` | Jira status to transition the ticket to after creation (e.g. `"In Progress"`). When null, no transition is performed. |

### `clients.<name>`

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `board` | str | yes | — | Jira project key (e.g. `IIT`) |
| `checks` | list of str | yes | — | Check type names to apply to this client |
| `tokenSecretPath` | str | yes | — | Path to agenix secret with raw API token |
| `jiraUrl` | str or null | no | `null` | Override module-level `jiraUrl` |
| `jiraUser` | str or null | no | `null` | Override module-level `jiraUser` |

## Schedule values

The `schedule` option accepts two forms:

### Structured frequency (string)

The systemd timer fires daily; the service script checks internally whether today is the trigger day.

| Value | Triggers on | Period string |
|-------|-------------|---------------|
| `first_working_day_of_month` | First Mon–Fri of each month | `2026-06` |
| `first_working_day_of_quarter` | First Mon–Fri of Jan/Apr/Jul/Oct | `2026-Q2` |
| `first_working_day_of_week` | Every Monday | `2026-W22` |
| `every_working_day` | Every Mon–Fri | `2026-05-26` |

### Raw calendar expression (attrset)

Scheduling is delegated entirely to systemd. The service always creates a ticket when it runs.

```nix
schedule = { calendar = "Thu *-*-* 08:00:00"; };  # every Thursday at 08:00
schedule = { calendar = "Mon-Fri *-*-* 07:30:00"; };  # every working day at 07:30
```

The period string on the calendar path is always the current date (`%Y-%m-%d`).

**Note:** "Working day" means Mon–Fri only. Public holidays are not taken into account.

## Migration from previous versions

If you used the old `frequency` and `timerCalendar` options, replace them with `schedule`:

```nix
# Before
frequency     = "first_working_day_of_month";
timerCalendar = "daily";

# After
schedule = "first_working_day_of_month";
```

```nix
# Before
frequency     = "every_working_day";
timerCalendar = "Mon-Fri *-*-* 08:00:00";

# After
schedule = { calendar = "Mon-Fri *-*-* 08:00:00"; };
```

## Age secret format

Each client requires one age-encrypted file containing the raw Jira API token (no newline, or trailing whitespace is stripped by the CLI):

```
ATATT3xFfGF0abc123xyz789...
```

Encrypt with agenix:
```bash
agenix -e secrets/jira-token-iit.age
```

## Systemd units

Units are named `jiraticketcreate-<client>-<checkType>`. Useful commands:

```bash
# View logs
journalctl -u jiraticketcreate-iit-aws-permission-matrix.service -f

# Trigger manually (ignores frequency check — runs unconditionally)
systemctl start jiraticketcreate-iit-aws-permission-matrix.service

# Check timer status
systemctl list-timers 'jiraticketcreate-*'
```

## Static config files

Each instance has a static config file written at activation time:

```
/etc/jiraticketcreate/<client>-<checkType>.json
```

This file contains the static ticket fields (board, issue_type) and is useful for debugging. The full JSON passed to the CLI is assembled at runtime in the service script.

## Infrastructure requirements

No additional AWS infrastructure is required. The service calls the Jira API directly using the credentials from the agenix secret.

If the host has outbound network restrictions, ensure HTTPS traffic to the configured `jiraUrl` is allowed.
