## ADDED Requirements

### Requirement: SMTP server configuration
The module SHALL configure SMTP for email delivery.

#### Scenario: Local Postfix relay
- **WHEN** smtp.host = "localhost" and smtp.port = 25
- **THEN** Documenso sends email via local Postfix without authentication

#### Scenario: SMTP with authentication
- **WHEN** smtp.username and smtp.passwordFile provided
- **THEN** SMTP credentials included in environment

### Requirement: SMTP sender configuration
The module SHALL configure sender name and address.

#### Scenario: Sender configured
- **WHEN** smtp.fromAddress and smtp.fromName provided
- **THEN** NEXT_PRIVATE_SMTP_FROM_ADDRESS and NEXT_PRIVATE_SMTP_FROM_NAME set
