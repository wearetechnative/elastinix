{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.elastinix.services.postfix-relay-aws;

in {
  options.elastinix.services.postfix-relay-aws = {
    enable = mkEnableOption "AWS SES Postfix relay service";

    sesEndpoint = mkOption {
      type = types.str;
      example = "email-smtp.eu-west-1.amazonaws.com";
      description = "AWS SES SMTP endpoint hostname";
    };

    sesPort = mkOption {
      type = types.port;
      default = 587;
      description = "AWS SES SMTP port (587=STARTTLS, 465=TLS, 25=plain)";
    };

    credentialsFile = mkOption {
      type = types.path;
      description = ''
        Path to SASL credentials file for AWS SES authentication.
        Format: [host]:port username:password

        Example:
          [email-smtp.eu-west-1.amazonaws.com]:587 AKIAIOSFODNN7EXAMPLE:secretkey

        This should typically point to an agenix-encrypted secret path.
      '';
    };

    trustedNetworks = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.0/8" "::1/128" ];
      example = [ "10.0.0.0/16" "127.0.0.0/8" "::1/128" ];
      description = ''
        Network addresses allowed to relay mail through this host (mynetworks).
        Postfix will only accept mail from these networks.
      '';
    };

    rootAlias = mkOption {
      type = types.str;
      example = "sysadmin@example.com";
      description = ''
        Email address to forward local system mail to.
        All mail sent to root@, postmaster@, and mailer-daemon@ will be forwarded here.
      '';
    };

    defaultSenderAddress = mkOption {
      type = types.str;
      example = "noreply@example.com";
      description = ''
        Default FROM address for rewriting sender addresses.
        Any mail without a proper domain will be rewritten to this address.
        This address must be verified in AWS SES.
      '';
    };

    senderMaps = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        "root@" = "sysadmin@example.com";
        "www-data@" = "webserver@example.com";
      };
      description = ''
        Mapping of local sender addresses to SES-verified addresses.
        Format: "local-user@" = "verified@example.com"
        All addresses must be verified in AWS SES.
      '';
    };

    messageSizeLimit = mkOption {
      type = types.int;
      default = 10485760;
      description = ''
        Maximum message size in bytes.
        AWS SES limit is 10MB (10485760 bytes).
      '';
    };
  };

  config = mkIf cfg.enable {
    # Extract domain from defaultSenderAddress for services.postfix.domain
    # Example: "noreply@example.com" -> "example.com"
    services.postfix = {
      enable = true;

      settings = {
        main = {
          # Network and hostname configuration
          mynetworks = cfg.trustedNetworks;
          myhostname = config.networking.hostName;
          mydomain = builtins.elemAt (builtins.split "@" cfg.defaultSenderAddress) 2;

          # Relay Configuration (NixOS 25.11+)
          relayhost = [ "[${cfg.sesEndpoint}]:${toString cfg.sesPort}" ];

          # SASL Authentication
          smtp_sasl_auth_enable = true;
          smtp_sasl_security_options = "noanonymous";
          smtp_sasl_password_maps = "hash:/var/lib/postfix/sasl_passwd";

          # TLS Configuration
          smtp_use_tls = true;
          smtp_tls_security_level = "encrypt";
          smtp_tls_note_starttls_offer = true;

          # Address Rewriting
          # Use both hash (for exact matches) and regexp (for catch-all)
          # Note: NixOS postfix module places mapFiles in /var/lib/postfix/conf/
          smtp_generic_maps = [
            "hash:/var/lib/postfix/conf/generic"
            "regexp:/var/lib/postfix/conf/generic_regexp"
          ];

          # SES Compliance Settings
          message_size_limit = cfg.messageSizeLimit;
          default_destination_concurrency_limit = 2;
          default_destination_rate_delay = "1s";

          # Bounce Handling
          bounce_notice_recipient = cfg.rootAlias;
          "2bounce_notice_recipient" = cfg.rootAlias;
          error_notice_recipient = cfg.rootAlias;
        };
      };

      # Map Files
      mapFiles = {
        # Sender rewriting - exact matches (hash map)
        generic = pkgs.writeText "postfix-generic" (
          concatStringsSep "\n" (
            # Specific sender mappings from cfg.senderMaps
            (mapAttrsToList (from: to: "${from} ${to}") cfg.senderMaps)
          )
        );

        # Sender rewriting - regex catch-all (regexp map)
        generic_regexp = pkgs.writeText "postfix-generic-regexp" ''
          # Catch-all: rewrite any address without proper domain to defaultSenderAddress
          /.+@[^.]+$/ ${cfg.defaultSenderAddress}
        '';

        # Local mail aliases
        aliases = pkgs.writeText "postfix-aliases" ''
          root: ${cfg.rootAlias}
          postmaster: ${cfg.rootAlias}
          mailer-daemon: ${cfg.rootAlias}
        '';
      };
    };

    # SASL Credentials Setup Service
    systemd.services.postfix-setup-sasl = {
      description = "Setup Postfix SASL credentials for AWS SES";
      before = [ "postfix.service" ];
      wantedBy = [ "multi-user.target" ];

      script = ''
        # Ensure /var/lib/postfix is owned by postfix user
        # (postmap switches to postfix user and needs write access)
        chown postfix:postfix /var/lib/postfix

        # Install credentials file with correct permissions
        install -D -m 600 -o postfix -g postfix \
          ${cfg.credentialsFile} \
          /var/lib/postfix/sasl_passwd

        # Generate hashed credentials database
        ${pkgs.postfix}/bin/postmap /var/lib/postfix/sasl_passwd

        # Ensure hashed file has correct permissions
        chmod 600 /var/lib/postfix/sasl_passwd.db
        chown postfix:postfix /var/lib/postfix/sasl_passwd.db
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
