{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [

    vim
    jq
    gum
    tmux
    zsh
    sudo
    bat
    git
    wget
    curl

    openssl

    nfs-utils

    dnsutils
    iputils
    htop
    stress
    nettools

    postgresql
  ];
}
