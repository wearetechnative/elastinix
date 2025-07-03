{config, pkgs, ... }:

{
  programs = {
    zsh = {
      enable = true;
      shellAliases = {
        tfswitch = "tfswitch -b $HOME/bin/terraform";
      };
      ohMyZsh = {
        enable = true;
        theme = "robbyrussell";
        plugins = [
          "git"
        ];
         # Global aliases
          };
    };
  };

  environment.etc = {
    "zshrc.local" = {
      text = ''
      PROMPT="%(?:%{$fg_bold[green]%}➜:%{$fg_bold[red]%}➜) %F{magenta}%n%f%{$fg[blue]%}@%M %{$fg[cyan]%}%c%{$reset_color%}"
      PROMPT+=' $(git_prompt_info)'
      ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}(%{$fg[red]%}"
      ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
      ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗"
      ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"
      '';
    };
  };

environment.homeBinInPath = true;

  users.defaultUserShell = pkgs.zsh;

  users.users.root = {
    shell = pkgs.zsh;
  };

  security.sudo.wheelNeedsPassword = false;
}
