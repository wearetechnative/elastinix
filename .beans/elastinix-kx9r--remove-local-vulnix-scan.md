---
# elastinix-kx9r
title: Remove the local vulnix scan service, replaced by the central approach
status: completed
type: task
priority: normal
created_at: 2026-07-27T00:00:00Z
updated_at: 2026-07-27T00:00:00Z
parent: elastinix-p9gu
depends_on:
  - elastinix-rdih
---

The local `elastinix.services.vulnix-scan` module is replaced by the central
scanning architecture (elastinix-rdih). The local module runs on each compute
itself and needs a roughly 2 GB NVD cache, which is too heavy for the small
computes. Once the central scanner is rolled out, the local module can go.

## What

1. Remove `modules/nixos/services/service-vulnix-scan.nix`
2. Remove the `vulnix-scan` capability spec (`openspec/specs/vulnix-scan/spec.md`)
3. Remove every reference to `elastinix.services.vulnix-scan` in downstream
   configurations (`technative-awsaccounts-workloads`)
4. Remove `vulnix` as a flake input if it was only used by the local service

## Ordering

Do this only after elastinix-rdih is fully rolled out on the scanner host, so
existing hosts never have a gap in scanning coverage.
