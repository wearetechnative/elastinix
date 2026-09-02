---
# elastinix-6hmg
title: Move the evidence report generator to the isotto repo as an ISO27001 tool
status: completed
type: task
priority: high
created_at: 2026-08-28T13:07:25Z
updated_at: 2026-08-31T10:04:12Z
parent: elastinix-p9gu
openspec-link: isotto:openspec/changes/vulnerability-management-tool
---

The Go generator currently sits at elastinix/tools/evidence-report. It belongs in isotto, which exists for collecting ISO information and data.

Target: isotto/lib/iso27001-vulnerability-management/, driven by
run-compliance-check.sh vulnerability <client>, writing to
compliance-reports/vulnerability/<client>/YYYY-MM-DD-*.md, with a config per client
under configs/vulnerability/ following the pattern of the other seven tools.

Consequences of the placement:

- The tool presents only. Mechanical verdicts and in-use qualification are decided
  in the elastinix normalizer and read from the bundle, so the report and the
  Prometheus exporter cannot disagree.
- It pulls the bundle from S3 rather than a local path.
- It needs a refusal to overwrite an existing dated report without --force, since
  the markdown is the reviewer working document once generated.
- It needs a lint step asserting the bmi isotto contract before render: line 1
  title, line 2 blank, line 3 **Control:**, chapters at ##. Every bmi extraction
  failure is silent and defaults rather than erroring.

Also delete elastinix/gen.py: the Python generator is superseded and keeping both
guarantees they drift.

## Progress, 2026-08-31

Done: `elastinix/gen.py` is deleted, so the Go tool is the only generator and the
duplicated verdict and reachability logic is gone.

Still open: the move itself. The tool sits at `elastinix/tools/evidence-report/`
and reads a local bundle. Placement was decided — isotto, because that repo exists
for collecting ISO information and data — and the consequence of that placement is
that the tool presents only: mechanical verdicts and in-use qualification are
decided in the elastinix normalizer and read from the bundle, so the report and the
Prometheus exporter cannot disagree.

Also still open, and a prerequisite for the report to be useful rather than merely
correct: a remediation SLA policy. The reviewer template has an `Actions agreed`
table pre-populated with one row per open item, and nothing to derive `Target date`
from. Roughly half a page: critical and reachable within N days, accepted risk
expiring after M months.
