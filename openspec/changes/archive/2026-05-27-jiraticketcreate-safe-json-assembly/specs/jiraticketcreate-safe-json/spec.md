## ADDED Requirements

### Requirement: JSON payload is safely assembled for all string values
The `jiraticketcreate` service script SHALL use `jq -n --arg` to assemble the JSON config payload, ensuring all field values are correctly escaped regardless of content (newlines, quotes, backslashes, special characters).

#### Scenario: Multiline description produces valid JSON
- **WHEN** `description` contains literal newlines (multiline Nix string)
- **THEN** the generated JSON file is valid and the description field contains the full multiline text

#### Scenario: Description with quotes produces valid JSON
- **WHEN** `description` contains double quotes or backslashes
- **THEN** the generated JSON file is valid and the characters are properly escaped

#### Scenario: Title with special characters produces valid JSON
- **WHEN** the resolved `$TITLE` (after period substitution) contains quotes or special characters
- **THEN** the generated JSON file is valid

### Requirement: jq referenced by absolute store path
The script SHALL reference jq as `${pkgs.jq}/bin/jq` (absolute Nix store path), not via PATH lookup.

#### Scenario: jq invocation does not depend on PATH
- **WHEN** the systemd service executes with a minimal PATH
- **THEN** jq is found and executes correctly via its absolute store path

## MODIFIED Requirements

### Requirement: description supports multiline strings
The `checkTypes.<name>.description` option SHALL accept multiline Nix strings. The value SHALL be transmitted to Jira verbatim including newlines.

#### Scenario: Multiline description in NixOS config
- **WHEN** `description` is set to a multiline Nix string using `''...''` syntax
- **THEN** the Jira ticket is created with the full multiline text in the description field
