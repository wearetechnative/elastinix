{ pkgs, config, tfvars, lib,  ... }:

let
  cfg = config.elastinix.services.twenty-psql;
  infra_environment = tfvars.infra_environment;
in
  {
  options.elastinix.services.frp = {
    enable = lib.mkEnableOption "frp server";
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = with pkgs; [
      frp
    ];

    services.frp = {
      enable = true;
      role = "server";
      settings = {
        bindPort = 7000;
        auth.method = "token";
        auth.token = "VopOstedjok1ddd1";
        vhostHTTPPort = 7070;
        subDomainHost = "ainative.eu";
      };
    };

    services.nginx.virtualHosts."invokeai.ainative.eu" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://invokeai.ainative.eu:7070";
          extraConfig = ''
            auth_basic "Restricted Content";
            proxy_pass_request_headers on;
            proxy_no_cache $cookie_nocache  $arg_nocache$arg_comment;
            proxy_no_cache $http_pragma     $http_authorization;
            proxy_cache_bypass $cookie_nocache $arg_nocache $arg_comment;
            proxy_cache_bypass $http_pragma $http_authorization;
            proxy_set_header HTTP_AUTHORIZATION $http_authorization;
          '';
        };
      };
    };

    services.nginx.virtualHosts."openwebui.ainative.eu" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://openwebui.ainative.eu:7070";
          extraConfig = ''
            proxy_set_header Upgrade           $http_upgrade;
            proxy_set_header Connection        $connection_upgrade;
          '';
        };
      };
    };


    services.nginx.virtualHosts."test.ainative.eu" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://test.ainative.eu:7070";
        };
      };
    };
  };
}
