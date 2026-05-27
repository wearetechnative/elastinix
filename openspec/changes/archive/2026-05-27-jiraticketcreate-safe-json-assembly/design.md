## Context

The `mkScript` function in `service-jiraticketcreate.nix` builds a JSON config file at runtime using a bash heredoc with direct Nix string interpolation:

```bash
cat > "$TMPFILE" << JIRAEOF
{
  "ticket": {
    "description": "${ct.description}",
    "title": "$TITLE",
    ...
  }
}
JIRAEOF
```

Both build-time values (Nix strings like `ct.description`, `ct.issueType`) and runtime variables (`$TITLE`, `$DUE_DATE`) are interpolated without escaping. Any value containing `"`, `\`, or newlines produces invalid JSON and silently creates a broken config file.

## Goals / Non-Goals

**Goals:**
- All string fields in the JSON payload are safely escaped regardless of content
- Multiline `description` values work correctly
- No user-facing option changes — fully backwards compatible

**Non-Goals:**
- Changing the JSON structure consumed by the `jiraticketcreate` CLI
- Adding new ticket fields
- Validating Nix-level option values (e.g. rejecting quotes in titleTemplate)

## Decisions

### Decision: Use `jq -n --arg` for all fields

Replace the heredoc with:

```bash
${pkgs.jq}/bin/jq -n \
  --arg url    "${effectiveJiraUrl}" \
  --arg user   "${effectiveJiraUser}" \
  --arg token  "${instance.client.tokenSecretPath}" \
  --arg board  "${instance.client.board}" \
  --arg title  "$TITLE" \
  --arg desc   "${ct.description}" \
  --arg itype  "${ct.issueType}" \
  --arg due    "$DUE_DATE" \
  '{
    api:    { url: $url, user: $user, token_file: $token },
    ticket: { board: $board, title: $title, description: $desc,
              issue_type: $itype, due_date: $due }
  }' > "$TMPFILE"
```

`jq --arg` always produces a valid JSON string regardless of content. Both build-time Nix interpolations and runtime bash variables go through the same safe path.

**Alternative considered: `builtins.toJSON` for build-time fields only.**
Rejected — only fixes static fields, leaves `$TITLE` and `$DUE_DATE` unescaped, creates an inconsistent mixed pattern.

**Alternative considered: Python/bash manual escaping.**
Rejected — fragile, requires maintaining escape logic ourselves.

### Decision: Reference `pkgs.jq` by absolute store path

Use `${pkgs.jq}/bin/jq` directly in the script rather than adding jq to `PATH`. This is consistent with how `jiraticketcreatePackage` is referenced and requires no `environment` changes to the systemd service.

## Risks / Trade-offs

- **jq added as runtime dependency** → `pkgs.jq` is in nixpkgs stable, well-maintained, negligible closure size impact.
- **Description with `JIRAEOF` literal** → `jq --arg` handles this correctly; the heredoc is gone so no delimiter collision risk.
- **`ct.description` multiline in Nix interpolation** → Nix interpolates the string verbatim into the bash `--arg` value, which is safe because jq reads it as a shell argument, not inline JSON.

## Migration Plan

1. Update `mkScript` in `modules/nixos/services/service-jiraticketcreate.nix`
2. Update `docs/services/jiraticketcreate.md` to document multiline support
3. Run `nix flake check` to verify

No migration required for existing configurations — the change is internal to the script.
