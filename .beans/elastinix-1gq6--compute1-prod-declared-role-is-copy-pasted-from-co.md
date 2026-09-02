---
# elastinix-1gq6
title: compute1-prod declared role is copy-pasted from compute5-prod
status: completed
type: bug
priority: normal
created_at: 2026-08-28T13:07:25Z
updated_at: 2026-08-28T14:43:11Z
parent: elastinix-p9gu
---

Both hosts declare the identical HASP role fact:

  role = "shared services host: chotto, vulnix-scan";

compute1-prod does not run chhoto or the vulnix scan. Its in-use evidence shows
docker-twenty, docker-solidtime-app, docker-solidtime-queue,
docker-solidtime-scheduler, docker-gotenberg, prod-psql-backup and
prod-psql-backup-twenty. compute5-prod is the chhoto and scanner host.

"chotto" is also a typo for "chhoto".

This matters more than a typo. role is a DECLARED fact, the human-attested half of
the profile, published under "Reviewed by Luca Kasper on 2026-08-28". An auditor
weighs declared facts precisely because a person signed them, so a wrong one
undermines the attestation on the correct ones.

HASP cannot catch this: declared facts are unvalidated by design, which is the
tradeoff for them being human judgement rather than derivation.

Fix: correct the role in stack/ec2_compute1/nix/hostconf.nix and re-attest.
