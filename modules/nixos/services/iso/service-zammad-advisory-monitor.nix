{ config, lib, pkgs, ... }:

# Zammad security advisory monitor (ISO 27001 A.8.8 / A.5.7)
#
# All logic lives in ./zammad-advisory-monitor.py (Python stdlib only).
# This module only wires it up: options, systemd service + timer,
# secrets via LoadCredential and systemd hardening.

let
  cfg = config.elastinix.services.zammad-advisory-monitor;

  # Same pattern as service-vulnerability-prometheus-exporter.nix:
  # copy the .py file into the Nix store and run it with python3.
  monitorScript = pkgs.writeText "zammad-advisory-monitor.py"
    (builtins.readFile ./zammad-advisory-monitor.py);

  # Command-line arguments passed to the script
  commonArgs = [
    "${pkgs.python3}/bin/python3"
    "${monitorScript}"
    "--repository" cfg.repository
    "--hostname" config.networking.hostName
  ];

  checkCommand = lib.escapeShellArgs (commonArgs
    ++ lib.optionals (cfg.heartbeatUrl != null) [ "--heartbeat-url" cfg.heartbeatUrl ]
    ++ lib.optionals (cfg.zammadVersion != null) [ "--zammad-version" cfg.zammadVersion ]
    ++ lib.optionals (cfg.zammadApiUrl != null) [ "--zammad-api-url" cfg.zammadApiUrl ]
    ++ lib.optional cfg.notifyUnaffected "--notify-unaffected");

  # If Zammad runs on this same host via elastinix, Nix already knows its version
  zammadCfg = config.elastinix.services.zammad;

  failureCommand = lib.escapeShellArgs (commonArgs ++ [ "--notify-failure" ]);

  hardening = {
    DynamicUser = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    RestrictNamespaces = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;
    SystemCallFilter = [ "@system-service" "~@privileged" ];
  };

in
{
  options.elastinix.services.zammad-advisory-monitor = {
    enable = lib.mkEnableOption "Zammad security advisory monitor (GitHub advisories -> Slack)";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "zammad/zammad";
      description = "GitHub repository (owner/name) whose security advisories are monitored.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "systemd OnCalendar expression for how often to poll.";
    };

    slackWebhookFile = lib.mkOption {
      type = lib.types.str;
      example = "config.age.secrets.zammad-advisory-slack-webhook.path";
      description = "Path to an agenix-decrypted file containing only the Slack incoming-webhook URL.";
    };

    githubTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional path to a file with a GitHub token (no scopes needed for public repos).
        Unauthenticated requests are limited to 60/hour per IP.
      '';
    };

    zammadVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if zammadCfg.enable then zammadCfg.package.version else null;
      defaultText = lib.literalExpression
        "if config.elastinix.services.zammad.enable then config.elastinix.services.zammad.package.version else null";
      example = "7.1.3";
      description = ''
        Zammad version to check advisories against. Detected automatically when
        elastinix.services.zammad is enabled on the same host. Set it by hand when the
        monitor runs elsewhere. null = no filtering, every advisory is alerted.
      '';
    };

    zammadApiUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://zammad.tools.technative.cloud/api/v1/version";
      description = ''
        Zammad version endpoint, queried on every run. When set, it takes precedence
        over zammadVersion. Requires zammadTokenFile. If the call fails, advisories are
        alerted as "check manually" and the run is marked failed.
      '';
    };

    zammadTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "config.age.secrets.zammad-version-token.path";
      description = "Path to an agenix-decrypted file containing only the Zammad API token (needs 'admin' permission).";
    };

    notifyUnaffected = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also post advisories that do not affect zammadVersion, as information.
        They are always written to the register either way.
      '';
    };

    heartbeatUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://hc-ping.com/<uuid>";
      description = "Optional dead-man's-switch URL pinged after every successful run.";
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [{
      assertion = cfg.zammadApiUrl == null || cfg.zammadTokenFile != null;
      message = "elastinix.services.zammad-advisory-monitor: zammadApiUrl requires zammadTokenFile.";
    }];

    systemd.services.zammad-advisory-monitor = {
      description = "Check ${cfg.repository} GitHub security advisories";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      onFailure = [ "zammad-advisory-monitor-failure.service" ];
      serviceConfig = hardening // {
        Type = "oneshot";
        ExecStart = checkCommand;
        StateDirectory = "zammad-advisory-monitor";   # -> $STATE_DIRECTORY
        LoadCredential =                               # -> $CREDENTIALS_DIRECTORY
          [ "slack-webhook:${cfg.slackWebhookFile}" ]
          ++ lib.optional (cfg.githubTokenFile != null) "github-token:${cfg.githubTokenFile}"
          ++ lib.optional (cfg.zammadTokenFile != null) "zammad-token:${cfg.zammadTokenFile}";
      };
    };

    # Runs only when the check above fails
    systemd.services.zammad-advisory-monitor-failure = {
      description = "Notify Slack that the Zammad advisory monitor failed";
      serviceConfig = hardening // {
        Type = "oneshot";
        ExecStart = failureCommand;
        LoadCredential = [ "slack-webhook:${cfg.slackWebhookFile}" ];
      };
    };

    systemd.timers.zammad-advisory-monitor = {
      description = "Timer for the Zammad advisory monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;          # catch up on runs missed while powered off
        RandomizedDelaySec = "5m";
      };
    };
  };
}