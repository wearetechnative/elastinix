## Context

Applications running in AWS VPCs need to send email through AWS SES, but configuring each host individually is inefficient and error-prone. This design implements a centralized mail relay architecture where all hosts in a VPC send mail to a dedicated relay host, which then forwards to AWS SES with proper authentication and address rewriting.

Current state:
- Elastinix has multiple service modules following established patterns (jirasync, cloudwatch-agent, etc.)
- Services use the `elastinix.services.<name>` namespace with an `enable` option
- Secrets are managed via agenix
- NixOS already provides a `services.postfix` module that can be configured

Key constraints:
- Must use native NixOS Postfix module (no wrapper services)
- Must avoid circular dependencies between service config and agenix secrets
- AWS SES requires verified sender identities (prerequisite)
- AWS SES has 10MB message size limit and rate limits

## Goals / Non-Goals

**Goals:**
- Provide a simple, opinionated configuration for Postfix as an AWS SES relay
- Implement defense-in-depth security (network filtering + TLS encryption)
- Support sender address rewriting for SES compliance
- Enable centralized credential management via agenix
- Follow existing Elastinix service module patterns
- Keep configuration minimal for common use cases

**Non-Goals:**
- Multi-instance support (single relay per host) - future enhancement
- SES identity verification automation (prerequisite, manual setup)
- Bounce handling beyond forwarding to rootAlias
- Custom Postfix features beyond SES relay functionality
- Support for non-SES SMTP relays

## Decisions

### Decision 1: Use Native NixOS Postfix Module

**Choice:** Configure `services.postfix` directly rather than creating a wrapper service or custom systemd unit.

**Rationale:**
- NixOS Postfix module already handles systemd service, configuration file generation, and security
- Reduces complexity and maintenance burden
- Inherits upstream security hardening
- Users familiar with NixOS Postfix can understand the configuration

**Alternatives considered:**
- Custom systemd service: Would duplicate NixOS module work, harder to maintain
- Wrapper module that calls NixOS module: Unnecessary abstraction layer

**Implementation:**
```nix
config = mkIf cfg.enable {
  services.postfix = {
    enable = true;
    relayHost = cfg.sesEndpoint;
    relayPort = cfg.sesPort;
    networks = cfg.trustedNetworks;
    config = {
      # Postfix main.cf settings
    };
  };
};
```

### Decision 2: SASL Credentials via Systemd Setup Service

**Choice:** Create a `postfix-setup-sasl.service` oneshot unit that copies and hashes the agenix credentials file before Postfix starts.

**Rationale:**
- Postfix needs hashed credentials (`postmap` output)
- Agenix secrets are available at `/run/agenix/*` at boot
- Setup service ensures credentials are ready before Postfix starts
- Avoids inline credential generation in module evaluation

**Alternatives considered:**
- Hash credentials during module evaluation: Can't run `postmap` at eval time
- Use systemd `LoadCredential=`: Doesn't handle `postmap` hashing requirement
- Manual `postmap` via activation script: Less declarative, harder to debug

**Implementation:**
```nix
systemd.services.postfix-setup-sasl = {
  before = [ "postfix.service" ];
  wantedBy = [ "multi-user.target" ];
  script = ''
    install -D -m 600 -o postfix -g postfix \
      ${cfg.credentialsFile} /var/lib/postfix/sasl_passwd
    ${pkgs.postfix}/bin/postmap /var/lib/postfix/sasl_passwd
  '';
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
  };
};
```

### Decision 3: Sender Rewriting with Generic Maps

**Choice:** Use Postfix `smtp_generic_maps` for sender address rewriting.

**Rationale:**
- `smtp_generic_maps` rewrites envelope sender on outbound SMTP (ideal for relay)
- Supports pattern matching (e.g., `root@` matches any domain)
- Allows per-user mappings with catch-all fallback
- Standard Postfix feature, well-documented

**Alternatives considered:**
- `canonical_maps`: Rewrites both incoming and outgoing (too broad)
- `sender_canonical_maps`: Rewrites envelope only (doesn't handle header FROM)
- Custom rewriting script: Unnecessary complexity

**Implementation:**
```nix
mapFiles.generic = pkgs.writeText "postfix-generic" (
  concatStringsSep "\n" (
    (mapAttrsToList (from: to: "${from} ${to}") cfg.senderMaps)
    ++ [ "/.+@[^.]+$/ ${cfg.defaultSenderAddress}" ]  # Catch-all regex
  )
);
```

### Decision 4: Single Instance Design (Multi-Instance Future)

**Choice:** Implement single-instance configuration for v1, design for future multi-instance support.

**Rationale:**
- Common case: one relay host with one SES endpoint
- Simpler initial implementation and testing
- Can add `instances` attrset later following jirasync pattern
- No breaking changes when adding multi-instance

**Alternatives considered:**
- Multi-instance from start: Over-engineering for common case
- Never support multi-instance: Limits future flexibility

**Migration path:**
When adding multi-instance support:
```nix
# Current (v1):
elastinix.services.postfix-relay-aws.enable = true;
elastinix.services.postfix-relay-aws.sesEndpoint = "...";

# Future (v2):
elastinix.services.postfix-relay-aws.enable = true;
elastinix.services.postfix-relay-aws.instances.production = {
  sesEndpoint = "...";
};
```

### Decision 5: Network Security via mynetworks Only

**Choice:** Implement network filtering via Postfix `mynetworks` configuration, document AWS Security Group recommendations separately.

**Rationale:**
- Postfix `mynetworks` is standard SMTP relay security
- AWS Security Groups are infrastructure-level, managed outside NixOS
- Separation of concerns: service module vs cloud infrastructure
- Users can apply defense-in-depth with both layers

**Alternatives considered:**
- Configure security groups via Terraform in module: Out of scope, infrastructure as code should be separate
- No network filtering: Insecure, creates open relay risk

**Documentation requirement:**
Include architecture diagram showing both layers:
1. AWS Security Group (ingress: VPC only, egress: SES only)
2. Postfix mynetworks (accept from: trustedNetworks)

### Decision 6: Default Values for Common Configuration

**Choice:** Provide sensible defaults for most options.

**Rationale:**
- Reduces boilerplate for common cases
- SES has standard settings (port 587, 10MB limit, rate limiting)
- Localhost-only default for `trustedNetworks` is secure by default

**Defaults:**
- `sesPort`: 587 (STARTTLS, most common)
- `trustedNetworks`: ["127.0.0.0/8", "::1/128"] (localhost only)
- `messageSizeLimit`: 10485760 (10MB, SES maximum)
- Rate limits: concurrency=2, delay=1s (SES safe defaults)

**Required options (no defaults):**
- `sesEndpoint`: Region-specific
- `credentialsFile`: User must provide agenix secret
- `rootAlias`: Deployment-specific
- `defaultSenderAddress`: Must be SES-verified

## Risks / Trade-offs

### Risk: Circular Dependency with Agenix Secrets

**Risk:** If service config references agenix secret owner/group from service config, creates infinite recursion.

**Mitigation:**
- Service default user/group is `root` (hardcoded)
- Documentation explicitly shows agenix secret configuration:
  ```nix
  age.secrets.ses-smtp = {
    file = ./secrets/ses-smtp.age;
    owner = "postfix";  # Hardcoded, not cfg.user
    group = "postfix";
  };
  ```
- Follow existing jirasync pattern (learned this lesson)

### Risk: Unverified Sender Addresses

**Risk:** User configures sender addresses not verified in AWS SES, causing delivery failures.

**Mitigation:**
- Documentation clearly states SES identity verification as prerequisite
- Include example of verifying identities in AWS
- Error messages from SES will indicate verification issues
- Consider future enhancement: validation warning at build time

### Risk: Rate Limit Exceeded (SES Sandbox)

**Risk:** Users in SES sandbox mode (1 email/sec, 200/day) may hit limits.

**Mitigation:**
- Configure conservative default rate limits (delay=1s, concurrency=2)
- Documentation explains sandbox vs production limits
- Users can adjust `messageSizeLimit` and rate settings if needed
- Postfix queue will hold messages during rate limiting

### Risk: Postfix Configuration Complexity

**Risk:** Postfix has many configuration options; incorrect settings could break email.

**Mitigation:**
- Use well-tested, minimal configuration for SES relay use case
- Leverage NixOS Postfix module's validation and defaults
- Provide complete, tested examples in documentation
- Keep configuration opinionated (don't expose every Postfix knob)

### Trade-off: Single Instance Limitation

**Trade-off:** v1 only supports one SES endpoint per host.

**Justification:**
- Common case: one relay, one SES endpoint
- Simpler to implement and test
- Can add multi-instance later without breaking changes
- Noted as wishlist item in documentation

## Migration Plan

### Deployment Steps

1. **Create and encrypt SES credentials**
   ```bash
   # Create credentials file
   echo '[email-smtp.region.amazonaws.com]:587 AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG' > ses-smtp-creds

   # Encrypt with agenix
   agenix -e secrets/ses-smtp.age
   ```

2. **Add service configuration to NixOS config**
   ```nix
   elastinix.services.postfix-relay-aws = {
     enable = true;
     sesEndpoint = "email-smtp.eu-west-1.amazonaws.com";
     credentialsFile = config.age.secrets.ses-smtp.path;
     trustedNetworks = [ "10.0.0.0/16" "127.0.0.0/8" ];
     rootAlias = "sysadmin@example.com";
     defaultSenderAddress = "noreply@example.com";
   };

   age.secrets.ses-smtp = {
     file = ./secrets/ses-smtp.age;
     owner = "postfix";
     group = "postfix";
   };
   ```

3. **Deploy to relay host**
   ```bash
   nixos-rebuild switch
   ```

4. **Verify service started**
   ```bash
   systemctl status postfix-setup-sasl.service
   systemctl status postfix.service
   ```

5. **Test email delivery**
   ```bash
   echo "Test" | mail -s "Test from relay" test@example.com
   tail -f /var/log/mail.log
   ```

6. **Configure application servers** to use relay host as SMTP server

### Rollback Strategy

If issues occur:
1. **Disable service**: Set `enable = false`, rebuild
2. **Check logs**: `journalctl -u postfix.service`, `/var/log/mail.log`
3. **Verify credentials**: Check agenix decryption and file permissions
4. **Network debugging**: Test connectivity to SES endpoint
5. **Revert to previous config**: Use NixOS generations

### Testing Plan

**Unit testing (manual verification):**
- [ ] Service enables and starts successfully
- [ ] Credentials are hashed correctly
- [ ] Network filtering rejects unauthorized hosts
- [ ] Sender addresses are rewritten as configured
- [ ] Root aliases forward correctly
- [ ] TLS connection to SES succeeds
- [ ] Message size limits enforced
- [ ] Rate limiting applied

**Integration testing:**
- [ ] Send mail from application server through relay
- [ ] Verify delivery to external recipient
- [ ] Test bounce handling
- [ ] Verify logs show proper sender rewriting

## Open Questions

### Question 1: Hostname Configuration

Should the module automatically configure `services.postfix.hostname` and `services.postfix.domain`?

**Options:**
- Auto-configure from `config.networking.hostName` and `defaultSenderDomain`
- Require explicit configuration
- Use Postfix defaults

**Recommendation:** Auto-configure for convenience:
```nix
services.postfix.hostname = config.networking.hostName;
services.postfix.domain = cfg.defaultSenderDomain;
```

### Question 2: Virtual Alias Domains

Should we support SES virtual alias domains (multiple sending domains)?

**Current approach:** Single `defaultSenderAddress` and `senderMaps`

**Enhancement:** Add `virtualAliasDomains` option for multi-domain setups

**Decision:** Defer to future enhancement (v2) unless user need arises.

### Question 3: Monitoring Integration

Should this module integrate with existing Elastinix monitoring (systemd-monitoring, CloudWatch)?

**Options:**
- Add Postfix queue monitoring to systemd-monitoring
- Add CloudWatch metrics for mail queue size
- Leave monitoring as separate configuration

**Recommendation:** Document monitoring separately, don't auto-enable. Users can add:
```nix
elastinix.services.systemd-monitoring.services = [
  "postfix.service"
];
```
