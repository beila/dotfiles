{ config, pkgs, ... }:

let
  # JejuHallasan: hand-brushed display font from Jeju (SIL OFL 1.1, Google Fonts).
  # Fetched directly from google/fonts so we don't pull in the 2.3 GB google-fonts
  # mega-package just for one glyph.
  jejuhallasan-ttf = pkgs.fetchurl {
    url = "https://github.com/google/fonts/raw/main/ofl/jejuhallasan/JejuHallasan-Regular.ttf";
    sha256 = "1sa88xp6dn8p0dan80s90zr9c6d1mhfi7ibql7b7w5yp4y61klbi";
  };

  # Local Python package providing reusable OSD primitives (cairo render +
  # XShape window). battery-osd uses it; future volume/brightness/audio
  # OSD migrations will too.
  osd = pkgs.python3Packages.buildPythonPackage {
    pname = "osd";
    version = "0.1.0";
    pyproject = true;
    src = ../xwindow/osd;
    build-system = with pkgs.python3Packages; [ setuptools ];
    propagatedBuildInputs = with pkgs.python3Packages; [
      pycairo
      xlib
    ];
    doCheck = false;
  };
in
{
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
    pkgs.btop
    pkgs.xfce4-genmon-plugin
    pkgs.cmake
    pkgs.dzen2 # lightweight OSD popups for audio/device switching
    pkgs.difftastic
    pkgs.dust
    pkgs.eza # modern ls replacement; used by fzf-tab directory previews
    pkgs.fd
    pkgs.ffmpeg
    pkgs.fzf
    pkgs.gawk # `bin/logrun` requires gawk in --auto mode
    pkgs.git
    (config.lib.nixGL.wrap pkgs.ghostty)
    pkgs.ghostty.terminfo
    pkgs.glow # terminal markdown renderer
    pkgs.gnumake # `make` needed by bb
    pkgs.hishtory
    pkgs.jetbrains-mono # For OSD popups
    pkgs.nerd-fonts.jetbrains-mono # For OSD popups
    pkgs.jujutsu
    pkgs.just
    pkgs.keyd
    pkgs.lxgw-wenkai # calligraphic CJK monospace; ghostty Hangul fallback + hangul-osd font
    pkgs.mergiraf
    pkgs.nmap # raw JetDirect printer discovery (print-hp)
    pkgs.nodejs # provides node + npx (used by ad-hoc tooling)
    pkgs.ollama
    pkgs.pavucontrol
    pkgs.piper-tts
    pkgs.plocate
    pkgs.ripgrep
    pkgs.scrot
    pkgs.spacer
    pkgs.uv # edge-tts runner for say-ko
    pkgs.watchlog
    # battery-osd: invocation wrapper around the local `osd` library.
    # Single binary in PATH; no full Python (would conflict with awscli2).
    (pkgs.writers.writePython3Bin "battery-osd" {
      libraries =
        with pkgs.python3Packages;
        [
          pycairo
          xlib
        ]
        ++ [ osd ];
      flakeIgnore = [
        "E501"
        "E731"
        "W503"
      ];
    } (builtins.readFile ../xwindow/bin/battery-osd.py))
    # hangul-osd: persistent overlay while ibus's current engine is hangul.
    # Same osd-library pattern as battery-osd, plus PyGObject for the IBus
    # D-Bus signal subscription (no polling). The wrapper script sources
    # the IBus GIR typelib at runtime so PyGObject can find it.
    (pkgs.writeShellScriptBin "hangul-osd" ''
      export GI_TYPELIB_PATH="${pkgs.ibus}/lib/girepository-1.0:${pkgs.pango.out}/lib/girepository-1.0:${pkgs.harfbuzz.out}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
      # Path to JejuHallasan ttf — passed straight to fontconfig's
      # app-font set at startup so Pango sees it even though its English
      # coverage is incomplete (Pango hides such fonts from its default
      # family list).
      export HANGUL_OSD_FONT_FILE=${jejuhallasan-ttf}
      exec ${
        pkgs.writers.writePython3Bin "hangul-osd-impl" {
          libraries =
            with pkgs.python3Packages;
            [
              pycairo
              xlib
              pygobject3
            ]
            ++ [ osd ];
          flakeIgnore = [
            "E501"
            "E731"
            "W503"
          ];
        } (builtins.readFile ../xwindow/bin/hangul-osd.py)
      }/bin/hangul-osd-impl "$@"
    '')
    pkgs.alsa-utils # aplay for say/say-ko
    pkgs.wl-clipboard
    pkgs.xclip
    pkgs.xdotool # window/input automation (xmonad debugging, scripts)
    pkgs.xz # liblzma needed by zstd for ollama .tar.zst extraction
    pkgs.xournalpp
    pkgs.zellij
    pkgs.zoxide
    pkgs.zsh
    pkgs.zsh-completions
    pkgs.nix-zsh-completions
    pkgs.zsh-powerlevel10k
    pkgs.zsh-fast-syntax-highlighting
    pkgs.zsh-autosuggestions
    pkgs.zsh-fzf-tab # fzf-driven <Tab> completion; sourced from completion.zsh

    pkgs.awscli2
    pkgs.copyq # clipboard history manager (Super+V picker)

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

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "albert"
      # Reclassified as unfree by upstream nixpkgs after 2026-05-23 flake update.
      # nvim plugins where the upstream repo lists a non-OSI license (or no
      # license at all, which nixpkgs now treats as unfree). We're not
      # redistributing — local use only.
      "nvim-dap-vscode-js"
      "typescript-vim"
      "YankRing.vim"
      "vimproc.vim"
      "vim-table-mode"
      "vim-jinja"
      "vim-fubitive"
      "vim-dirdiff"
      "vim-argumentative"
    ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # ~/.terminfo must exist at process startup (ncurses checks it before any shell rc),
    # so TERMINFO_DIRS in zshenv/hm-session-vars.sh is too late for zsh's $terminfo[]
    ".terminfo".source = "${pkgs.ghostty.terminfo}/share/terminfo";
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
    # DOTFILES_ROOT — absolute path to ~/.dotfiles. Also computed in
    # zsh/zshenv.symlink (more flexibly, by resolving the zshenv symlink
    # itself), but exporting here makes it visible to systemd user units,
    # cron jobs, and anything else that doesn't source zshenv. jj fix
    # invocations and bootstrap rely on this.
    DOTFILES_ROOT = "$HOME/.dotfiles";
    # USER_HOME — placeholder for $HOME used by generalize-paths /
    # localize-paths (script/bin/). Setting it as an env var means apps
    # that interpolate env vars resolve `$USER_HOME` at runtime even
    # when the file hasn't been localized yet (e.g. fresh clone before
    # bootstrap, files outside the localize walk).
    USER_HOME = "$HOME";
    # LOGRUN_TUI_SKIPLIST — space-separated list of curses-style apps
    # whose terminal handling breaks under any stdout pipe. The
    # zz-logrun-auto.zsh widget skips these so they run untouched
    # (no logrun wrap). Membership is derived from what's actually
    # installed on this machine: TUIs declared above (nvim, btop, fzf,
    # zellij, zmx, glow) plus system-default TUIs that ship with any
    # base distro (less, more, ssh, man, top, nano, watch). Add to this
    # list when you `home.packages` a new TUI; the auto-suggestion in
    # `bin/logrun --auto` will tell you when something it saw should be
    # added.
    # See bin/AGENTS.md "Output writer / decorator".
    LOGRUN_TUI_SKIPLIST = "nvim btop fzf zellij zmx glow less more ssh man top nano watch claude kiro-cli bat";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # ---- Scheduled jobs (driven by ./schedule.nix) -----------------------
  # Each entry is backend-agnostic: schedule.nix dispatches to either
  # systemd.user.{services,timers} (taygeta) or a managed crontab block
  # (electra, cloud-desktop AL2 — see ./schedule.nix for why).

  # Sync all repos every 10 minutes (with random delay to avoid clashing across machines).
  # Uses flock in sync_all to prevent concurrent runs.
  # Low priority (nice 19, idle IO) to not interfere with interactive work.
  # No `persistent` — avoids running immediately on home-manager switch.
  dotfiles.schedule.jobs.sync-repos = {
    description = "Sync dotfiles and docs repos";
    command = "%h/.dotfiles/script/sync_all";
    schedule = {
      systemd = "*:0/10";
      cron = "*/10 * * * *";
    };
    randomizedDelaySec = 540; # 9m
    nice = 19;
    ioSchedulingClass = "idle";
  };

  # Update plocate database every 10 minutes (user home only).
  # Used by Albert for file search and sync_all for repo discovery.
  # Notifies via desktop notification if update takes >30s (threshold is in
  # the script itself). Runs every 10 minutes — frequent enough that
  # locate/plocate results stay fresh, infrequent enough to not compete
  # with interactive I/O when the system is busy.
  dotfiles.schedule.jobs.updatedb = {
    description = "Update plocate database";
    command = "%h/.dotfiles/script/updatedb";
    schedule = {
      systemd = "*:0/10";
      cron = "*/10 * * * *";
    };
  };

  # Battery low-charge OSD + notification (script tracks per-stage state).
  dotfiles.schedule.jobs.battery-notify = {
    description = "Battery low notification";
    command = "%h/.dotfiles/script/battery-notify";
    schedule = {
      systemd = "*:0/1";
      cron = "* * * * *";
    };
  };

  # Weekly flake update + dry-run home-manager build. Catches breaking
  # changes (deprecated options, schema migrations, package renames) on
  # a Sunday morning instead of the next time the user runs `home-manager
  # switch` for an unrelated reason. Never auto-switches — only signals.
  # `persistent = true` lets a suspended laptop catch up on missed Sundays;
  # under cron mode that's a best-effort no-op (cloud-desktop never
  # suspends, so no observable difference there).
  dotfiles.schedule.jobs.flake-update = {
    description = "Weekly nix flake update + home-manager build dry-run";
    command = "%h/.dotfiles/script/flake-update";
    schedule = {
      systemd = "Sun 03:00";
      cron = "0 3 * * 0";
    };
    randomizedDelaySec = 7200; # 2h
    persistent = true;
    nice = 19;
    ioSchedulingClass = "idle";
  };

  # CopyQ clipboard manager daemon (persistent history at ~/.config/copyq/).
  # Long-running graphical-session.target service — not a scheduled job, so
  # it stays a direct systemd.user.services declaration. Only relevant on
  # hosts that run a graphical session (taygeta); electra has no display.
  systemd.user.services.copyq = {
    Unit = {
      Description = "CopyQ clipboard manager";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.copyq}/bin/copyq";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  targets.genericLinux.enable = true;
}
