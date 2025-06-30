{config, lib, pkgs, tfvars, ...}:
let

  environment_domain = tfvars.environment_domain;
  infra_environment = tfvars.infra_environment;
  hedgedoc-secret = "hedgedoc-${infra_environment}";
  cfg = config.elastinix.services.hedgedoc;

in
{
  options.elastinix.services.hedgedoc = {
    enable = lib.mkEnableOption "enable hedgedoc service";
      #   secretsFile = lib.mkOption {
      #       type = lib.types.path;
      #       description = "Where to find the secrets file.";
      #   };

  };

  config = lib.mkIf cfg.enable {

    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    #age.secrets.${hedgedoc-secret}.file = cfg.secretsFile;

    services.hedgedoc = {
      enable = true;
      environmentFile = config.age.secrets.${hedgedoc-secret}.path;
      settings = {
        domain = "hedgedoc.${environment_domain}";
        defaultNotePath = "/var/lib/hedgedoc/uploads/default.md";
        dbURL = "postgres://hedgedoc:\${DB_PASSWORD}@psql.${environment_domain}:5432/hedgedoc";
        protocolUseSSL = true;
        allowOrigin = [
          "localhost"
          "hedgedoc.${environment_domain}"
        ];
        port = 3001;
        host = "localhost";
      };
    };

    services.nginx.virtualHosts."hedgedoc.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://localhost:3001";
        };
        "/socket.io/" = {
          proxyPass = "http://localhost:3001";
          proxyWebsockets = true;
          extraConfig =
            "proxy_ssl_server_name on;"
            ;
        };
      };
    };

  };

}
