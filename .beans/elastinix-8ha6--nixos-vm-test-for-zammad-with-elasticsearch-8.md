---
# elastinix-8ha6
title: NixOS VM test for zammad with Elasticsearch 8
status: completed
type: task
priority: normal
created_at: 2026-10-19T14:05:05Z
updated_at: 2026-10-19T18:59:06Z
parent: elastinix-gt7k
---

Add checks.<linux>.zammad-vm: boots elastinix.services.zammad (local PostgreSQL, Redis, Elasticsearch 8) and asserts Zammad answers, Elasticsearch reports 8.19, and zammad:searchindex:rebuild passes Zammad 7.2's version gate.

- [x] test file
- [x] wired into flake checks
- [x] passes

## Summary of Changes

- tests/zammad-vm.nix (checks.<linux>.zammad-vm) boots the real service-zammad.nix plus service-nginx.nix with stub tfvars, a local PostgreSQL, ACME/forceSSL forced off and vhost zammad.example.com (Zammad's default fqdn, accepted as ActionCable origin).
- All 7 subtests pass against Zammad 7.2.2 + Elasticsearch 8.19.23: ES version in Zammad's range; ingest-attachment bundled with no plugins; ES on loopback only; welcome page through nginx; 101 upgrades on /ws and /cable; zammad:searchindex:rebuild succeeds and creates zammad_production_* indices.
- Findings fixed on the way: JDK 21 fails ES entitlements with console-only logging (package moved to JDK 25); nginx must be enabled via elastinix.services.nginx; without KVM (TCG) the first-start DB seed outlasts zammad-web's 20 min TimeoutStartSec, so the test node raises it to 7200 s.
