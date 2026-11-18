{
  lib,
  config,
  pkgs,
  inputs,
  tfvars,
  ...
}:

let
  cfg = config.elastinix.services.vaultwarden;
  inherit (tfvars) environment_domain;

  # Oldest release allowed against the production database (migrations are
  # forward-only). Raise this after every production upgrade.
  minimumVersion = "1.37.2";

  # Packages per `source`; attrsets are lazy, so only the selected one is built.
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  packages = {
    pinned = pkgs.callPackage ../../../pkgs/vaultwarden/package.nix { };
    nixpkgs = pkgs.vaultwarden;
    unstable = unstable.vaultwarden;
  };
in

{
  options.elastinix.services.vaultwarden = {

    enable = lib.mkEnableOption "vaultwarden";

    source = lib.mkOption {
      type = lib.types.enum [
        "pinned"
        "nixpkgs"
        "unstable"
      ];
      default = "nixpkgs";
      description = ''
        Where the default `package` comes from: "pinned" builds the upstream
        source pinned in pkgs/vaultwarden/source.json, "nixpkgs" uses
        pkgs.vaultwarden, "unstable" uses the nixpkgs-unstable input.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "Vaultwarden package to run. Defaults to the package selected by `source`.";
      default = packages.${cfg.source};
      defaultText = lib.literalExpression ''
        {
          pinned = pkgs.callPackage <elastinix>/pkgs/vaultwarden/package.nix { };
          nixpkgs = pkgs.vaultwarden;
          unstable = inputs.nixpkgs-unstable.legacyPackages.''${system}.vaultwarden;
        }.''${config.elastinix.services.vaultwarden.source}
      '';
    };

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for vaultwarden";
    };

    nginx = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Render the module's nginx virtual host and its ACME certificate.
          Set this to false when the host declares its own virtual host (and
          certificate) for Vaultwarden, so the consumer flake owns the
          published domain and the module does not add a second one.
        '';
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = "vaultwarden.${environment_domain}";
        defaultText = lib.literalExpression ''"vaultwarden.''${tfvars.environment_domain}"'';
        description = ''
          Fully qualified domain name for the nginx virtual host and its ACME
          certificate. Defaults to `vaultwarden.<environment_domain>`; set it
          when the service is published on another domain, for example
          `vaultwarden.technative.eu`.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (lib.versionOlder cfg.package.version minimumVersion) ''
      elastinix.services.vaultwarden: package version ${cfg.package.version} is older than
      the minimum version ${minimumVersion}. Vaultwarden database migrations are
      forward-only; take a backup of the database before downgrading.
    '';

    services = {
      # Vaultwarden service configuration
      vaultwarden = {
        enable = true;
        inherit (cfg) package;
        # The upstream module takes the web vault from pkgs.vaultwarden; keep it
        # matched to the selected server.
        webVaultPackage = cfg.package.webvault or pkgs.vaultwarden.webvault;
        dbBackend = "postgresql";
        environmentFile = cfg.environment_file;
      };
      nginx = {
        recommendedProxySettings = true;
        virtualHosts = lib.mkIf cfg.nginx.enable {
          "${cfg.nginx.domain}" = {
            enableACME = true;
            forceSSL = true;
            extraConfig = ''
              client_max_body_size 525M;
            '';
            locations = {
              "/" = {
                proxyPass = "http://127.0.0.1:8222";
                proxyWebsockets = true;
              };
            };
          };
        };
      };
    };

    environment.systemPackages = [
      pkgs.system-sendmail
    ];

    security.acme.certs = lib.mkIf cfg.nginx.enable {
      "${cfg.nginx.domain}" = {
        webroot = "/var/lib/acme/acme-challenge";
        group = "nginx";
      };
    };

    systemd.services.vaultwarden.serviceConfig.ReadWritePaths = "/vaultwarden"; # needed to get systemd vaultwarden.service read outside system folders

  };
}
