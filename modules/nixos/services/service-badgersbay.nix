{ lib, config, pkgs, inputs, tfvars, ... }:

let
  cfg = config.elastinix.services.badgersbay;
  badgersbayPackage = inputs.badgersbay.packages.${pkgs.system}.default;
  environment_domain = tfvars.environment_domain;
in

{
  options.elastinix.services.badgersbay = {

    enable = lib.mkEnableOption "Badgersbay file processing service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9117;
      description = "Port number for the badgersbay service";
    };

    storagePath = lib.mkOption {
      type = lib.types.str;
      default = "/data/badgersbay";
      description = "Path where badgersbay stores and processes files";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to YAML file containing API tokens for report submission.

        Format:
        ```yaml
        tokens:
          - hb_token_abc123
          - hb_token_xyz789
        ```

        Required for authentication. Use agenix to encrypt this file.
      '';
      example = "config.age.secrets.badgersbay-tokens.path";
    };

    dashboardPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to plaintext file containing the password for web dashboard access.
        The file should contain a single line with the password.

        Required for dashboard authentication. Use agenix to encrypt this file.
      '';
      example = "config.age.secrets.badgersbay-password.path";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "badgersbay";
      description = "User to run the service as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "badgersbay";
      description = "Group to run the service as";
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      default = pkgs.writeText "badgersbay-config.yaml" ''
        # Badgersbay Configuration
        networkport: ${toString cfg.port}
        storage_location: ${cfg.storagePath}/reports

        # Compliance Tracking
        compliance:
          enabled: true
          audit_months: [3, 9]
          required_reports:
            mandatory:
              - neofetch
              - lynis
            one_of: []
      '';
      description = ''
        Path to the badgersbay configuration file.

        By default, a configuration file is generated with the port and storage path
        from the service options. You can override this to provide a custom configuration.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [ badgersbayPackage ];

    users.users.${cfg.user} = lib.mkIf (cfg.user == "badgersbay") {
      isSystemUser = true;
      group = cfg.group;
      description = "Badgersbay service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "badgersbay") {};

    systemd.tmpfiles.rules = [
      "d '${cfg.storagePath}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.storagePath}/reports' 0750 ${cfg.user} ${cfg.group} - -"
      "C '${cfg.storagePath}/config.yaml' 0640 ${cfg.user} ${cfg.group} - ${cfg.configFile}"
    ];

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    systemd.services.badgersbay = {
      description = "Badgersbay file processing service";
      after = [ "network-online.target" "systemd-tmpfiles-setup.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      script = ''
        ${badgersbayPackage}/bin/honeybadger-server \
          --config ${cfg.storagePath}/config.yaml \
          --token-file ${cfg.tokenFile} \
          --dashboard-password-file ${cfg.dashboardPasswordFile}
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.storagePath;
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        ReadWritePaths = [ cfg.storagePath ];
      };
    };

    services.nginx.virtualHosts."badgersbay.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
