{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [

    vim
    jq
    gum
    tmux
    zsh
    sudo

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

    minica
    lego
    acme
  ];
}
