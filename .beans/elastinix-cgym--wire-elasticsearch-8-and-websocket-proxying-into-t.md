---
# elastinix-cgym
title: Wire Elasticsearch 8 and websocket proxying into the zammad module
status: completed
type: task
priority: normal
created_at: 2026-10-19T14:05:04Z
updated_at: 2026-10-19T18:59:06Z
parent: elastinix-gt7k
---

In service-zammad.nix: use the vendored Elasticsearch 8 as services.elasticsearch.package, drop the ingest-attachment plugin (built in since 8.4), disable xpack security/ML for the local-only node, avoid the module's ES7-only gateway.auto_import_dangling_indices by setting single-node via extraConf. Proxy /ws and /cable with websocket upgrades and send X-Forwarded-Proto (Zammad 7.2 breaking changes).

- [x] elasticsearch wiring
- [x] nginx locations
- [x] eval check

## Summary of Changes

- service-zammad.nix runs the vendored Elasticsearch 8.19.23 (callPackage inside the module, pkgs.elasticsearch unchanged), single_node = false with discovery.type: single-node in extraConf (avoids the ES7-only gateway.auto_import_dangling_indices), xpack security and ML off, no plugins.
- nginx vhost: / with recommendedProxySettings, /cable (web port) and /ws (websocket port) with proxyWebsockets; ports from services.zammad.{port,websocketPort}; ACME and forceSSL unchanged.
- Verified by eval and by the zammad-vm test.
