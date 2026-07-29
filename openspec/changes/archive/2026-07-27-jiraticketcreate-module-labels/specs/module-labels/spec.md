## ADDED Requirements

### Requirement: Fixed module label always applied

The module SHALL always include `"jiraticketcreate-elastinix"` as a label on every ticket it creates, regardless of user configuration.

#### Scenario: No user labels configured
- **WHEN** `checkType.labels` is not set or is `[]`
- **THEN** the generated JSON config SHALL contain `"labels": ["jiraticketcreate-elastinix"]`

#### Scenario: User labels configured
- **WHEN** `checkType.labels` is `["compliance", "automated"]`
- **THEN** the generated JSON config SHALL contain `"labels": ["jiraticketcreate-elastinix", "compliance", "automated"]`

### Requirement: Optional extra labels per checkType

The `checkTypes` submodule SHALL accept an optional `labels` field of type `listOf str` with default `[]`. These labels are appended after the fixed module label.

#### Scenario: labels option absent from checkType definition
- **WHEN** the user does not set `labels` on a `checkType`
- **THEN** only the fixed module label is sent to the Jira API
