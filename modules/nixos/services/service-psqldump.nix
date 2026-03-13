{ lib, config, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.psqldump;
  infra_environment = tfvars.infra_environment;
  app = "twentycrm";
  dataDir = "/data/psqldump";
  persistant_storage_s3 = tfvars.docker_twenty_storageS3Name;

  bin.aws = "${pkgs.awscli2}/bin/aws";
  bin.lego = "${pkgs.lego}/bin/lego";
  bin.pgdump = "${pkgs.postgresql}/bin/pg_dump";
  bin.tar = "${pkgs.gnutar}/bin/tar";
  bin.psql = "${pkgs.postgresql}/bin/psql";
  bin.pg_dump = "${pkgs.postgresql}/bin/pg_dump";
  bin.logger = "${pkgs.logger}/bin/logger";
  bin.gzip = "${pkgs.gzip}/bin/gzip";

in {
  options.elastinix.services.psqldump = {

    enable = lib.mkEnableOption "PSQL dump";

    configFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/psql_backup_database_${infra_environment}.env";
      description = "The config file location for psqldump";
    };
  };

  config = lib.mkIf cfg.enable {

    users.groups.${app}.members = [ "${app}" ];
    users.users.${app} = {
      isSystemUser = true;
      group = "${app}";
    };

    # CERTBOT
    systemd.timers."${infra_environment}-psql-backup" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 08:25:00";
        Unit = "${infra_environment}-psql-backup.service";
      };
    };

    services.logrotate.settings = {
      header = {
        dateext = true;
      };
      "/var/log/psqlDatabaseBackup.log" = {
        frequency = "daily";
        rotate = 7;
      };
    };

    systemd.services."${infra_environment}-psql-backup" =
      {
        serviceConfig.Type = "oneshot";
        wantedBy = [ "multi-user.target" ];
        script = ''

      numberOfErrors=0
      trap '((numberOfErrors++))' ERR
      set +e

      exec > >(tee -a /var/log/psqlDatabaseBackup.log | while read line; do ${bin.logger} -t psqlBackup "$line"; done) 2>&1


      psqlDumpPathBase="${dataDir}"
      backupMinimumFiles=5
      backupMinimumAge=7

      config_files=("/run/secrets/psql_backup_database_${infra_environment}.env")

      echo "---- Start run psqlDatabaseBackup $0) - $(date) ----"
      mkdir -p $psqlDumpPathBase
      for cfg in "''${config_files[@]}"; 
      do
      if [ -f "$cfg" ]; then
      source "$cfg"


      databaseConnectionString="postgres://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT"

      echo "--- Processing database host: $DB_HOST"
      echo "------------------------"
      echo "-- Database user: $DB_USER"
      echo "-- Database host: $DB_HOST"
      echo "-- Database port: $DB_PORT"
      echo "------------------------"
      databases=($(${bin.psql}  "$databaseConnectionString" -c 'select datname from pg_database;' |tail -n +3 |head -n -2 | egrep -v 'template0|template1|postgres|default'))
      for database in "''${databases[@]}"
      do
      echo "-- Start dump database: $database - $(date +"%Y%m%d-%H%M%S")"
      psqlDumpPath="$psqlDumpPathBase/$database"
      psqlDumpFile="$psqlDumpPath/$database-$(date +"%Y%m%d-%H%M%S").sql"
      mkdir -p $psqlDumpPath
      ${bin.pg_dump} -f $psqlDumpFile "$databaseConnectionString/$database";
      ${bin.gzip} $psqlDumpFile
      echo "-- End dump database: $database - $(date +"%Y%m%d-%H%M%S")"
      echo ""
      done
      unset databases
      echo ""
      fi 
      done

      echo "--- Backup retention"
      echo "--- Keeping minimum of #$backupMinimumFiles backup files and keeping backups for a minimum of #$backupMinimumAge days."
      for psqlDumpPath in "$psqlDumpPathBase"/*/  ; do
      ls -1tr $psqlDumpPath 2>/dev/null | head -n -$backupMinimumFiles | while read file; do
      fileToCheck=$psqlDumpPath/$file
      if [ -f "$fileToCheck" ] && [ "$(find "$fileToCheck" -mtime +$backupMinimumAge )" ]; then
      echo "--Remove backup file: $fileToCheck"
      rm $fileToCheck
      fi
      done
      done

      # Sync backup files to s3-bucket
      dirname=$(basename "$psqlDumpPathBase") 
      ${bin.aws} s3 sync $psqlDumpPathBase s3://${persistant_storage_s3}/psqlDatabaseBackup-technative-tools/$dirname/ --delete

      if [[ $numberOfErrors -ne 0 ]]; 
      then
      echo "---- Timestamp: $(date)"
      echo "---- Finish run psqlDatabaseBackup with errors ----"
      else
      echo "---- Timestamp: $(date)"
      echo "---- Finish run psqlDatabaseBackup successfully ----"
      fi
      '';
      };
  };
}
