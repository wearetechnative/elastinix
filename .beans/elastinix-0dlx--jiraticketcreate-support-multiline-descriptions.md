---
# elastinix-0dlx
title: 'jiraticketcreate: support multiline descriptions'
status: todo
type: task
created_at: 2026-05-26T13:49:28Z
updated_at: 2026-05-26T13:49:28Z
---

The `description` field in `checkTypes` currently does not support multiline strings. The value is embedded directly into a bash heredoc as a JSON string literal, so literal newlines break the JSON.

The fix should JSON-encode the description at build time (Nix side) or use `jq` at runtime to safely construct the JSON payload, so that newlines, quotes, and other special characters in the description are properly escaped.

Example that should work after this fix:
```nix
description = ''
  Voor implementatie test maak ik dit ticket.

  Voer dit script uit.
'';
```
