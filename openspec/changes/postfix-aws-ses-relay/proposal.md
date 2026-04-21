## Why

Many applications running on AWS need to send email (notifications, alerts, reports), but configuring each host individually with AWS SES credentials is repetitive and creates security risks. A centralized mail relay host simplifies credential management, provides network-level security through subnet filtering, and ensures consistent sender address rewriting for SES compliance.

## What Changes

- Add new NixOS service module `elastinix.services.postfix-relay-aws`
- Configure native NixOS Postfix module for AWS SES relay (no wrapper service)
- Implement SASL authentication with agenix-encrypted AWS SES SMTP credentials
- Add network security via configurable trusted subnets (mynetworks)
- Implement sender address rewriting (FROM) with per-user mappings and catch-all default
- Configure local mail forwarding (TO) via rootAlias for system mail
- Set SES-compliant message size limits (10MB default) and rate limiting
- Configure bounce/error mail handling to rootAlias
- Enable TLS/STARTTLS encryption for SES connections
- Add service documentation with architecture diagrams and configuration examples

## Capabilities

### New Capabilities

- `postfix-aws-ses-relay`: NixOS service module that configures Postfix as a centralized mail relay for AWS SES, including authentication, network security, address rewriting, and SES compliance settings

### Modified Capabilities

<!-- No existing capabilities are being modified -->

## Impact

- New service module: `modules/nixos/services/service-postfix-relay-aws.nix`
- New documentation: `docs/services/postfix-relay-aws.md`
- Update service index: `docs/README.md` to include new service
- No breaking changes to existing services
- Uses native NixOS `services.postfix` module (no new dependencies)
- Requires AWS SES SMTP credentials (prerequisite: SES identities must be verified)
