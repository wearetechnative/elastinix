---
# elastinix-8hwr
title: retarget-pr-32-to-nixos-26-05
status: in-progress
type: task
priority: high
created_at: 2026-09-04T12:07:11Z
updated_at: 2026-09-04T13:01:21Z
parent: elastinix-sfmm
---

PR #32 currently targets base `nixos-25.11`, which the compute does not consume and where the oauth2-proxy module cannot evaluate. Retarget it to base `nixos-26.05` (or close #32 and open a fresh PR from the port branch against nixos-26.05). Update the PR body to reflect the two-file design and 26.05-only scope.

Repo: wearetechnative/elastinix (GitHub PR).
