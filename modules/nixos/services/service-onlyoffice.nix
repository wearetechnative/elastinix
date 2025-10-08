{ config, lib, tfvars, ... }:

let
  cfg = config.elastinix.services.onlyoffice;
  environment_domain = tfvars.environment_domain;
in
  {
  options.elastinix.services.onlyoffice = {

    enable = lib.mkEnableOption "Only-office for file storage";

    postgres_host = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    postgres_password_file = lib.mkOption {
      type = lib.types.str;
      description = "";
    };
  };

  config = lib.mkIf cfg.enable {

    services.onlyoffice = {
      enable = true;
      hostname = "onlyoffice.${environment_domain}";
      postgresHost = cfg.postgres_host;
      postgresUser = "onlyoffice";
      port = 7777;
      postgresPasswordFile = cfg.postgres_password_file;
    };
  };
}

