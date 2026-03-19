{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.elastinix.services.jirasync;

  # Use the jirasync package from the flake input
  jirasyncPackage = inputs.jirasync.packages.${pkgs.system}.default;

in {
  options.elastinix.services.jirasync = {
    enable = mkEnableOption "Jira synchronization service";

    instances = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          configFile = mkOption {
            type = types.str;
            description = "Path to the Jira sync configuration file";
          };

          daysToSync = mkOption {
            type = types.int;
            default = 90;
            description = "Number of days to look back for issues";
          };

          dryRun = mkOption {
            type = types.bool;
            default = false;
            description = "Run in dry-run mode without making changes";
          };

          interval = mkOption {
            type = types.str;
            default = "hourly";
            description = "Systemd timer interval (e.g., 'daily', 'hourly', '*:0/30' for every 30 minutes)";
          };

          user = mkOption {
            type = types.str;
            default = "root";
            description = "User to run the service as";
          };

          group = mkOption {
            type = types.str;
            default = "root";
            description = "Group to run the service as";
          };
        };
      });
      default = {};
      description = "Jira sync instances to configure";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ jirasyncPackage ];

    # Create users and groups for all instances (skip root as it already exists)
    users.users = listToAttrs (filter (x: x.name != "root") (map (name:
      let instanceCfg = cfg.instances.${name};
      in nameValuePair instanceCfg.user {
        isSystemUser = true;
        group = instanceCfg.group;
        description = "Jira sync service user";
      }
    ) (attrNames cfg.instances)));

    users.groups = listToAttrs (filter (x: x.name != "root") (map (name:
      let instanceCfg = cfg.instances.${name};
      in nameValuePair instanceCfg.group {}
    ) (attrNames cfg.instances)));

    # Create systemd services for each instance
    systemd.services = listToAttrs (map (name:
      let instanceCfg = cfg.instances.${name};
      in nameValuePair "jirasync-${name}" {
        description = "Jira synchronization service (${name})";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        script = ''
          ${jirasyncPackage}/bin/jirasync \
            --config "${instanceCfg.configFile}" \
            --days "${toString instanceCfg.daysToSync}" \
            ${optionalString instanceCfg.dryRun "--dry-run"}
        '';

        serviceConfig = {
          Type = "oneshot";
          User = instanceCfg.user;
          Group = instanceCfg.group;

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
        };
      }
    ) (attrNames cfg.instances));

    # Create systemd timers for each instance
    systemd.timers = listToAttrs (map (name:
      let instanceCfg = cfg.instances.${name};
      in nameValuePair "jirasync-${name}" {
        description = "Timer for Jira synchronization (${name})";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          OnCalendar = instanceCfg.interval;
          Persistent = true;
          RandomizedDelaySec = "5min";
        };
      }
    ) (attrNames cfg.instances));
  };
}
