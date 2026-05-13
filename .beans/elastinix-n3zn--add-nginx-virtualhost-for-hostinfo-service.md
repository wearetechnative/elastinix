---
# elastinix-n3zn
title: Add nginx virtualHost for hostinfo service
status: todo
type: task
created_at: 2026-05-11T12:48:48Z
updated_at: 2026-05-11T12:48:48Z
---

The hostinfo service currently exposes JSON directly via firewall on port 3333.\n\nAdd an nginx virtualHost so the service is also accessible via HTTPS at a domain URL.\n\nRequired changes:\n1. Add optional nginx virtualHost config to elastinix.services.hostinfo module\n2. Add option e.g. `nginxDomain` or use `environment_domain` tfvars pattern\n3. Configure proxyPass to localhost:${port}\n4. Enable ACME/SSL via the standard elastinix nginx pattern\n5. Update docs for the hostinfo service
