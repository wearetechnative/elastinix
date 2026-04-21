# Postfix AWS SES Relay

Centralized mail relay service for forwarding all email through AWS SES with SASL authentication, network security, and sender address rewriting.

## Overview

The Postfix AWS SES relay service provides a dedicated mail relay host within your VPC that all application servers can use to send email through AWS SES. This architecture:

- **Centralizes credential management** - AWS SES SMTP credentials stored in one place
- **Enforces network security** - Only trusted subnets can relay mail
- **Ensures SES compliance** - Automatic sender address rewriting and message size limits
- **Simplifies configuration** - Applications just point to the relay host

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     VPC (10.0.0.0/16)                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                                                           │  │
│  │  App Server 1        App Server 2       App Server N     │  │
│  │  (10.0.1.10)        (10.0.1.11)         (10.0.1.x)       │  │
│  │      │                  │                    │            │  │
│  │      │ SMTP:25          │ SMTP:25            │            │  │
│  │      └──────────────────┴────────────────────┘            │  │
│  │                         │                                 │  │
│  │                         ▼                                 │  │
│  │              ┌──────────────────────┐                     │  │
│  │              │   Mail Relay Host    │                     │  │
│  │              │   (10.0.2.5)         │                     │  │
│  │              │                      │                     │  │
│  │              │  Postfix Relay       │                     │  │
│  │              │  + mynetworks filter │                     │  │
│  │              └──────────┬───────────┘                     │  │
│  │                         │                                 │  │
│  │                         │ SMTP:587/TLS                    │  │
│  └─────────────────────────┼─────────────────────────────────┘  │
│                            │                                    │
│                            │ (via NAT Gateway)                  │
│                            ▼                                    │
│                   ┌─────────────────┐                           │
│                   │    AWS SES      │                           │
│                   │  SMTP Endpoint  │                           │
│                   └─────────────────┘                           │
│                                                                 │
│  Security Layers:                                              │
│  1. AWS Security Group - only relay host → SES                │
│  2. Postfix mynetworks - only accept from 10.0.0.0/16         │
│  3. TLS encryption for SES connection                          │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. AWS SES Identity Verification

All sender addresses must be verified in AWS SES before use:

```bash
# Verify a domain (recommended)
aws ses verify-domain-identity --domain example.com

# Or verify individual email addresses
aws ses verify-email-identity --email-address noreply@example.com
aws ses verify-email-identity --email-address sysadmin@example.com
```

**Important:** In SES sandbox mode, you must also verify recipient addresses. Request production access to send to any recipient.

### 2. AWS SES SMTP Credentials

Generate SMTP credentials in the AWS SES console or via AWS CLI:

```bash
# Create IAM user for SES SMTP
aws iam create-user --user-name ses-smtp-user

# Attach SES sending policy
aws iam attach-user-policy \
  --user-name ses-smtp-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonSesSendingAccess

# Create SMTP credentials (converts IAM credentials to SMTP format)
# Follow AWS documentation for SMTP credential conversion
```

### 3. Agenix Secret Configuration

Encrypt SMTP credentials using agenix:

```bash
# Create credentials file (format: [host]:port username:password)
cat > ses-smtp-creds <<EOF
[email-smtp.eu-west-1.amazonaws.com]:587 AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF

# Encrypt with agenix
agenix -e secrets/ses-smtp.age

# Clean up plaintext file
rm ses-smtp-creds
```

## Configuration

### Basic Configuration

```nix
{
  elastinix.services.postfix-relay-aws = {
    enable = true;

    # AWS SES SMTP endpoint (region-specific)
    sesEndpoint = "email-smtp.eu-west-1.amazonaws.com";
    sesPort = 587;  # 587=STARTTLS (default), 465=TLS, 25=plain

    # Path to agenix-encrypted SASL credentials
    credentialsFile = config.age.secrets.ses-smtp.path;

    # Networks allowed to relay mail (VPC CIDR + localhost)
    trustedNetworks = [
      "10.0.0.0/16"    # VPC CIDR
      "127.0.0.0/8"    # localhost
      "::1/128"        # IPv6 localhost
    ];

    # Where local system mail (root@, postmaster@) is forwarded
    rootAlias = "sysadmin@example.com";

    # Default FROM address for sender rewriting
    defaultSenderAddress = "noreply@example.com";

    # Optional: per-user sender mappings
    senderMaps = {
      "root@" = "sysadmin@example.com";
      "www-data@" = "webserver@example.com";
      "postgres@" = "database@example.com";
    };

    # Message size limit (default 10MB, SES maximum)
    messageSizeLimit = 10485760;
  };

  # Agenix secret configuration
  age.secrets.ses-smtp = {
    file = ./secrets/ses-smtp.age;
    owner = "postfix";
    group = "postfix";
  };
}
```

### SES Endpoints by Region

| Region | SMTP Endpoint |
|--------|---------------|
| us-east-1 | email-smtp.us-east-1.amazonaws.com |
| us-west-2 | email-smtp.us-west-2.amazonaws.com |
| eu-west-1 | email-smtp.eu-west-1.amazonaws.com |
| eu-central-1 | email-smtp.eu-central-1.amazonaws.com |
| ap-southeast-1 | email-smtp.ap-southeast-1.amazonaws.com |

See [AWS SES Regions and Endpoints](https://docs.aws.amazon.com/general/latest/gr/ses.html) for complete list.

## Sender Address Rewriting Scenarios

### Scenario 1: Local System Mail

Cron jobs and system services send mail as `root@hostname.local`:

```
FROM: root@mailrelay.local
TO: root

↓ (alias_maps + senderMaps)

FROM: sysadmin@example.com
TO: sysadmin@example.com
```

### Scenario 2: Application Without Domain

Web application sends as `www-data@hostname`:

```
FROM: www-data@appserver
TO: customer@external.com

↓ (senderMaps)

FROM: webserver@example.com
TO: customer@external.com
```

### Scenario 3: Already Verified Domain

Application uses correct SES-verified address:

```
FROM: noreply@example.com
TO: user@customer.com

↓ (no rewriting)

FROM: noreply@example.com
TO: user@customer.com
```

### Scenario 4: Catch-All Rewriting

Any sender without proper domain:

```
FROM: app@localhost
TO: admin@example.com

↓ (catch-all regex → defaultSenderAddress)

FROM: noreply@example.com
TO: admin@example.com
```

## Security

### Defense in Depth

This service implements multiple security layers:

#### Layer 1: AWS Security Groups

Configure security groups for network-level filtering:

```hcl
# Terraform example
resource "aws_security_group_rule" "relay_to_ses" {
  type              = "egress"
  from_port         = 587
  to_port           = 587
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]  # SES endpoints
  security_group_id = aws_security_group.mail_relay.id
}

resource "aws_security_group_rule" "apps_to_relay" {
  type                     = "ingress"
  from_port                = 25
  to_port                  = 25
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app_servers.id
  security_group_id        = aws_security_group.mail_relay.id
}
```

#### Layer 2: Postfix mynetworks

The `trustedNetworks` option configures Postfix to only accept mail from specific networks:

```nix
trustedNetworks = [ "10.0.0.0/16" "127.0.0.0/8" ];
```

This prevents open relay - only hosts in these networks can send mail.

#### Layer 3: TLS Encryption

All connections to AWS SES use TLS encryption:
- Port 587: STARTTLS (opportunistic → mandatory via `smtp_tls_security_level = encrypt`)
- Port 465: TLS wrapper (deprecated but supported)

### Credential Security

- Credentials stored in agenix-encrypted files
- Decrypted at boot to `/run/agenix/*` (tmpfs, mode 600)
- Postfix reads credentials via systemd setup service
- Hashed credentials stored in `/var/lib/postfix/sasl_passwd.db` (mode 600, owner postfix)

## SES Compliance Settings

### Message Size Limit

AWS SES has a 10MB message size limit. The service enforces this by default:

```nix
messageSizeLimit = 10485760;  # 10MB in bytes
```

Messages exceeding this limit are rejected before sending to SES.

### Rate Limiting

To prevent hitting SES rate limits, the service configures conservative Postfix defaults:

```nix
# In services.postfix.config
default_destination_concurrency_limit = "2";  # Max 2 concurrent connections
default_destination_rate_delay = "1s";        # 1 second delay between messages
```

**SES Rate Limits:**
- **Sandbox mode**: 1 email/second, 200 emails/day
- **Production mode**: Varies by account (request increase via AWS support)

Postfix will queue messages if rate limits are exceeded.

## Testing

### 1. Verify Service Status

```bash
# Check SASL credentials setup service
systemctl status postfix-setup-sasl.service

# Check Postfix service
systemctl status postfix.service

# Check Postfix logs
journalctl -u postfix.service -f
```

### 2. Send Test Email

```bash
# Using mail command
echo "Test email body" | mail -s "Test Subject" test@example.com

# Using sendmail
sendmail -t <<EOF
From: noreply@example.com
To: test@example.com
Subject: Test from relay

This is a test email.
EOF
```

### 3. Monitor Mail Queue

```bash
# Check mail queue
mailq

# Watch mail log
tail -f /var/log/mail.log

# Or with journalctl
journalctl -u postfix.service -f
```

### 4. Test From Application Server

Configure application to use relay host as SMTP server:

```python
# Python example
import smtplib

smtp = smtplib.SMTP('mailrelay.internal', 25)
smtp.sendmail(
    'noreply@example.com',
    ['test@example.com'],
    'Subject: Test\n\nTest email'
)
smtp.quit()
```

## Troubleshooting

### Credentials Not Working

**Symptom:** Authentication failures in logs

```
SASL authentication failed; server email-smtp.eu-west-1.amazonaws.com[...] said: 535 Authentication Credentials Invalid
```

**Solution:**
1. Verify credentials file format: `[host]:port username:password`
2. Check credentials are valid in AWS console
3. Verify file permissions: `ls -la /var/lib/postfix/sasl_passwd*`
4. Re-run setup: `systemctl restart postfix-setup-sasl.service`

### Connection Refused

**Symptom:** Connection errors to SES endpoint

```
connect to email-smtp.eu-west-1.amazonaws.com[...]:587: Connection refused
```

**Solution:**
1. Check AWS Security Group allows egress to port 587
2. Verify network connectivity: `nc -zv email-smtp.eu-west-1.amazonaws.com 587`
3. Check NAT Gateway configuration

### Sender Address Not Verified

**Symptom:** SES rejects email due to unverified sender

```
554 Message rejected: Email address is not verified
```

**Solution:**
1. Verify sender addresses in AWS SES console
2. Check `senderMaps` configuration
3. Verify `defaultSenderAddress` is verified

### Mail Queue Building Up

**Symptom:** `mailq` shows many queued messages

**Solution:**
1. Check SES rate limits (sandbox vs production)
2. Adjust rate limiting settings if needed
3. Request SES sending limit increase from AWS
4. Check for delivery errors: `mailq` and logs

### Permission Denied

**Symptom:** Postfix can't read credentials file

```
warning: hash:/var/lib/postfix/sasl_passwd: Permission denied
```

**Solution:**
1. Check agenix secret owner: `owner = "postfix"; group = "postfix";`
2. Verify setup service ran: `systemctl status postfix-setup-sasl.service`
3. Check file permissions: `ls -la /var/lib/postfix/sasl_passwd*`

## Future Enhancements

### Multi-Instance Support

Currently supports single SES endpoint per host. Future enhancement for multiple endpoints:

```nix
elastinix.services.postfix-relay-aws = {
  enable = true;
  instances = {
    production = {
      sesEndpoint = "email-smtp.eu-west-1.amazonaws.com";
      trustedNetworks = [ "10.0.0.0/16" ];
      # ... config ...
    };
    staging = {
      sesEndpoint = "email-smtp.us-east-1.amazonaws.com";
      trustedNetworks = [ "10.1.0.0/16" ];
      # ... config ...
    };
  };
};
```

**Use cases:**
- Multi-account AWS setups
- Different regions for different environments
- Staging vs production separation

### Virtual Alias Domains

Support multiple sending domains:

```nix
virtualAliasDomains = [
  "example.com"
  "example.org"
];
```

### Monitoring Integration

Integration with existing Elastinix monitoring:

```nix
elastinix.services.systemd-monitoring.services = [
  "postfix.service"
  "postfix-setup-sasl.service"
];
```

## References

- [AWS SES SMTP Documentation](https://docs.aws.amazon.com/ses/latest/dg/send-email-smtp.html)
- [Postfix SASL README](http://www.postfix.org/SASL_README.html)
- [Postfix TLS README](http://www.postfix.org/TLS_README.html)
- [NixOS Postfix Module](https://search.nixos.org/options?query=services.postfix)
