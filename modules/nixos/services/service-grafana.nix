{ lib, config, tfvars, ... }:

let
  cfg = config.elastinix.services.grafana;
  environment_domain = tfvars.environment_domain;

  # Customer submodule for elastinix
  customerModule = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Customer name (used for job naming and file paths)";
        example = "technative";
      };

      probesFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to the YAML file containing URLs to probe";
        example = ./customers/technative/probes/urls.yaml;
      };

      alertRules = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = "List of alert rule files for this customer";
        example = [ ./customers/technative/alerts/alert-ssl_expiration.yml ];
      };

      dashboardsPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to directory containing Grafana dashboard JSON files for this customer";
        example = ./dashboards/technative;
      };

      dashboardFiles = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Dashboard filename (e.g., 'ssl-check.json')";
            };
            source = lib.mkOption {
              type = lib.types.path;
              description = "Path to the dashboard JSON file (can be an agenix secret path at runtime)";
            };
          };
        });
        default = [];
        description = ''
          List of individual dashboard files for this customer.
          Use this option when dashboards are stored as individual files (e.g., agenix secrets)
          instead of in a directory. Cannot be used together with dashboardsPath.
        '';
        example = lib.literalExpression ''
          [
            {
              name = "ssl-check.json";
              source = config.age.secrets.dashboard-ssl.path;
            }
          ]
        '';
      };

      blackboxModule = lib.mkOption {
        type = lib.types.str;
        default = "http_2xx";
        description = "Blackbox exporter module to use";
      };

      refreshInterval = lib.mkOption {
        type = lib.types.str;
        default = "5m";
        description = "How often to refresh the probes file";
      };
    };
  };

in {
  options.elastinix.services.grafana = {
    enable = lib.mkEnableOption "Prometheus and Grafana monitoring stack";

    customers = lib.mkOption {
      type = lib.types.listOf customerModule;
      default = [];
      description = "List of customers to monitor with their specific configurations";
      example = lib.literalExpression ''
        [
          {
            name = "technative";
            probesFile = ./customers/technative/probes/urls.yaml;
            alertRules = [ ./customers/technative/alerts/alert-ssl_expiration.yml ];
            dashboardsPath = ./dashboards/technative;
          }
        ]
      '';
    };

    root_domain = lib.mkOption {
      type = lib.types.str;
      default = environment_domain;
      description = "Root domain for Grafana nginx configuration";
      example = "example.com";
    };

    alertmanager = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Prometheus Alertmanager";
      };

      configuration = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = ''
          Alertmanager configuration as a Nix attribute set.
          See https://prometheus.io/docs/alerting/latest/configuration/ for available options.
        '';
        example = lib.literalExpression ''
          {
            global.resolve_timeout = "5m";
            route = {
              receiver = "slack-notifications";
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "3h";
            };
            receivers = [
              {
                name = "slack-notifications";
                slack_configs = [
                  {
                    send_resolved = true;
                    channel = "#alerts";
                    api_url_file = "/run/secrets/slack-webhook";
                  }
                ];
              }
            ];
          }
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Use the grafana flake module
    services.grafana = {
      enable = true;
      customers = cfg.customers;
      root_domain = cfg.root_domain;
      alertmanager = {
        enable = cfg.alertmanager.enable;
        configuration = cfg.alertmanager.configuration;
      };
    };
  };
}
