{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.elastinix.services.jiraticketcreate;

  jiraticketcreatePackage = inputs.jiraticketcreate.packages.${pkgs.system}.default;

  # Cartesian product: for each client, for each check in client.checks
  allInstances = flatten (mapAttrsToList (clientName: clientCfg:
    map (checkName: {
      name        = "${clientName}-${checkName}";
      clientName  = clientName;
      checkName   = checkName;
      client      = clientCfg;
      checkType   = cfg.checkTypes.${checkName};
    }) clientCfg.checks
  ) cfg.clients);

  # Bash functions per frequency value, inlined into each service script at build time
  frequencyScript = {
    first_working_day_of_month = ''
      get_current_period() {
        date +%Y-%m
      }
      is_trigger_day() {
        local today_dom
        today_dom=$(date +%-d)
        local first_wd=0
        for d in 1 2 3 4 5 6 7; do
          local wd
          wd=$(date -d "$(date +%Y-%m)-$(printf '%02d' "$d")" +%u 2>/dev/null) || break
          if [ "$wd" -le 5 ]; then
            first_wd=$d
            break
          fi
        done
        [ "$today_dom" -eq "$first_wd" ]
      }
    '';

    first_working_day_of_quarter = ''
      get_current_period() {
        local month year quarter
        month=$(date +%-m)
        year=$(date +%Y)
        quarter=$(( (month - 1) / 3 + 1 ))
        echo "$year-Q$quarter"
      }
      is_trigger_day() {
        local month today_dom first_wd
        month=$(date +%-m)
        today_dom=$(date +%-d)
        case $month in 1|4|7|10) ;; *) return 1 ;; esac
        first_wd=0
        for d in 1 2 3 4 5 6 7; do
          local wd
          wd=$(date -d "$(date +%Y-%m)-$(printf '%02d' "$d")" +%u 2>/dev/null) || break
          if [ "$wd" -le 5 ]; then
            first_wd=$d
            break
          fi
        done
        [ "$today_dom" -eq "$first_wd" ]
      }
    '';

    first_working_day_of_week = ''
      get_current_period() {
        date +%Y-W%V
      }
      is_trigger_day() {
        local dow
        dow=$(date +%u)
        [ "$dow" -eq 1 ]
      }
    '';

    every_working_day = ''
      get_current_period() {
        date +%Y-%m-%d
      }
      is_trigger_day() {
        local dow
        dow=$(date +%u)
        [ "$dow" -le 5 ]
      }
    '';
  };

  # Build the ExecStart script for one instance
  mkScript = instance:
    let
      effectiveJiraUrl  = if instance.client.jiraUrl  != null then instance.client.jiraUrl  else cfg.jiraUrl;
      effectiveJiraUser = if instance.client.jiraUser != null then instance.client.jiraUser else cfg.jiraUser;
      ct = instance.checkType;
      isStructured = builtins.isString ct.schedule;
    in ''
      ${if isStructured then ''
        ${frequencyScript.${ct.schedule}}

        is_trigger_day || exit 0
      '' else ''
        get_current_period() {
          date +%Y-%m-%d
        }
      ''}

      PERIOD=$(get_current_period)
      TITLE=$(echo "${ct.titleTemplate}" | sed "s/{period}/$PERIOD/g")
      DUE_DATE=$(date -d "+${toString ct.dueDateOffsetDays} days" +%Y-%m-%d)

      TMPFILE=$(mktemp)
      trap 'rm -f "$TMPFILE"' EXIT

      ${pkgs.jq}/bin/jq -n \
        --arg url        "${effectiveJiraUrl}" \
        --arg user       "${effectiveJiraUser}" \
        --arg token_file "${instance.client.tokenSecretPath}" \
        --arg board      "${instance.client.board}" \
        --arg title      "$TITLE" \
        --arg description "${ct.description}" \
        --arg issue_type "${ct.issueType}" \
        --arg due_date   "$DUE_DATE" \
        '{
          api: {
            url: $url,
            user: $user,
            token_file: $token_file
          },
          ticket: {
            board: $board,
            title: $title,
            description: $description,
            issue_type: $issue_type,
            due_date: $due_date
          }
        }' > "$TMPFILE"

      ${jiraticketcreatePackage}/bin/jiraticketcreate --config "$TMPFILE"
    '';

in {
  options.elastinix.services.jiraticketcreate = {
    enable = mkEnableOption "Jira ticket creation service";

    jiraUrl = mkOption {
      type = types.str;
      description = "Default Jira base URL used for all clients (can be overridden per client).";
    };

    jiraUser = mkOption {
      type = types.str;
      description = "Default Jira user email used for all clients (can be overridden per client).";
    };

    checkTypes = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          schedule = mkOption {
            type = types.either
              (types.enum [
                "first_working_day_of_month"
                "first_working_day_of_quarter"
                "first_working_day_of_week"
                "every_working_day"
              ])
              (types.submodule {
                options.calendar = mkOption {
                  type = types.str;
                  description = "systemd OnCalendar expression (e.g. \"Mon-Fri *-*-* 08:00:00\").";
                };
              });
            description = "When to create the ticket. Either a structured frequency string or a raw systemd calendar expression ({ calendar = \"...\"; }).";
          };
          titleTemplate = mkOption {
            type = types.str;
            description = "Ticket title. Use {period} as a placeholder for the current period string (e.g. 2026-Q2).";
          };
          description = mkOption {
            type = types.str;
            description = "Ticket description (plain text).";
          };
          issueType = mkOption {
            type = types.str;
            default = "Task";
            description = "Jira issue type name.";
          };
          dueDateOffsetDays = mkOption {
            type = types.int;
            default = 0;
            description = "Number of calendar days after the trigger date to set as due date. 0 means same day.";
          };
        };
      });
      default = {};
      description = "Reusable ticket templates. Each entry defines what ticket to create and how often.";
    };

    clients = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          board = mkOption {
            type = types.str;
            description = "Jira project key (e.g. IIT).";
          };
          checks = mkOption {
            type = types.listOf types.str;
            description = "List of checkTypes names to apply to this client.";
          };
          tokenSecretPath = mkOption {
            type = types.str;
            description = "Path to agenix-decrypted file containing the raw Jira API token.";
          };
          jiraUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Override Jira base URL for this client. Falls back to module-level jiraUrl when null.";
          };
          jiraUser = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Override Jira user email for this client. Falls back to module-level jiraUser when null.";
          };
        };
      });
      default = {};
      description = "Client definitions. Each entry maps a Jira board to a set of check types.";
    };
  };

  config = mkIf cfg.enable {

    # Static ticket fields written at activation time — useful for inspection
    environment.etc = listToAttrs (map (instance:
      nameValuePair "jiraticketcreate/${instance.name}.json" {
        text = builtins.toJSON {
          ticket = {
            board      = instance.client.board;
            issue_type = instance.checkType.issueType;
          };
        };
      }
    ) allInstances);

    systemd.services = listToAttrs (map (instance:
      nameValuePair "jiraticketcreate-${instance.name}" {
        description = "Jira ticket creation for ${instance.name}";
        after  = [ "network-online.target" ];
        wants  = [ "network-online.target" ];
        script = mkScript instance;
        serviceConfig = {
          Type             = "oneshot";
          User             = "root";
          Group            = "root";
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          NoNewPrivileges  = true;
          PrivateDevices   = true;
          ProtectKernelTunables  = true;
          ProtectKernelModules   = true;
          ProtectControlGroups   = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
          RestrictNamespaces = true;
          LockPersonality    = true;
          RestrictRealtime   = true;
          RestrictSUIDSGID   = true;
          RemoveIPC          = true;
          SystemCallFilter   = [ "@system-service" "~@privileged" ];
        };
      }
    ) allInstances);

    systemd.timers = listToAttrs (map (instance:
      nameValuePair "jiraticketcreate-${instance.name}" {
        description = "Timer for Jira ticket creation (${instance.name})";
        wantedBy    = [ "timers.target" ];
        timerConfig = {
          OnCalendar = if builtins.isString instance.checkType.schedule
            then "daily"
            else instance.checkType.schedule.calendar;
          Persistent = true;
        };
      }
    ) allInstances);

  };
}
