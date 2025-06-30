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

  users.users.userzero = {
    shell = pkgs.zsh;
    isNormalUser = true;
    extraGroups = [ "wheel"];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQChpc+m1+NcJ7rWhdbKDb489Jziv5751p198MQsxfjiOu4Bwj5VFgq/z8D5EbLe6X6azU+FkPG1TJqxzRMYzVd/DBA/nfVryekQ2e96C9/uMLkotJ4hMWUbCXuJ2hU93ncooh+6yCSMTZUYcQWymRhKfHeh5ES0T5cuyw+WJDIp7U27QC1yf8TkB1qmrZOjrnx2u9cEKcelvxPAWzmT0eJQ/eemSLl2zPY8fYnAy25jVqlKEVfP0Qt3uaud7GcZC41hG19WXYqa+LzO2nkzHF7GtwVQuumD20jryq/BpY4moQyMotH3dkurSBkrfI62K53V83CL1MlyAnxX6Ku51m/S5XeKTGayilXDOZ60mScK3e9T7cY67yBgTVpz6cVLkvGpHevA9bWt38aebdGMdwV9JrUFQJvL8bO/l4gOx2y9mqT4Kt5t5IfINZAUIctSfpOTN22mfhv85cTBS+JuyR42y0ZwLg9cFz/SkEPH3FZk/rQHayvqzlBh6SdcU2J5UoU= pim@ojs"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDXou85inL0/UMBGw2VNi+CCQcSKzH7VAihPwcSl8Icb"
    ];
  };


  security.sudo.wheelNeedsPassword = false;
}
