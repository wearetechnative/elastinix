{ config, lib, pkgs, ... }:

let
  cfg = config.elastinix.services.vaultwarden-release-monitor;

  # If Vaultwarden runs on this same host via elastinix, Nix already knows its version
  vaultwardenCfg = config.elastinix.services.vaultwarden;

  monitorScript = pkgs.writeText "vaultwarden-release-monitor.py"
    (builtins.readFile ./vaultwarden-release-monitor.py);

  commonArgs = [
    "${pkgs.python3}/bin/python3"
    "${monitorScript}"
    "--repository" cfg.repository
    "--hostname" config.networking.hostName
  ];

  checkCommand = lib.escapeShellArgs (commonArgs
    ++ lib.optionals (cfg.installedVersion != null) [ "--installed-version" cfg.installedVersion ]
    ++ lib.optionals (cfg.versionUrl != null) [ "--version-url" cfg.versionUrl ]
    ++ lib.optionals (cfg.heartbeatUrl != null) [ "--heartbeat-url" cfg.heartbeatUrl ]);

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
  options.elastinix.services.vaultwarden-release-monitor = {
    enable = lib.mkEnableOption "Vaultwarden release monitor (GitHub releases -> Slack)";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "dani-garcia/vaultwarden";
      description = "GitHub repository (owner/name) whose releases are monitored.";
    };

    installedVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if vaultwardenCfg.enable then vaultwardenCfg.package.version else null;
      defaultText = lib.literalExpression
        "if config.elastinix.services.vaultwarden.enable then config.elastinix.services.vaultwarden.package.version else null";
      example = "1.37.5";
      description = ''
        Vaultwarden version we run. Detected automatically when
        elastinix.services.vaultwarden is enabled on the same host. Set it by hand
        when the monitor runs elsewhere. null = every new release is posted.
      '';
    };

    versionUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://vaultwarden.example.com/api/version";
      description = ''
        Vaultwarden's public version endpoint, queried on every run (no token needed).
        When set, it takes precedence over installedVersion. If the call fails, new
        releases are still announced and the run is marked failed.
      '';
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "Mon..Fri *-*-* 09..17:00:00 Europe/Amsterdam";
      description = "systemd OnCalendar expression for how often to check.";
    };

    slackWebhookFile = lib.mkOption {
      type = lib.types.str;
      example = "config.age.secrets.zammad-advisory-slack-webhook.path";
      description = "Path to an agenix-decrypted file containing only the Slack incoming-webhook URL.";
    };

    githubTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional path to a file with a GitHub token (no scopes needed), to avoid the 60 requests/hour limit.";
    };

    heartbeatUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://hc-ping.com/<uuid>";
      description = "Optional dead-man's-switch URL pinged after every successful run.";
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.services.vaultwarden-release-monitor = {
      description = "Check ${cfg.repository} for new releases";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      onFailure = [ "vaultwarden-release-monitor-failure.service" ];
      serviceConfig = hardening // {
        Type = "oneshot";
        ExecStart = checkCommand;
        StateDirectory = "vaultwarden-release-monitor";   # -> $STATE_DIRECTORY
        LoadCredential =                                   # -> $CREDENTIALS_DIRECTORY
          [ "slack-webhook:${cfg.slackWebhookFile}" ]
          ++ lib.optional (cfg.githubTokenFile != null) "github-token:${cfg.githubTokenFile}";
      };
    };

    # Runs only when the check above fails
    systemd.services.vaultwarden-release-monitor-failure = {
      description = "Notify Slack that the Vaultwarden release monitor failed";
      serviceConfig = hardening // {
        Type = "oneshot";
        ExecStart = failureCommand;
        LoadCredential = [ "slack-webhook:${cfg.slackWebhookFile}" ];
      };
    };

    systemd.timers.vaultwarden-release-monitor = {
      description = "Timer for the Vaultwarden release monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;          
        RandomizedDelaySec = "5m";
      };
    };
  };
}