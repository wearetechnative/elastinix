{ config, tfvars, lib, pkgs, nixpkgs2411, fossarPhps, ... }:

let
  cfg = config.elastinix.services.phpnginx;
  infra_environment = tfvars.infra_environment;
in
  {

  options.elastinix.services.phpnginx = {

    enable = lib.mkEnableOption "Web server with php and nginx";

    app_name = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The app name that should be used";
    };

    environment = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The environment that should be used";
    };

    php_version = lib.mkOption {
      type = lib.types.str;
      default = "php83";
      description = "The PHP version that should be used, default is php83";
    };

    php_options = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The PHP options that can be set";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The domain that can be set";
    };

    domain_aliases = lib.mkOption {
      type = lib.types.list;
      default = [];
      description = "The domain aliases that can be set";
    };

    user_uid = lib.mkOption {
      type = lib.types.int;
      default = null;
      description = "The user uid to run the services";
    };

    artifact_bucket = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The artifact bucket that should be set";
    };

    tarfile = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The tarfile that should be set";
    };

    env_patch_list = lib.mkOption {
      type = lib.types.list;
      default = [];
      description = "The artifact bucket that should be set";
    };

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.any);
      default = {};
      description = ''
      '';
    };

  };

  #config = lib.mkIf cfg.enable {
  config = let
    instances = config.elastinix.services.phpnginx.instances;
  in lib.mkMerge (lib.mapAttrs (_name: envCfg:
  {

    phpngninx = let
      certEmail = "sysadmin+${envCfg.environment}@technative.eu";
      certdir = "/data/acme/${envCfg.app_name}";
      certfile = "${certdir}/certificates/${envCfg.domain}.crt";
      certkeyfile = "${certdir}/certificates/${envCfg.domain}.key";

      app = _name;
      dataDir = "/var/www/${app}/html";
      appDir = "/var/www/${app}";

      #php_version = envCfg.php_version;
      #php_packages = "${php_version}Packages";

      bin.aws = "${pkgs.awscli2}/bin/aws";
      bin.lego = "${pkgs.lego}/bin/lego";
      bin.git = "${pkgs.git}/bin/git";
      bin.awk = "${pkgs.gawk}/bin/awk";
      bin.jq = "${pkgs.jq}/bin/jq";
      bin.tar = "${pkgs.gnutar}/bin/tar";
      bin.openssl = "${pkgs.openssl}/bin/openssl";
      bin.composer = "${pkgs.php83Packages.composer}/bin/composer";

    in {
      users.groups.${app} = {
	members = [ "${app}" ];
	gid = envCfg.user_uid;
      };
      users.users.${app} = {
	isSystemUser = true;
	group = "${app}";
	uid = envCfg.user_uid;
      };
      users.users.nginx.extraGroups = [ "${app}" "acme" ];

      environment.systemPackages = [
	# pkgs.${envCfg.php_version}Packages.composer
	pkgs."${envCfg.php_version}Packages".composer
	pkgs.${envCfg.php_version}
      ];

      services.phpfpm.pools.${app} = {
	user = app;
	phpOptions = envCfg.php_options;
	phpPackage = fossarPhps.packages.x86_64-linux.${envCfg.php_version};
	settings = {
	  "pm" = "dynamic";
	  "pm.max_children" = 32;
	  "pm.max_requests" = 500;
	  "pm.start_servers" = 2;
	  "pm.min_spare_servers" = 2;
	  "pm.max_spare_servers" = 5;
	  "php_admin_value[error_log]" = "stderr";
	  "php_admin_flag[log_errors]" = true;
	  "listen.owner" = config.services.nginx.user;
	  "listen.group" = config.services.nginx.group;
	  "listen.mode" = "0660";
	  "catch_workers_output" = 1;
	  "php_admin_value[post_max_size]" = "220M";
	  "php_admin_value[memory_limit]" = "1536M";
	  "request_terminate_timeout" = 300;
	};
      };

      ## TODO: Variable per environment
      security.acme = {
	acceptTerms = true;
	defaults.email = "sysadmin+${envCfg.environment}@technative.eu";
      };

      services.nginx = {
	enable = true;
	serverNamesHashBucketSize = 128;
	virtualHosts = {
	  ${envCfg.domain} = {
	    root = "${dataDir}";
	    serverAliases = envCfg.domain_aliases;
	    extraConfig = ''
	    index index.php;
	    keepalive_timeout 5m;
	    send_timeout 5m;
	    client_body_timeout 5m;
	    client_header_timeout 5m;
	    proxy_connect_timeout 5m;
	    proxy_read_timeout 5m;
	    proxy_send_timeout 5m;
	    fastcgi_connect_timeout 5m;
	    fastcgi_read_timeout 5m;
	    fastcgi_send_timeout 5m;
	    memcached_connect_timeout 5m;
	    memcached_read_timeout 5m;
	    memcached_send_timeout 5m;
	    '';

	    forceSSL = true;
	    sslCertificate = certfile;
	    sslCertificateKey = certkeyfile;

	    locations."~ ^(.+\\.php)(.*)$" = {
	      fastcgiParams = {
		"fastcgi_read_timeout" = "300";
	      };
	      extraConfig = ''
	    # Check that the PHP script exists before passing it
	    try_files $fastcgi_script_name =404;
	    include ${config.services.nginx.package}/conf/fastcgi_params;
	    fastcgi_split_path_info ^(.+\.php)(.*)$;
	    #fastcgi_split_path_info ^(.+\.php)(/.+)$;
	    fastcgi_pass unix:${config.services.phpfpm.pools.${app}.socket};
	    fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
	    fastcgi_param  PATH_INFO        $fastcgi_path_info;
	    include ${pkgs.nginx}/conf/fastcgi.conf;
	    proxy_pass_request_headers on;
	    proxy_read_timeout 300;
	    proxy_connect_timeout 300;
	      '';
	    };

	    locations."/app/" = {
	      fastcgiParams = {
		"fastcgi_read_timeout" = "300";
	      };
	      extraConfig = ''
	    # Any additional configuration for /app/ location
	    proxy_read_timeout 300;
	    proxy_connect_timeout 300;
	      '';
	    };

	    locations."/static/" = {
	      fastcgiParams = {
		"fastcgi_read_timeout" = "300";
	      };
	      extraConfig = ''
	    # Any additional configuration for /static/ location
	    proxy_read_timeout 300;
	    proxy_connect_timeout 300;
	      '';
	    };
	    locations."/" = {
	      fastcgiParams = {
		"fastcgi_read_timeout" = "300";
	      };
	      extraConfig = ''
	     proxy_pass_request_headers on;
	     try_files $uri $uri/ /index.php?$query_string;
	     proxy_read_timeout 300;
	     proxy_connect_timeout 300;
	      '';
	    };

	    locations."~ \\.php$" = {
	      fastcgiParams = {
		"fastcgi_read_timeout" = "300";
	      };
	      extraConfig = ''
	    include ${config.services.nginx.package}/conf/fastcgi_params;
	    include ${pkgs.nginx}/conf/fastcgi.conf;
	    fastcgi_split_path_info ^(.+\.php)(.*)$;
	    fastcgi_pass unix:${config.services.phpfpm.pools.${app}.socket};
	    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
	    fastcgi_param PATH_INFO $fastcgi_path_info;
	    try_files $uri $uri/ /index.php?$args;
	    proxy_pass_request_headers on;
	    proxy_read_timeout 300;
	    proxy_connect_timeout 300;
	      '';
	    };
	  };
	};
      };


      systemd.services."${app}-initial-index-php" = {
	serviceConfig.Type = "oneshot";
	wantedBy = [ "multi-user.target" ];
	script = ''

      if [ ! -f ${dataDir}/index.php ]; then
      mkdir -p ${dataDir}

	touch ${dataDir}/index.php

	echo "<h1> ${app} </h1>" >> ${dataDir}/index.php
	echo "<a href=\"./info.php\">phpinfo...</a>" >> ${dataDir}/index.php

	touch ${dataDir}/info.php

	echo "<?php" >> ${dataDir}/info.php
	echo "phpinfo();" >> ${dataDir}/info.php
	echo "?>" >> ${dataDir}/info.php

	chown -Rc ${app}:${app} ${dataDir}
      fi
      '';
      };

      # CERTBOT
      systemd.timers."${app}-cert-refresh" = {
	wantedBy = [ "timers.target" ];
	timerConfig = {
	  OnCalendar = "*-*-* 01:00:00";
	  Unit = "${app}-cert-refresh.service";
	};
      };

      systemd.services."${app}-cert-refresh" =
	let
	  legoDomains = builtins.concatStringsSep "," ([ envCfg.domain ] ++ envCfg.domain_aliases);
	in
	  {
	  serviceConfig.Type = "oneshot";
	  wantedBy = [ "multi-user.target" ];
	  script = ''

      echo "Refresh Cert for: ${app} - ${envCfg.domain}"

      export TMP_AWS_ACCESS_KEY_ID=$(${bin.aws} ssm get-parameter --name /letsencrypt/aws_access_key_id --output text --query Parameter.Value)
      export TMP_AWS_SECRET_ACCESS_KEY=$(${bin.aws} ssm get-parameter --name /letsencrypt/aws_secret_access_key --with-decryption --output text --query Parameter.Value)
      export TMP_AWS_REGION=$(${bin.aws} ssm get-parameter --name /letsencrypt/aws_region --output text --query Parameter.Value)
      export TMP_AWS_HOSTED_ZONE_DOMAIN=$(echo ${envCfg.domain} | ${bin.awk} -F '.' '{ for(i=2; i<=NF; i++) { printf "%s", $i; if(i < NF) printf "." }; printf "\n" }')
      export TMP_AWS_HOSTED_ZONE_ID=$(${bin.aws} ssm get-parameter --name /letsencrypt/$TMP_AWS_HOSTED_ZONE_DOMAIN/aws_hosted_zone_id --output text --query Parameter.Value)



      export AWS_ACCESS_KEY_ID=$TMP_AWS_ACCESS_KEY_ID
      export AWS_SECRET_ACCESS_KEY=$TMP_AWS_SECRET_ACCESS_KEY
      export AWS_REGION=$TMP_AWS_REGION
      export AWS_HOSTED_ZONE_ID=$TMP_AWS_HOSTED_ZONE_ID

      if [[ -f ${certfile} ]]; then
      echo "$(date) - renewal fase" >> /tmp/lego-${envCfg.domain}

      expiryDate=$(date -d "$(${bin.openssl} x509 -enddate -noout -in ${certfile} |cut -d= -f2)" +%s)
      currentDate=$(date +"%s")
      let daysToExpiration="($expiryDate-$currentDate) /86400"
      if [[ $daysToExpiration  -lt 30  ]];
      then
      echo "Certificate renwal" >> /tmp/lego-${envCfg.domain}
      ${bin.lego} --email="${certEmail}" --domains="${legoDomains}" --dns route53 --path ${certdir} renew
      else
      echo "Certificate is not eligible for renewal. Days to expiry: $daysToExpiration" >> /tmp/lego-${envCfg.domain}
      fi
      else
      echo "$(date) - run fase" >> /tmp/lego-${envCfg.domain}
      ${bin.lego} --email="${certEmail}" --domains="${legoDomains}" --dns route53 --accept-tos=true --path ${certdir} run
      fi

      sleep 5
      echo "-- Setting permissions --"
      find ${certdir} -type d -exec chmod 770 {} \;
      find ${certdir} -type f -exec chmod 660 {} \;
      find ${certdir} -exec chown nginx:nginx {} \;

      systemctl restart nginx.service

	    '';
	};

      # DEPLOY

      systemd.timers."${app}-s3-deploy" = {
	wantedBy = [ "timers.target" ];
	timerConfig = {
	  OnBootSec = "1m";
	  OnUnitActiveSec = "1m";
	  Unit = "${app}-s3-deploy.service";
	};
      };

      systemd.services."${app}-s3-deploy" =
	let
	  patchCmds = lib.strings.concatStrings (builtins.map (patchPair: ''
	    ${bin.aws} ssm get-parameter --name ${patchPair.paramstore_key} --with-decryption --output text --query Parameter.Value > ${appDir}${patchPair.dest_path}
	  '') envCfg.env_patch_list);
	in
	  {
	  serviceConfig.Type = "oneshot";
	  wantedBy = [ "multi-user.target" ];
	  script = ''

      mkdir -p ${dataDir}
      export PATH=$PATH:${pkgs.gzip}/bin:${pkgs.openssh}/bin
      export LOCAL_VERSION=$(cat ${appDir}/sourcecode_version_id)

      export COMPOSER_ALLOW_SUPERUSER=1
      export COMPOSER_HOME=${appDir}
      export HOME=/root

      ${bin.aws} s3api list-object-versions \
      --bucket ${envCfg.artifact_bucket} \
      --prefix ${envCfg.tarfile} \
      | ${bin.jq} '.Versions | .[] | select(.IsLatest)|.VersionId' \
      > ${appDir}/sourcecode_version_id || echo "none" > ${appDir}/sourcecode_version_id

      export REMOTE_VERSION=$(cat ${appDir}/sourcecode_version_id)

      echo "S3-DEPLOY: Comparing local and remote versions"
      echo " local: $LOCAL_VERSION"
      echo " remote: $REMOTE_VERSION"

      if [[ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]]; then

      echo "S3-DEPLOY: Install devkey in root"
      ${bin.aws} ssm get-parameter \
      --name /shared/iit_developer_keypair/private \
      --with-decryption --output text --query Parameter.Value > /root/.ssh/id_ed25519
      chmod 600 /root/.ssh/id_ed25519

      echo "S3-DEPLOY: Creating backup"
      ${bin.tar} czf ${appDir}/backup-$(date +"%Y_%m_%d_%I_%M_%p")-${envCfg.tarfile} ${dataDir}

      echo "S3-DEPLOY: Removing earlier backups"
      ls -tp ${appDir}/backup-* | grep -v '/$'| tail -n +4 | xargs -I {} rm -- {}

      echo "S3-DEPLOY: Installing new version"
      ${bin.aws} s3 cp s3://${envCfg.artifact_bucket}/${envCfg.tarfile} /tmp/
      rm -Rfv ${dataDir}
      mkdir -p ${dataDir}
      ${bin.tar} xzf /tmp/${envCfg.tarfile} -C ${dataDir} --warning=no-unknown-keyword

      ## copied to below find ${appDir} -not -user ${app} -exec chown -Rf ${app}:${app} {} \;

      #cd ${dataDir} && ${bin.git} config --global --add safe.directory '*'
      #cd ${dataDir} && ${bin.composer} install
      #cd ${dataDir}/alltrack-core && ${bin.composer} install

      # Create folders - temporary solution

      mkdir -p ${dataDir}/alltrack-cust-${envCfg.environment}/log


      ${patchCmds}

      ## create dirs and symlinks for persistent storage uploads

      mkdir -p /data/${app}/uploads
      ln -sf /data/${app}/uploads ${dataDir}/uploads


      mkdir -p /data/${app}/tmp
      ln -sf /data/${app}/tmp ${dataDir}/alltrack-cust-${envCfg.environment}/tmp

      ## create dirs and symlinks for persistent storage data for xmlsin and xmlsout

      mkdir -p /data/${app}/data
      ln -sf /data/${app}/data ${dataDir}/data

      ## copied to below chown -Rf ${app}:${app} /data/${app}/

      if [[ ! -f ${appDir}/html/data/${envCfg.environment}log/import/Manual.xml ]];
      then
      mkdir -p ${appDir}/html/data/${envCfg.environment}log/import
      echo "" > ${appDir}/html/data/${envCfg.environment}log/import/Manual.xml
      fi

      ln -sf /data/${app}/log ${dataDir}/alltrack-cust-medipoint-voorraad
      chmod 0775 ${appDir}/html/alltrack-cust-medipoint-voorraad/log

      sleep 5

      find ${appDir} -not -user ${app} -exec chown -Rf ${app}:${app} {} \;
      find /data/${app} -not -user ${app} -exec chown -Rf ${app}:${app} {} \;
      systemctl restart phpfpm-${app}.service
      fi

      '';
	};


      #	systemd.services."process-${envCfg.environment}-xml-queued-messages-${app}" = {
      #		description = "${envCfg.environment} XML queues messages processor";
      #		after = [ "network.target" ];
      #		startLimitBurst = 5;
      #		startLimitIntervalSec = 10;
      #
      #		serviceConfig = {
      #			Type = "simple";
      #			WorkingDirectory = "${dataDir}";
      #			StandardOutput = "journal";
      #			StandardError = "journal";
      #			ExecStart = "${pkgs.${php_version}}/bin/php index.php cron process-xml-queued-messages";
      #			Restart = "always";
      #			RestartSec = 3;
      #			User = "${app}";
      #			Group = "${app}";
      #		};
      #
      #		wantedBy = [ "multi-user.target" ];
      #	};
    };
  }) instances);
}
