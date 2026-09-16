{ lib, config, options, pkgs, inputs, tfvars, ... }:

let
  cfg = config.elastinix.services.badgersbay;
  opt = options.elastinix.services.badgersbay;
  badgersbayPackage = inputs.badgersbay.packages.${pkgs.system}.default;
  environment_domain = tfvars.environment_domain;

  yamlFormat = pkgs.formats.yaml { };

  # The configuration the module generates. It is a world-readable store path,
  # which is exactly why nothing secret is allowed into `settings`: the tokens,
  # the dashboard password and the asset register arrive as file paths from
  # agenix and are never composed here.
  generatedConfigFile = yamlFormat.generate "badgersbay-config.yaml" cfg.settings;

  # agenix, if this host has it. The module works without it - the secret paths
  # are plain paths - so every check below degrades to being skipped rather
  # than to an evaluation error about a missing `age` option.
  ageConfig = config.age or null;
  ageSecrets = if ageConfig == null then [ ] else lib.attrValues ageConfig.secrets;
  ageSecretsDir = if ageConfig == null then null else ageConfig.secretsDir;

  # Every secret path the service is given, with the option name to blame.
  secretFiles =
    [
      { option = "tokenFile"; value = cfg.tokenFile; }
      { option = "dashboardPasswordFile"; value = cfg.dashboardPasswordFile; }
    ]
    ++ lib.optional (cfg.assetRegisterFile != null) {
      option = "assetRegisterFile";
      value = cfg.assetRegisterFile;
    };

  # An option's `default` is injected as a definition at `mkOptionDefault`
  # priority, so `isDefined` is true even for an option nobody touched. A
  # priority below that is the only honest signal that a host set it.
  setByHost = option: option.highestPrio < 1500;

  # A nix path literal is copied into the store the moment it is interpolated
  # into the unit; a store path is already there. Both are world-readable, so
  # both are refused.
  inNixStore = value: builtins.isPath value || lib.hasPrefix builtins.storeDir (toString value);

  underAgenix = value:
    ageSecretsDir != null && lib.hasPrefix "${ageSecretsDir}/" (toString value);

  declaredSecret = value:
    lib.findFirst (secret: secret.path == toString value) null ageSecrets;

  # Only numeric modes can be judged; agenix hands `mode` to chmod, which also
  # accepts symbolic forms, and a form we cannot read is not a form we should
  # fail a deploy over.
  octalMode = mode:
    let parts = builtins.match "[0-7]?([0-7])([0-7])([0-7])" (toString mode); in
    if parts == null then null else {
      user = lib.toInt (builtins.elemAt parts 0);
      group = lib.toInt (builtins.elemAt parts 1);
      other = lib.toInt (builtins.elemAt parts 2);
    };

  # A numeric owner other than root cannot be matched against a user name, so
  # it is left alone rather than guessed at.
  ambiguousOwner = owner: owner != "0" && builtins.match "[0-9]+" owner != null;

  # True only when the file is certainly out of reach: root can read anything,
  # an unknown owner is not judged, and any read bit that applies is enough.
  unreadableByService = secret:
    let mode = octalMode secret.mode; in
    cfg.user != "root"
    && mode != null
    && !(ambiguousOwner secret.owner)
    && mode.other < 4
    && !(secret.owner == cfg.user && mode.user >= 4)
    && !(secret.group == cfg.group && mode.group >= 4);
in

{
  options.elastinix.services.badgersbay = {

    enable = lib.mkEnableOption "Badgersbay file processing service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9117;
      description = ''
        Port number for the badgersbay service.

        This is the port the firewall opens and the nginx virtual host proxies
        to, so it is the one to change. `settings.networkport` follows it.
      '';
    };

    storagePath = lib.mkOption {
      type = lib.types.str;
      default = "/data/badgersbay";
      description = "Path where badgersbay stores and processes files";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to YAML file containing API tokens for report submission.

        Format:
        ```yaml
        tokens:
          - hb_token_abc123
          - hb_token_xyz789
        ```

        Required for authentication. Use agenix to encrypt this file.
      '';
      example = "config.age.secrets.badgersbay-tokens.path";
    };

    assetRegisterFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the asset register: the CSV of systems expected to report,
        exported from the `Active Assets` sheet of the ISO compliance
        spreadsheet.

        This is the denominator badgersbay measures coverage against. Without
        it the dashboard can show what arrived but never which systems are
        missing, and both its views say so.

        Format:
        ```csv
        asset_id,serial,owner,model,class,status,owner_since,valid_from,valid_to,departure_reason
        TARI-00023,PF50L2MR,Wouter van der Toorren,LENOVO 21K9CTO1WW,linux,active,2024-01-01,2024-01-01,,
        ```

        The file pairs employee names with hardware serials, so use agenix to
        encrypt it, as for the tokens and the dashboard password.

        Badgersbay refuses to start on a register it cannot trust - a duplicate
        active serial, an unknown platform class, an unparseable date - because
        a compliance figure built on one cannot be trusted either.

        Optional. A host that does not set it runs without a register.
      '';
      example = "config.age.secrets.badgersbay-assets.path";
    };

    dashboardPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to plaintext file containing the password for web dashboard access.
        The file should contain a single line with the password.

        Required for dashboard authentication. Use agenix to encrypt this file.
      '';
      example = "config.age.secrets.badgersbay-password.path";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "badgersbay";
      description = "User to run the service as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "badgersbay";
      description = "Group to run the service as";
    };

    settings = lib.mkOption {
      default = { };
      description = ''
        The badgersbay configuration, rendered to YAML.

        The module owns the structure - which keys exist, what shape they have,
        what they default to - so a host can change one value without replacing
        the file, and so a changed default reaches every host that has not.

        Nothing secret belongs here. The rendered file is a world-readable nix
        store path; the API tokens, the dashboard password and the asset
        register are delivered as agenix secrets through `tokenFile`,
        `dashboardPasswordFile` and `assetRegisterFile`, and the module only
        ever receives their paths.

        Keys the module does not declare are passed through unchanged, so a
        configuration key badgersbay gains can be set before this module knows
        about it.

        Ignored when `configFile` is set, which is why setting both is an
        evaluation error.
      '';
      example = lib.literalExpression ''
        {
          compliance = {
            audit_months = [ 2 8 ];
            grace_weeks = 6;
            required_reports.per_class.windows = {
              sysinfo = [ "fastfetch" ];
              hardening = [ "hardeningkitty" ];
            };
          };
        }
      '';
      type = lib.types.submodule {
        freeformType = yamlFormat.type;

        options = {
          networkport = lib.mkOption {
            type = lib.types.port;
            default = cfg.port;
            defaultText = lib.literalExpression "config.elastinix.services.badgersbay.port";
            description = ''
              Port the server listens on. Follows `port`, which is also what
              the firewall opens and what nginx proxies to; setting it to
              anything else is an evaluation error.
            '';
          };

          storage_location = lib.mkOption {
            type = lib.types.str;
            default = "${cfg.storagePath}/reports";
            defaultText = lib.literalExpression ''"''${config.elastinix.services.badgersbay.storagePath}/reports"'';
            description = "Directory the server writes submissions to.";
          };

          compliance = lib.mkOption {
            description = "Compliance tracking: the audit rounds and what a system has to submit to be counted.";
            default = { };
            type = lib.types.submodule {
              freeformType = yamlFormat.type;

              options = {
                enabled = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = ''
                    Track compliance rounds. With this off the server keeps
                    accepting and storing reports, but the dashboard reports
                    no rounds and no coverage.
                  '';
                };

                audit_months = lib.mkOption {
                  type = lib.types.listOf (lib.types.ints.between 1 12);
                  default = [ 3 9 ];
                  description = ''
                    Months in which an audit round opens, as month numbers.
                    Two rounds a year is the ISO cadence we run.
                  '';
                };

                grace_weeks = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  default = 4;
                  description = ''
                    Weeks past the audit month during which a submission still
                    counts toward the round, and during which an asset
                    entering scope still belongs to it. One value, both
                    boundaries.
                  '';
                };

                required_reports = lib.mkOption {
                  description = "What a system has to submit to count as complete.";
                  default = { };
                  type = lib.types.submodule {
                    freeformType = yamlFormat.type;

                    options = {
                      mandatory = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ "fastfetch" "lynis" ];
                        description = ''
                          Report types every system must submit. `fastfetch`
                          carries the system identity; badgersbay stopped
                          accepting `neofetch` at 844176c.
                        '';
                      };

                      one_of = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [ ];
                        description = ''
                          Report types of which at least one must arrive, for
                          example a vulnerability scanner that differs per
                          platform. Empty means no such requirement.
                        '';
                      };

                      per_class = lib.mkOption {
                        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
                        default = { };
                        example = {
                          windows = {
                            sysinfo = [ "fastfetch" ];
                            hardening = [ "hardeningkitty" ];
                          };
                        };
                        description = ''
                          Requirements per platform class, overriding the
                          server's built-in table for the classes named here.

                          A requirement is named after what it is - `sysinfo`,
                          `hardening` - and lists the report types that
                          satisfy it, because the tools that do differ per
                          platform and change over time.
                        '';
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      default = generatedConfigFile;
      defaultText = lib.literalExpression "a YAML file rendered from `settings`";
      description = ''
        Path to the badgersbay configuration file.

        By default this is the file rendered from `settings`. Setting it
        replaces that file whole: the module's defaults no longer reach this
        host, which is how a host can miss a changed default entirely. Prefer
        `settings`.

        The configuration carries no secrets, so it does not need to be
        delivered as one. A host on an agenix config secret can move its values
        into `settings` and drop this option.

        Setting this together with `settings` is an evaluation error, because
        one of the two would have to be discarded silently.
      '';
      example = lib.literalExpression "config.age.secrets.badgersbay-config.path";
    };
  };

  config = lib.mkIf cfg.enable {

    assertions =
      [
        {
          assertion = !(setByHost opt.configFile && setByHost opt.settings);
          message = ''
            elastinix.services.badgersbay: `configFile` and `settings` are both
            set. An explicit `configFile` replaces the generated file whole, so
            `settings` would be discarded without a word. Set one of the two:
            move the values into `settings` and drop `configFile`, or keep
            `configFile` and leave `settings` alone.
          '';
        }
        {
          assertion = cfg.settings.networkport == cfg.port;
          message = ''
            elastinix.services.badgersbay: `settings.networkport`
            (${toString cfg.settings.networkport}) differs from `port`
            (${toString cfg.port}). The firewall rule and the nginx proxy
            follow `port`, so the server would listen where neither reaches it.
            Set `port` instead.
          '';
        }
        {
          assertion = !(cfg.settings.compliance ? asset_register);
          message = ''
            elastinix.services.badgersbay: `settings.compliance.asset_register`
            is set. The service passes `--asset-register`, which overrides the
            configuration file, so this value would never be used. Set
            `assetRegisterFile` instead - and keep the register an agenix
            secret, since it pairs employee names with hardware serials.
          '';
        }
      ]
      ++ lib.concatMap
        (secret:
        let
          declared = declaredSecret secret.value;
          # Kept out of the message body so it is never forced when there is
          # no declared secret to describe.
          ownership =
            if declared == null then "unknown"
            else "${declared.owner}:${declared.group} at mode ${declared.mode}";
        in [
          {
            assertion = !(inNixStore secret.value);
            message = ''
              elastinix.services.badgersbay: `${secret.option}`
              (${toString secret.value}) ${
                if builtins.isPath secret.value
                then "is a path literal, which is copied into the nix store the moment the unit interpolates it"
                else "is a nix store path"
              }. The store is world-readable on every machine that has the path,
              so a secret must never be written there - not by `pkgs.writeText`,
              and not by a path literal. Deliver the file with agenix and pass
              its `.path`.
            '';
          }
          {
            assertion = !(underAgenix secret.value) || declared != null;
            message = ''
              elastinix.services.badgersbay: `${secret.option}` points at
              ${toString secret.value}, under `age.secretsDir`, but no
              `age.secrets` entry produces that path. Nothing will write the
              file, and the service will fail at start instead of here. Declare
              the secret, or correct the path.
            '';
          }
          {
            assertion = declared == null || !(unreadableByService declared);
            message = ''
              elastinix.services.badgersbay: the agenix secret behind
              `${secret.option}` (${toString secret.value}) is ${ownership},
              which the service user ${cfg.user} cannot read. agenix defaults to
              root-owned 0400, so this is the usual case rather than an exotic
              one. Set `owner = "${cfg.user}"` on that secret, or give it
              `group = "${cfg.group}"` with a group-readable mode.
            '';
          }
        ])
        secretFiles;

    environment.systemPackages = [ badgersbayPackage ];

    users.users.${cfg.user} = lib.mkIf (cfg.user == "badgersbay") {
      isSystemUser = true;
      uid = 994;
      group = cfg.group;
      description = "Badgersbay service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "badgersbay") {
      gid = 991;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];

    systemd.services.badgersbay = {
      description = "Badgersbay file processing service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # The register is passed as an argument rather than written into the
      # generated configuration, so a host that overrides configFile with its
      # own secret - as compute2 does - does not have to have that secret
      # reissued to gain a register.
      script = ''
        ${badgersbayPackage}/bin/honeybadger-server \
          --config ${cfg.configFile} \
          --token-file ${cfg.tokenFile} \
          --dashboard-password-file ${cfg.dashboardPasswordFile} \
          ${lib.optionalString (cfg.assetRegisterFile != null)
            "--asset-register ${cfg.assetRegisterFile}"}
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.storagePath;
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
        ReadWritePaths = [ cfg.storagePath ];
      };
    };
    
    systemd.timers.badgersbay = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly"; 
        Persistent = true;
      };
    };

    services.nginx.virtualHosts."badgersbay.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
