## 1. Module Integration

- [x] 1.1 Verify module files are in correct location (modules/nixos/services/documenso/)
- [x] 1.2 Ensure module is importable from elastinix flake
- [x] 1.3 Add module to elastinix module list if needed
- [x] 1.4 Verify example.nix uses elastinix conventions

## 2. Documentation

- [x] 2.1 Update elastinix README to mention Documenso service
- [x] 2.2 Verify README.md follows elastinix documentation standards
- [x] 2.3 Add quickstart example to elastinix docs
- [x] 2.4 Document secret generation with agenix

## 3. Testing

- [x] 3.1 Run NixOS VM test: `nix-build modules/nixos/tests/documenso.nix`
- [x] 3.2 Verify all 10 test cases pass
- [x] 3.3 Test with agenix secret integration
- [x] 3.4 Test with external PostgreSQL
- [x] 3.5 Test S3 storage configuration
- [x] 3.6 Test BullMQ/Redis auto-enablement
- [x] 3.7 Test certificate auto-generation
- [x] 3.8 Verify systemd security hardening

## 4. Code Review

- [x] 4.1 Verify module follows elastinix coding standards
- [x] 4.2 Check that all secrets use *File options
- [x] 4.3 Verify systemd service configuration
- [x] 4.4 Review environment file generation script
- [x] 4.5 Check Redis configuration aligns with elastinix patterns
- [x] 4.6 Verify no AI co-author attribution in commits

## 5. Final Validation

- [x] 5.1 Ensure module works with pkgs.documenso from nixpkgs
- [x] 5.2 Verify no custom package derivation needed
- [x] 5.3 Test service restart and recovery
- [x] 5.4 Validate health check endpoints
- [x] 5.5 Confirm logs accessible via journalctl

## 6. Deployment Preparation

- [x] 6.1 Create example agenix secret files
- [x] 6.2 Document production deployment steps
- [x] 6.3 Add backup recommendations to README
- [x] 6.4 Document upgrade procedure
- [x] 6.5 Add troubleshooting section to README

## 7. Feature Enhancements

- [x] 7.1 Add SMTP credentialsFile option (alternative to username+passwordFile)
- [x] 7.2 Add validation assertions for SMTP credential methods
- [x] 7.3 Update environment generator to support credentialsFile
- [x] 7.4 Document SMTP credentialsFile in README
- [x] 7.5 Add SMTP credentialsFile examples to example.nix
- [x] 7.6 Update agenix secrets section in example.nix

## 8. AWS Integration Documentation

- [x] 8.1 Document AWS SES SMTP configuration (port 587 vs 465)
- [x] 8.2 Explain STARTTLS vs direct TLS configuration
- [x] 8.3 Document SES SMTP credentials vs IAM access keys
- [x] 8.4 Add S3 CORS configuration examples
- [x] 8.5 Document IAM permissions for S3 and SES
- [x] 8.6 Add stateless EC2 deployment guidance
- [x] 8.7 Document certificate management via agenix

## 9. Troubleshooting Documentation

- [x] 9.1 Add SMTP authentication error troubleshooting
- [x] 9.2 Add SSL/TLS configuration error troubleshooting
- [x] 9.3 Add email delivery troubleshooting (distributionMethod, BullMQ)
- [x] 9.4 Add S3 CORS error troubleshooting
- [x] 9.5 Add Redis/BullMQ job monitoring guidance
- [x] 9.6 Add SMTP connectivity testing examples

## 10. End-to-End Validation

- [x] 10.1 Create standalone VM test configuration
- [x] 10.2 Test S3 document upload with real AWS credentials
- [x] 10.3 Configure and test S3 CORS for PDF viewing
- [x] 10.4 Test AWS SES SMTP integration (port 587 + STARTTLS)
- [x] 10.5 Validate email delivery workflow
- [x] 10.6 Test multi-recipient document distribution
- [x] 10.7 Complete full signing workflow from upload to completion
- [x] 10.8 Test BullMQ job processing with Redis
- [x] 10.9 Validate certificate auto-generation
- [x] 10.10 Document all edge cases and solutions

## 11. Future Planning

- [x] 11.1 Create GitHub issue for CloudWatch Logs integration (#11)
- [ ] 11.2 Plan CloudWatch Logs implementation approach
- [ ] 11.3 Design CloudWatch Logs configuration interface
