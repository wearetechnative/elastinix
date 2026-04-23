## 1. Module Structure

- [x] 1.1 Create `modules/nixos/services/service-postfix-relay-aws.nix` module file
- [x] 1.2 Define module structure with imports and `with lib` statement
- [x] 1.3 Create local `cfg` binding for `config.elastinix.services.postfix-relay-aws`

## 2. Module Options

- [x] 2.1 Create `enable` option under `elastinix.services.postfix-relay-aws` namespace
- [x] 2.2 Add `sesEndpoint` option (type: str, example: "email-smtp.eu-west-1.amazonaws.com")
- [x] 2.3 Add `sesPort` option (type: port, default: 587)
- [x] 2.4 Add `credentialsFile` option (type: path, description: path to SASL credentials)
- [x] 2.5 Add `trustedNetworks` option (type: listOf str, default: ["127.0.0.0/8", "::1/128"])
- [x] 2.6 Add `rootAlias` option (type: str, example: "sysadmin@example.com")
- [x] 2.7 Add `defaultSenderAddress` option (type: str, example: "noreply@example.com")
- [x] 2.8 Add `senderMaps` option (type: attrsOf str, default: {})
- [x] 2.9 Add `messageSizeLimit` option (type: int, default: 10485760)

## 3. Postfix Configuration

- [x] 3.1 Configure `services.postfix.enable = true` in config section
- [x] 3.2 Set `services.postfix.relayHost` to `cfg.sesEndpoint`
- [x] 3.3 Set `services.postfix.relayPort` to `cfg.sesPort`
- [x] 3.4 Set `services.postfix.networks` to `cfg.trustedNetworks`
- [x] 3.5 Set `services.postfix.hostname` to `config.networking.hostName`
- [x] 3.6 Set `services.postfix.domain` from extracted domain in `cfg.defaultSenderAddress`

## 4. SASL Authentication Configuration

- [x] 4.1 Add `smtp_sasl_auth_enable = "yes"` to `services.postfix.config`
- [x] 4.2 Add `smtp_sasl_security_options = "noanonymous"` to `services.postfix.config`
- [x] 4.3 Add `smtp_sasl_password_maps = "hash:/var/lib/postfix/sasl_passwd"` to `services.postfix.config`

## 5. TLS Configuration

- [x] 5.1 Add `smtp_use_tls = "yes"` to `services.postfix.config`
- [x] 5.2 Add `smtp_tls_security_level = "encrypt"` to `services.postfix.config`
- [x] 5.3 Add `smtp_tls_note_starttls_offer = "yes"` to `services.postfix.config`

## 6. Address Rewriting Configuration

- [x] 6.1 Add `smtp_generic_maps = "hash:/var/lib/postfix/generic"` to `services.postfix.config`
- [x] 6.2 Add `alias_maps = "hash:/var/lib/postfix/aliases"` to `services.postfix.config`

## 7. SES Compliance Settings

- [x] 7.1 Add `message_size_limit` to `services.postfix.config` using `toString cfg.messageSizeLimit`
- [x] 7.2 Add `default_destination_concurrency_limit = "2"` to `services.postfix.config`
- [x] 7.3 Add `default_destination_rate_delay = "1s"` to `services.postfix.config`

## 8. Bounce Handling Configuration

- [x] 8.1 Add `bounce_notice_recipient` to `services.postfix.config` set to `cfg.rootAlias`
- [x] 8.2 Add `2bounce_notice_recipient` to `services.postfix.config` set to `cfg.rootAlias`
- [x] 8.3 Add `error_notice_recipient` to `services.postfix.config` set to `cfg.rootAlias`

## 9. Postfix Map Files Generation

- [x] 9.1 Create `services.postfix.mapFiles.generic` with sender rewriting rules
- [x] 9.2 Add specific senderMaps entries from `cfg.senderMaps` to generic map
- [x] 9.3 Add catch-all regex rule to rewrite addresses without domain to `cfg.defaultSenderAddress`
- [x] 9.4 Create `services.postfix.mapFiles.aliases` with root, postmaster, and mailer-daemon aliases
- [x] 9.5 Set all aliases to forward to `cfg.rootAlias`

## 10. SASL Credentials Setup Service

- [x] 10.1 Create `systemd.services.postfix-setup-sasl` service
- [x] 10.2 Set service description to "Setup Postfix SASL credentials for AWS SES"
- [x] 10.3 Add `before = [ "postfix.service" ]` to service
- [x] 10.4 Add `wantedBy = [ "multi-user.target" ]` to service
- [x] 10.5 Write script to install credentials file with correct permissions (mode 600, owner postfix)
- [x] 10.6 Add postmap command to generate hashed credentials database
- [x] 10.7 Set serviceConfig.Type to "oneshot"
- [x] 10.8 Set serviceConfig.RemainAfterExit to true

## 11. Documentation

- [x] 11.1 Create `docs/services/postfix-relay-aws.md` documentation file
- [x] 11.2 Add overview section explaining centralized relay architecture
- [x] 11.3 Add ASCII diagram showing VPC network architecture with relay host
- [x] 11.4 Document prerequisites (SES identity verification, agenix setup)
- [x] 11.5 Add complete configuration example with all required options
- [x] 11.6 Document sender rewriting scenarios (root mail, app mail, verified domains)
- [x] 11.7 Add security section explaining mynetworks and AWS Security Groups
- [x] 11.8 Document SES compliance settings (message size, rate limits)
- [x] 11.9 Add testing section with example mail commands
- [x] 11.10 Document troubleshooting steps (logs, connectivity, credentials)
- [x] 11.11 Add future enhancements section (multi-instance wishlist)
- [x] 11.12 Update `docs/README.md` to add link to postfix-relay-aws service

## 12. Testing

- [x] 12.1 Test module evaluation with `nix eval .#nixosConfigurations.test.config.elastinix.services.postfix-relay-aws`
- [x] 12.2 Create minimal test configuration in a temporary file
- [x] 12.3 Verify all required options are present and have correct types
- [x] 12.4 Verify default values are set correctly
- [x] 12.5 Test that Postfix configuration is generated correctly
- [x] 12.6 Verify map files are created with correct content
- [x] 12.7 Verify systemd service dependencies are correct
