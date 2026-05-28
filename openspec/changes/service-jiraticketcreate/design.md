## Context

Elastinix already has a pattern for scheduled external tools: `service-jirasync.nix` creates systemd timer + oneshot service pairs per instance, driven by NixOS module configuration. The new `service-jiraticketcreate` follows this exact pattern but adds:

1. Cross-product generation of instances from `checkTypes × clients`
2. DynamoDB-backed idempotency check before each ticket creation
3. Frequency logic (e.g. "first working day of quarter") evaluated at runtime in the systemd service script
4. `jiraticketcreate` CLI tool consumed as a flake input

## Goals / Non-Goals

**Goals:**
- NixOS module under `elastinix.services.jiraticketcreate`
- Define check types once, apply to N clients — generates N×M systemd service+timer pairs
- Daily systemd timer per instance; frequency logic inside the script decides whether to act
- Jira API token managed via agenix secret per client (`tokenSecretPath`)
- Standard elastinix systemd hardening applied

**Non-Goals:**
- No support for client-specific overrides of check type parameters
- No holiday calendar awareness for "first working day" (weekdays only: Mon–Fri)
- No retry logic — elastinix timer's `Persistent=true` handles missed runs
- No web UI or management API

## Decisions

### Cross-product instances via `lib.mapAttrs` + `lib.concatMapAttrs`
Check types and clients are declared separately. The module generates instances as the cartesian product filtered by each client's `checks` list. Instance names follow the pattern `<client>-<check-type>`.

**Alternative considered:** One flat `instances` attrset (like jirasync) — rejected because it forces repetition of frequency and description for every client, making the config hard to maintain as clients grow.

### No state tracking
The service creates a ticket on the trigger day and does not track whether a ticket was already created for a given period. If the service runs multiple times on the trigger day (e.g. due to a server restart or manual invocation), duplicate tickets may be created. This is accepted as a known limitation for v1 — the trigger day window is short and server restarts on that exact day are rare in practice.

**Alternative considered:** DynamoDB state table (PK=instance, SK=period) to prevent duplicates — rejected because it requires extra AWS infrastructure (table, IAM permissions), increases bash script complexity, and the operational overhead outweighs the benefit given the low probability of duplicate tickets. Can be added in a future version if duplicates prove to be a real problem.

### Frequency logic in bash within systemd ExecStart
The systemd service script calls a small bash function to determine the current period and whether today is the trigger day. If not trigger day: exit 0 (no-op). If trigger day: check DynamoDB, then call `jiraticketcreate`.

Supported frequencies:
- `first_working_day_of_quarter` — first Mon–Fri of Jan/Apr/Jul/Oct
- `first_working_day_of_month` — first Mon–Fri of each month
- `first_working_day_of_week` — every Monday (or next weekday if holiday, not implemented)

**Alternative considered:** Compute trigger day in Nix at build time — rejected because `OnCalendar` cannot express "first weekday of month" natively, and build-time computation doesn't know future dates.

### jiraticketcreate as flake input
```nix
inputs.jiraticketcreate = {
  url = "github:wearetechnative/jiraticketcreate";
  inputs.nixpkgs.follows = "nixpkgs";
};
```
Package accessed via `inputs.jiraticketcreate.packages.${pkgs.system}.default`.

### Jira URL and user in NixOS config; token in agenix secret
`jiraUrl` and `jiraUser` are NixOS options — defined once at module level with optional per-client override. The API token is sensitive and SHALL NOT appear in the Nix store; it is stored in an age-encrypted file and referenced via `tokenSecretPath` per client. The service script writes the full `api` block into the temp JSON at runtime, setting `api.token_file` to the agenix path. The CLI then reads the token from that file.

This matches the CLI's JSON schema exactly:
```json
{
  "api": {
    "url": "https://mycompany.atlassian.net",
    "user": "jira-service@mycompany.com",
    "token_file": "/run/agenix/jira-token-iit"
  }
}
```

Age file contents (before encryption) — raw token only:
```
ATATT3xFfGF0abc123...
```

**Alternative considered:** All credentials (URL, user, token) in one age EnvironmentFile — rejected because the CLI expects `api.token_file` (a file path), not a token value. Injecting URL and user via env vars while writing the token to a temp file adds unnecessary complexity. Keeping URL and user in NixOS config is not a security concern as they are not secrets.

### JSON config written to `/etc/jiraticketcreate/<instance>.json` at activation
The NixOS module generates the config JSON as a NixOS `environment.etc` entry. The systemd script renders the title and description (with period substituted) into a temp file at runtime and passes it to the CLI.

### Schedules in NixOS config, not in DynamoDB
Schedule definitions (`checkTypes`, `clients`, `frequency`) live in NixOS config. Adding or changing a schedule requires a NixOS rebuild and deploy — the same flow as any other infrastructure change in elastinix.

**Alternative considered:** Store schedule definitions in DynamoDB so beheerders can add schedules without a rebuild. Rejected because:
- Target users are beheerders who already perform NixOS deploys; the extra step is not a burden
- DynamoDB as a config store introduces a second management plane alongside NixOS, increasing operational complexity
- Schedule definitions in DynamoDB are not validated until runtime; NixOS catches errors (unsupported `frequency` values, missing required options) at build time
- DynamoDB would serve dual purpose (config + state), conflating two responsibilities; keeping it as state-only store maintains a single, clear responsibility
- The approach contradicts the elastinix infrastructure-as-code principle

DynamoDB remains exclusively a **state store for idempotency**.

## Risks / Trade-offs

- [IAM role missing DynamoDB permissions] → Document required IAM policy additions; deployment will fail fast with a clear AWS error
- [Working day detection ignores public holidays] → Acceptable for v1; document limitation
- [DynamoDB unavailable during run] → Service exits non-zero; `Persistent=true` timer retries next day
- [Flake input lock diverges] → Standard `nix flake update jiraticketcreate` workflow handles this

## Migration Plan

1. Add `jiraticketcreate` flake input to `flake.nix`
2. Create `modules/nixos/services/service-jiraticketcreate.nix`
3. Add IAM DynamoDB permissions to host server role
4. Create DynamoDB table `jiraticketcreate-state`
5. Configure first instance in a host's NixOS config
6. Deploy and verify ticket creation manually by setting system date to a trigger day in a test run

## Open Questions

- Should the DynamoDB table name be configurable per service instance, or global to the module?
  - Current decision: one table name configured at module level, shared by all instances
