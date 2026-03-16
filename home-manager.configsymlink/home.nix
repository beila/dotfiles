{ config, pkgs, ... }:

let
  local = import ./local.nix;
in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.

  # I like https://github.com/cwndrws/dotfiles/blob/master/home.nix#L10 for simplicity
  home.username = local.username;
  home.homeDirectory = local.homeDirectory;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

        pkgs.albert
        pkgs.bat
        pkgs.brightnessctl
        pkgs.xfce.xfce4-power-manager
        pkgs.xfce.xfce4-cpugraph-plugin
        pkgs.xfce.xfce4-genmon-plugin
        pkgs.cmake
        pkgs.dzen2  # lightweight OSD popups for audio/device switching
        pkgs.difftastic
        pkgs.fd
        pkgs.ffmpeg
        pkgs.fzf
        pkgs.git
        (config.lib.nixGL.wrap pkgs.ghostty)
        pkgs.hishtory
        pkgs.jetbrains-mono # For OSD popups
        pkgs.nerd-fonts.jetbrains-mono  # For OSD popups
        pkgs.jujutsu
        pkgs.just
        pkgs.keyd
        pkgs.mergiraf
        pkgs.pavucontrol
        pkgs.piper-tts
        pkgs.plocate
        pkgs.ripgrep
        pkgs.scrot
        pkgs.uv  # edge-tts runner for say-ko
        pkgs.alsa-utils  # aplay for say/say-ko
        pkgs.wl-clipboard
        pkgs.xclip
        pkgs.xournalpp
        pkgs.zellij
        pkgs.zoxide
        pkgs.zsh

        pkgs.awscli2

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "albert"
    ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/hojin/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Sync all repos every 10 minutes (with random delay to avoid clashing across machines)
  # Uses flock in sync_all to prevent concurrent runs
  # Low priority (nice 19, idle IO) to not interfere with interactive work
  # No Persistent=true — avoids running immediately on home-manager switch
  systemd.user.services.sync-repos = {
    Unit.Description = "Sync dotfiles and docs repos";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.dotfiles/script/sync_all";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };
  systemd.user.timers.sync-repos = {
    Unit.Description = "Sync dotfiles and docs repos every 10 minutes";
    Timer = {
      OnCalendar = "*:0/10";
      RandomizedDelaySec = "9m";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Update plocate database every 3 minutes (user home only)
  # Used by Albert for file search and jj_snapshot_all for repo discovery
  # Notifies via desktop notification if update takes >10s
  systemd.user.services.updatedb = {
    Unit.Description = "Update plocate database";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.dotfiles/script/updatedb";
    };
  };
  systemd.user.timers.updatedb = {
    Unit.Description = "Update plocate database every 3 minutes";
    Timer = {
      OnCalendar = "*:0/3";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  targets.genericLinux.enable = true;
}
