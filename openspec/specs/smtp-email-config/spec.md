# smtp-email-config Specification

## Purpose
TBD - created by archiving change nixos-documenso-service. Update Purpose after archive.

## Requirements

### Requirement: SMTP server configuration
The module SHALL configure SMTP for email delivery.

#### Scenario: Local Postfix relay
- **WHEN** smtp.host = "localhost" and smtp.port = 25
- **THEN** Documenso sends email via local Postfix without authentication

#### Scenario: SMTP with authentication (separate credentials)
- **WHEN** smtp.username and smtp.passwordFile provided
- **THEN** SMTP credentials included in environment as NEXT_PRIVATE_SMTP_USERNAME and NEXT_PRIVATE_SMTP_PASSWORD

#### Scenario: SMTP with authentication (combined credentials file)
- **WHEN** smtp.credentialsFile provided
- **THEN** Credentials sourced from file containing SMTP_USERNAME and SMTP_PASSWORD
- **AND** Environment variables NEXT_PRIVATE_SMTP_USERNAME and NEXT_PRIVATE_SMTP_PASSWORD set

#### Scenario: SMTP credential validation
- **WHEN** Both username+passwordFile AND credentialsFile provided
- **THEN** Build fails with assertion error
- **AND** Error message explains to use only one method

#### Scenario: AWS SES SMTP configuration
- **WHEN** smtp.host = "email-smtp.*.amazonaws.com" and smtp.port = 587
- **THEN** smtp.secure SHOULD be false (STARTTLS)
- **AND** Documentation provides AWS SES setup guidance

### Requirement: SMTP sender configuration
The module SHALL configure sender name and address.

#### Scenario: Sender configured
- **WHEN** smtp.fromAddress and smtp.fromName provided
- **THEN** NEXT_PRIVATE_SMTP_FROM_ADDRESS and NEXT_PRIVATE_SMTP_FROM_NAME set
