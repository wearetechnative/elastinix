---
# elastinix-vtja
title: Rename buildTime to lastUpdated in hostinfo JSON and update lambda
status: todo
type: task
created_at: 2026-05-11T12:47:06Z
updated_at: 2026-05-11T12:47:06Z
---

The hostinfo service JSON currently uses the field name `buildTime`. This should be renamed to `lastUpdated` for clarity.\n\nRequired changes:\n1. Rename `buildTime` to `lastUpdated` in the hostinfo service JSON output (elastinix repo)\n2. Update lambda `elastinix_services_monitor_prod` in repo https://github.com/TechNative-B-V/technative-awsaccounts-workloads.git to use the new field name
