{ config, lib, pkgs, ... }:

let

  cfg = config.elastinix.programs.awsUtils;

in {

  config = lib.mkIf cfg.enable {

    environment.systemPackages = with pkgs; [
      tfswitch
      awscli2
      s3fs
      aws-mfa
      ssmsh
      granted
    ];
  };

}
