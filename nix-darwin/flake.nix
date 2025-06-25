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
      # $ nix-env -qaP | grep wget
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
          jetbrains-mono    #  왜 neovide에서 못 찾지?
          just
          kitty
          maccy
          neovide
          neovim
          nodejs    # Tools installed by Mason in Neovim (biome, etc.)
          ripgrep
          rustup
          yt-dlp
          zoxide
          # insuk-www
          imagemagick
          rclone
        ];

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
