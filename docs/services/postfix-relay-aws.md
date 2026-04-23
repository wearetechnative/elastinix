# Postfix Mail Relay

Centralized mail relay for forwarding all email through AWS SES with SASL authentication and sender address rewriting.

## Features

- **Centralized credentials** - AWS SES SMTP credentials in one place
- **Network security** - Only trusted VPC subnets can relay
- **SES compliance** - Automatic sender rewriting, 10MB limit, rate limiting
- **Client support** - Simple relay configuration for application servers

## Architecture

```
Application Servers (VPC)
  ↓ SMTP:25
Relay Host (Postfix)
  ↓ SMTP:587/TLS
AWS SES
  ↓
Recipients
```

**Security**: AWS Security Group + Postfix mynetworks + TLS encryption

## Prerequisites

**1. AWS SES Setup**
- Verify domain or email addresses in AWS SES
- Create SMTP credentials in IAM (not regular IAM keys)
- Request production access (sandbox limits: 1 email/sec, 200/day)

**2. Agenix Secret**
```bash
# Format: [host]:port username:password
echo "[email-smtp.eu-central-1.amazonaws.com]:587 AKIAXXX:SecretXXX" | agenix -e secrets/ses-smtp.age
```

## Server Configuration

```nix
{
  elastinix.services.postfix-relay-aws = {
    enable = true;

    sesEndpoint = "email-smtp.eu-central-1.amazonaws.com";
    sesPort = 587;  # 587=STARTTLS, 465=TLS, 25=plain
    credentialsFile = config.age.secrets.ses-smtp.path;

    trustedNetworks = [
      "10.0.0.0/16"    # VPC CIDR
      "127.0.0.0/8"    # localhost
    ];

    rootAlias = "sysadmin@example.com";
    defaultSenderAddress = "noreply@example.com";

    # Optional: per-user mappings
    senderMaps = {
      "root@" = "sysadmin@example.com";
      "www-data@" = "webserver@example.com";
    };

    messageSizeLimit = 10485760;  # 10MB (SES max)
  };

  age.secrets.ses-smtp = {
    file = ./secrets/ses-smtp.age;
    owner = "postfix";
    group = "postfix";
  };
}
```

**SES Endpoints**: [AWS documentation](https://docs.aws.amazon.com/general/latest/gr/ses.html)

## Client Configuration

Application servers forward all mail to relay host:

```nix
let
  postfix_relay_host = "postfix.internal";  # or "postfix.${domain}"
in {
  services.postfix = {
    enable = true;
    hostname = "appserver";
    domain = "example.com";

    settings.main = {  # NixOS 25.11+
      relayhost = [ "${postfix_relay_host}:25" ];
      inet_interfaces = "loopback-only";
      inet_protocols = "ipv4";
      mydestination = ["localhost"];
      alias_maps = ["hash:/etc/postfix/aliases"];
    };

    mapFiles.aliases = pkgs.writeText "aliases" ''
      root: sysadmin@example.com
      postmaster: sysadmin@example.com
    '';
  };
}
```

**NixOS 25.05** (old API):
```nix
services.postfix = {
  relayHost = postfix_relay_host;
  relayPort = 25;
  config.inet_interfaces = "loopback-only";
  destination = ["localhost"];
  # ... same mapFiles
};
```

**DNS**: Point `postfix.internal` to relay host's **private IP** for VPC-only access.

## Sender Address Rewriting

| From | To |
|------|-----|
| `root@hostname` | `sysadmin@example.com` (via senderMaps) |
| `www-data@appserver` | `webserver@example.com` (via senderMaps) |
| `noreply@example.com` | unchanged (already verified) |
| `app@localhost` | `noreply@example.com` (catch-all regex) |

## Testing

```bash
# Server: Check status
systemctl status postfix postfix-setup-sasl
journalctl -u postfix -f

# Client: Send test
echo "Test" | mail -s "Test" user@example.com
mailq  # Check queue
postconf relayhost  # Verify relay config
```

## Troubleshooting

**Authentication failed (535)**
- Use SES SMTP credentials (not IAM keys)
- Check credentials format: `[host]:port username:password`
- Verify file permissions: `ls -la /var/lib/postfix/sasl_passwd*`

**Connection refused**
- Check AWS Security Group egress to port 587
- Test: `nc -zv email-smtp.eu-central-1.amazonaws.com 587`
- Verify NAT Gateway configuration

**Sender not verified (554)**
- Verify addresses in AWS SES console
- Check `senderMaps` and `defaultSenderAddress` configuration

**Mail queue building up**
- Check SES rate limits (sandbox vs production)
- Monitor: `mailq` and `journalctl -u postfix`
- Request SES limit increase from AWS

**smtpd crash (dictionary error)**
- Ensure IPv6 (::1/128) removed from trustedNetworks
- Check `proxy_read_maps` and `parent_domain_matches_subdomains` settings

## Security

- Store credentials in agenix/sops-nix encrypted files
- Restrict relay to VPC CIDR only (trustedNetworks)
- Use TLS for SES connection (port 587 with STARTTLS)
- Regular database backups if using database storage
- Monitor logs for suspicious activity

## Performance

**SES Rate Limits**:
- Sandbox: 1 email/sec, 200 emails/day
- Production: Varies (request increase via AWS support)

**Postfix Defaults**:
- 2 concurrent connections to SES
- 1 second delay between messages
- 10MB message size limit

## References

- [AWS SES SMTP](https://docs.aws.amazon.com/ses/latest/dg/send-email-smtp.html)
- [Postfix SASL](http://www.postfix.org/SASL_README.html)
- [NixOS Postfix Module](https://search.nixos.org/options?query=services.postfix)
