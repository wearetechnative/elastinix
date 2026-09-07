---
# elastinix-8hwr
title: retarget-pr-32-to-nixos-26-05
status: completed
type: task
priority: high
created_at: 2026-09-04T12:07:11Z
updated_at: 2026-09-04T13:06:13Z
parent: elastinix-sfmm
---

PR #32 currently targets base `nixos-25.11`, which the compute does not consume and where the oauth2-proxy module cannot evaluate. Retarget it to base `nixos-26.05` (or close #32 and open a fresh PR from the port branch against nixos-26.05). Update the PR body to reflect the two-file design and 26.05-only scope.

Repo: wearetechnative/elastinix (GitHub PR).

## Summary of Changes

Closed PR #32 (base nixos-25.11, superseded) and opened PR #33 (base nixos-26.05, head feature/prometheus-alertmanager-cognito-auth-2605) with the ported two-file design. #32 got a comment pointing to #33 and explaining the 26.05-only rationale.
