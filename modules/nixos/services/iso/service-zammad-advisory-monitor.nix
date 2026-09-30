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

  checkCommand = lib.escapeShellArgs commonArgs;

  failureCommand = lib.escapeShellArgs (commonArgs ++ [ "--notify-failure" ]);

  hardening = {
    DynamicUser = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    ProtectProc = "invisible";
    CapabilityBoundingSet = "";
    UMask = "0077";
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    RestrictNamespaces = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;
    SystemCallArchitectures = "native";
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
      example = lib.literalExpression "config.age.secrets.zammad-advisory-slack-webhook.path";
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

    heartbeatUrlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = lib.literalExpression "config.age.secrets.zammad-advisory-heartbeat-url.path";
      description = ''
        Optional path to a file containing a dead-man's-switch URL (e.g. https://hc-ping.com/<uuid>)
        that is pinged after every successful run. Read via LoadCredential so the URL stays
        out of the Nix store and the process list.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

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
          ++ lib.optional (cfg.heartbeatUrlFile != null) "heartbeat-url:${cfg.heartbeatUrlFile}";
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