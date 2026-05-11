# Claude Context: Elastinix Development

This document provides context for AI assistants working on the Elastinix project. It captures key decisions, patterns, and implementation details from development sessions.

## Project Overview

Elastinix is a NixOS flake providing shared build code for the NixOS product family on AWS cloud. It includes reusable NixOS services and deployment tooling.

**Repository**: https://github.com/wearetechnative/elastinix

## Key Design Patterns

### Service Structure

All Elastinix services follow these conventions:

1. **Namespace**: `elastinix.services.<service-name>`
2. **Enable option**: Every service has a top-level `enable` boolean
3. **Security**: Services run with systemd security hardening by default
4. **Secrets**: Sensitive configuration uses agenix for encryption
5. **Documentation**: Each service has detailed docs in `docs/services/<service-name>.md`

### Multi-Instance Services

Pattern for services that need multiple instances:

```nix
elastinix.services.<service-name> = {
  enable = true;
  instances = {
    instance-name-1 = {
      # Instance-specific configuration
    };
    instance-name-2 = {
      # Instance-specific configuration
    };
  };
};
```

**Benefits**:
- Cleaner than `attrsOf` at top level
- Similar to systemd-monitoring pattern
- Single enable for all instances
- Easy to add/remove instances

## Jira Sync Service

### Purpose

One-way synchronization of Jira issues from client/remote boards to organization boards. Enables better DevOps workflows when working with external clients.

**Key points**:
- ONE-WAY sync (client → organization)
- Single API token from target organization user
- User must have access to both Jira instances
- Clear source/target separation in configuration

### Evolution

#### 1. Initial Implementation (service-jirasync-iit-tn.nix)
- Started as single-instance service
- Hardcoded for specific client (iit-tn)
- Local Python script in `services-scripts/`

#### 2. Generic Service (service-jirasync.nix)
- Renamed to generic jirasync
- Still single instance
- Moved to fetching from GitHub

#### 3. Multi-Instance Support
- Changed to `attrsOf submodule` structure
- Encountered infinite recursion issues with age secrets
- Problem: Circular dependency between service config and age secrets

#### 4. Current Structure (Final)
- Multi-instance via `instances` suboption
- Age secrets use hardcoded user/group to avoid circular dependency
- Flake input for jirasync package
- Default user/group: `root`

### Configuration Structure

**JSON Configuration File**:

```json
{
  "source_jira_url": "https://client-company.atlassian.net",
  "source_project_key": "CLIENT",
  "source_board_id": 123,
  "target_jira_url": "https://your-company.atlassian.net",
  "target_jira_user": "jirasync-service@your-company.com",
  "target_jira_token": "ATATT3xFfGF0...",
  "target_project_key": "INT",
  "target_board_id": 456,
  "status_mapping": {
    "To Do": "To Do",
    "In Progress": "In Progress",
    "Done": "Done"
  }
}
```

**Key Design Decision**: All fields have `source_` or `target_` prefix for clarity. The credentials (`target_jira_user`, `target_jira_token`) belong to the target organization, not source.

### Avoiding Circular Dependencies

**Problem**: When using multi-instance services with age secrets, circular dependencies can occur:
```
service config → age secret path → age secret owner/group → service config
```

**Solution**: Hardcode age secret owner/group instead of referencing service config:
```nix
# BAD - Creates circular dependency
age.secrets.jirasync-client = {
  owner = config.elastinix.services.jirasync.instances.client.user;
  group = config.elastinix.services.jirasync.instances.client.group;
};

# GOOD - Breaks the circle
age.secrets.jirasync-client = {
  owner = "root";  # Hardcoded, matches service default
  group = "root";
};
```

### Flake Integration

#### Why Flake Input Over fetchFromGitHub

**fetchFromGitHub** (old approach):
```nix
src = pkgs.fetchFromGitHub {
  owner = "wearetechnative";
  repo = "jirasync";
  rev = "main";
  hash = lib.fakeHash;  # Manual hash management
};
```

**Flake Input** (current approach):
```nix
# In flake.nix inputs:
jirasync.url = "github:wearetechnative/jirasync";
jirasync.inputs.nixpkgs.follows = "nixpkgs";

# In service module:
jirasyncPackage = inputs.jirasync.packages.${pkgs.system}.default;
```

**Benefits**:
- ✅ Automatic hash handling via flake lock
- ✅ Easy updates: `nix flake update jirasync`
- ✅ Users can override version
- ✅ Consistent with other elastinix dependencies
- ✅ Follows modern Nix flakes best practices

#### The "follows" Pattern

```nix
jirasync.inputs.nixpkgs.follows = "nixpkgs";
```

**What it does**: Forces jirasync to use elastinix's nixpkgs instead of its own.

**Without follows**:
```
elastinix → nixpkgs (25.11)
         → jirasync → nixpkgs (24.11)  ← Duplicate!
```

**With follows**:
```
elastinix → nixpkgs (25.11)
         → jirasync ────────┘  ← Reuses elastinix's nixpkgs
```

**Benefits**: Smaller closure, faster builds, consistent versions, no conflicts.

### Systemd Service Names

Each instance creates:
- Service: `jirasync-<instance-name>.service`
- Timer: `jirasync-<instance-name>.timer`

Example:
```nix
instances = {
  acme-corp = { ... };  # → jirasync-acme-corp.service
  globex-inc = { ... }; # → jirasync-globex-inc.service
};
```

### Documentation Conventions

**Fictional Company Names**: Use generic examples, not real client names:
- `acme-corp`, `acme-widgets` - Client organizations
- `globex-inc` - Additional client example
- `mycompany` - Your own organization

**Avoid**: Real client names, internal project codes (e.g., "iit-tn")

## File Structure

```
elastinix/
├── docs/
│   ├── README.md                    # Services overview
│   └── services/
│       └── jirasync.md             # Jirasync documentation
├── modules/
│   └── nixos/
│       ├── services/
│       │   └── service-jirasync.nix  # Service implementation
│       └── services-scripts/        # (deprecated - moved to separate repo)
├── flake.nix                        # Main flake with inputs
└── CLAUDE.md                        # This file
```

## External Dependencies

### Jirasync Repository
- **URL**: https://github.com/wearetechnative/jirasync
- **Purpose**: Python script for Jira synchronization
- **Structure**: Standalone flake with package output
- **Version**: 1.0.0 (see VERSION and CHANGELOG.md)

## Common Issues & Solutions

### Issue: Infinite Recursion in Module
**Symptom**: `error: infinite recursion encountered` when building
**Cause**: Circular dependency between service config and age secrets
**Solution**: Hardcode age secret owner/group instead of referencing service config

### Issue: Script Not Found
**Symptom**: `cp: cannot stat 'services-scripts/jirasync.py'`
**Cause**: Script moved to separate repository
**Solution**: Use flake input instead of local script

### Issue: Hash Mismatch
**Symptom**: Hash mismatch error with fetchFromGitHub
**Cause**: Manual hash management is error-prone
**Solution**: Use flake input with automatic hash handling via flake lock

## Development Workflow

### Git Commit Conventions

**IMPORTANT**: Never include Co-Authored-By credits for AI agents in git commits.

- ❌ **Never use**: `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`
- ❌ **Never use**: Any AI agent attribution in commits
- ✅ **Do use**: Standard commit messages without AI attribution
- ✅ **Do use**: Descriptive commit messages that explain what and why

Git commits should reflect human contributions only. AI assistance is a development tool, not a co-author.

### Adding a New Service

1. **Create service module**: `modules/nixos/services/service-<name>.nix`
2. **Follow conventions**:
   - Namespace: `elastinix.services.<name>`
   - Include `enable` option
   - Add systemd security hardening
   - Support agenix for secrets
3. **Write documentation**: `docs/services/<name>.md`
4. **Update docs index**: Add link in `docs/README.md`
5. **Test**: Build and verify the service works

### Updating Jirasync

```bash
# In elastinix repository
cd /path/to/elastinix
nix flake update jirasync
git add flake.lock
git commit -m "Update jirasync to latest version"
```

## Security Considerations

### Default User/Group
- **Default**: `root` for simplicity and broad permissions
- **Override**: Can specify per-instance if needed
- **Best Practice**: Use dedicated service accounts when possible

### API Token Security
- Store in age-encrypted files
- Never commit unencrypted tokens
- Rotate regularly
- Use service accounts, not personal accounts
- Follow principle of least privilege

### Systemd Hardening
All services include:
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `NoNewPrivileges=true`
- Network restrictions
- System call filtering

## Testing

### Local Testing
```bash
# Build the configuration
nix build .#packages.x86_64-linux.nonProdApply

# Check service status
systemctl status jirasync-<instance>.service

# View logs
journalctl -u jirasync-<instance>.service -f

# Manual trigger
systemctl start jirasync-<instance>.service
```

### Dry-Run Mode
Enable for testing without making changes:
```nix
instances = {
  test = {
    dryRun = true;
    # ... other config
  };
};
```

## Future Considerations

### Potential Improvements
1. **Versioned releases**: Tag jirasync releases for stability
2. **Health checks**: Add monitoring for sync failures
3. **Metrics**: Track sync performance and issue counts
4. **Incremental sync**: Only sync changed issues
5. **Bidirectional sync**: Support two-way synchronization (if needed)

### Migration Notes
If moving from old structure to new:
1. Update JSON config field names (remote_org → source_jira_url, etc.)
2. Update Python script to use new field names
3. Update service module if using old naming
4. Test with dry-run before production

## Related Documentation

- [Elastinix README](README.md)
- [Services Documentation](docs/README.md)
- [Jirasync Service Docs](docs/services/jirasync.md)
- [Jirasync Repository](https://github.com/wearetechnative/jirasync)
- [NixOS Manual - Modules](https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)

## Changelog

### 2026-03-13
- Initial jirasync service implementation
- Multi-instance support added
- Flake input integration
- Complete documentation written
- Configuration structure finalized with source/target prefixes
- Circular dependency issues resolved

---

**Note**: This document should be updated as the project evolves. Keep it current with major design decisions and patterns.
- always remember openspec settings and documents
- never add claude or claude-code references in git commit messages
When I refer to issues like elastinix-rn3b checkout the task
in @.beans/elastinix-rn3b*.md
In this project we will use these tasks as epics for making openspec proposals.
WHEN you create a proposal at a link to this task in the proposal.md.
WHEN a bean is used to create an proposal change the status to "in-progress"
WHEN a proposal is archived add the link to the archived proposal in the frontmatter of this task like this:
openspec-link: openspec/changes/archive/....
You are allowed to update these statuses in the task frontmatter:
in-progress
todo
draft
completed
scrapped
When making changes you are allowed to update the date/time in updated_at in the task frontmatter
Besides updating status and openspec-link, you are NOT ALLOWED to modify the contents of the task file.
Always use opsx commands when creating openspec proposals or archive proposals
All openspec documents need to be in english, not matter the language being used in the users conversation.
