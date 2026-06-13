{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      environment.systemPackages = with pkgs;
        [
          asdf-vm
          awscli2
          bat
          broot
          difftastic
          dust
          eza
          fd
          ffmpeg
          fzf
          git
          hishtory
          just
          kanata
          kitty
          maccy
          mergiraf
          neovide
          neovim
          nodejs    # Tools installed by Mason in Neovim (biome, etc.)
          ripgrep
          rustup
          tmux
          yt-dlp
          zoxide
          # insuk-www
          imagemagick
          rclone
                        # ignite
              ccache
              cmake
              git
              gst_all_1.gstreamer
              gst_all_1.gstreamer.dev
              jq
              just
              ninja
              nodejs_22
              pkg-config
              python312Full
              #rustToolchain
              zsh
              SDL2
              SDL2_image
              SDL2_mixer.dev
              SDL2_ttf
              a52dec
              gettext
              glib.dev
              gst_all_1.gst-plugins-base
              gst_all_1.gst-plugins-base.dev
              gst_all_1.gst-plugins-good.dev
              libjpeg8
              libpng
              openssl

   #- gstreamer-1.0
   #- gstreamer-plugins-base-1.0
   #- glib-2.0
        ];

      fonts.packages = [ pkgs.jetbrains-mono ];

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";

      # Determinate uses its own daemon to manage the Nix installation that
      # conflicts with nix-darwin’s native Nix management.
      nix.enable = false;

      # https://nixcademy.com/posts/nix-on-macos/#unlocking-sudo-via-fingerprint
      # This option has been renamed to `security.pam.services.sudo_local.touchIdAuth` for consistency with NixOS.
      security.pam.services.sudo_local.touchIdAuth = true;

      # https://nixcademy.com/posts/nix-on-macos/#setting-system-defaults
      system.defaults = {
        dock.appswitcher-all-displays = true;
        dock.autohide = true;
        dock.mru-spaces = false;
        finder.AppleShowAllExtensions = true;
        finder.FXPreferredViewStyle = "clmv";
        screensaver.askForPasswordDelay = 10;
      };
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    darwinConfigurations."simple" = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
