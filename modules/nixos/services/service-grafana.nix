{ lib, config, tfvars, ... }:

let
  cfg = config.elastinix.services.grafana-prometheus;
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
  options.elastinix.services.grafana-prometheus = {
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

    oauth2Proxy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Protect the Prometheus and Alertmanager vhosts with oauth2-proxy
          (OIDC) via nginx `auth_request`, reusing an external identity provider
          (AWS Cognito) for SSO consistent with Grafana. The Grafana vhost keeps
          its own OAuth.

          Requires an OIDC app client on the identity provider with the callback
          URLs `https://prometheus.<root_domain>/oauth2/callback` and
          `https://alertmanager.<root_domain>/oauth2/callback`.
        '';
      };

      oidcIssuerUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC issuer URL of the identity provider (e.g. Cognito user pool).";
        example = "https://cognito-idp.eu-central-1.amazonaws.com/eu-central-1_abc123";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC app client id for the monitoring oauth2-proxy.";
      };

      clientSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the OIDC client secret (e.g. an agenix
          secret path). Read at runtime via systemd credentials.
        '';
        example = "/run/agenix/oauth2-proxy-client-secret";
      };

      cookieSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the oauth2-proxy cookie secret (16, 24 or 32
          bytes). Read at runtime via systemd credentials.
        '';
        example = "/run/agenix/oauth2-proxy-cookie-secret";
      };

      allowedGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Groups (from the OIDC groups claim) allowed to access Prometheus and
          Alertmanager. Empty means any user authenticated by the pool.
        '';
        example = [ "grafana-admin" ];
      };

      groupsClaim = lib.mkOption {
        type = lib.types.str;
        default = "groups";
        description = ''
          Name of the OIDC token claim carrying group membership. AWS Cognito
          exposes groups under `cognito:groups`.
        '';
        example = "cognito:groups";
      };
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

    services.grafana-prometheus = {
      enable = true;
      customers = cfg.customers;
      root_domain = cfg.root_domain;
      alertmanager = {
        enable = cfg.alertmanager.enable;
        configuration = cfg.alertmanager.configuration;
      };
      oauth2Proxy = {
        enable = cfg.oauth2Proxy.enable;
        oidcIssuerUrl = cfg.oauth2Proxy.oidcIssuerUrl;
        clientId = cfg.oauth2Proxy.clientId;
        clientSecretFile = cfg.oauth2Proxy.clientSecretFile;
        cookieSecretFile = cfg.oauth2Proxy.cookieSecretFile;
        allowedGroups = cfg.oauth2Proxy.allowedGroups;
        groupsClaim = cfg.oauth2Proxy.groupsClaim;
      };
    };
  };
}
