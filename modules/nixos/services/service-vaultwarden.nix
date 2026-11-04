{ lib, config, pkgs, inputs, tfvars, ... }:

let
  cfg = config.elastinix.services.vaultwarden;
  environment_domain = tfvars.environment_domain;

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
      type = lib.types.enum [ "pinned" "nixpkgs" "unstable" ];
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
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (lib.versionOlder cfg.package.version minimumVersion) ''
      elastinix.services.vaultwarden: package version ${cfg.package.version} is older than
      the minimum version ${minimumVersion}. Vaultwarden database migrations are
      forward-only; take a backup of the database before downgrading.
    '';

    # Vaultwarden service configuration
    services.vaultwarden = {
      enable = true;
      package = cfg.package;
      # The upstream module takes the web vault from pkgs.vaultwarden; keep it
      # matched to the selected server.
      webVaultPackage = cfg.package.webvault or pkgs.vaultwarden.webvault;
      dbBackend = "postgresql";
      environmentFile = cfg.environment_file;
    };

    environment.systemPackages = [
      pkgs.system-sendmail
    ];

    security.acme.certs."vaultwarden.${environment_domain}" = {
      webroot = "/var/lib/acme/acme-challenge";
      group = "nginx";
    };

    systemd.services.vaultwarden.serviceConfig.ReadWritePaths = "/vaultwarden"; # needed to get systemd vaultwarden.service read outside system folders

    services.nginx.virtualHosts."vaultwarden.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8222";
        };
      };
    };
  };
}
