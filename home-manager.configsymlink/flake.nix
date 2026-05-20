{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl.url = "github:nix-community/nixGL";
  };

  outputs =
    { nixpkgs, home-manager, nixgl, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Resolve private-dotfiles from the current user's $HOME at eval time so
      # flake.lock is portable across machines. `script/bootstrap` clones the
      # repo before any home-manager switch is run, so the local checkout is
      # guaranteed to exist. Requires `home-manager switch --impure`.
      #
      # When HOME is unavailable (pure eval, e.g. home-manager's "sanity check"
      # phase that runs without --impure), fall through to a sentinel path. The
      # sentinel won't exist, so hostsDir reads empty and homeConfigurations
      # comes out as an empty attrset — pure eval succeeds with no targets.
      home = builtins.getEnv "HOME";
      privateRoot =
        if home != "" && builtins.pathExists (home + "/.dotfiles/private-dotfiles")
        then /. + (home + "/.dotfiles/private-dotfiles")
        else /. + "/var/empty/private-dotfiles-not-resolved";
      nixFilesFrom = dir:
        if builtins.pathExists dir then
          builtins.filter (f: f != null)
            (map (name: if builtins.match ".*\\.nix" name != null then dir + "/${name}" else null)
              (builtins.attrNames (builtins.readDir dir)))
        else [];
      hostsDir = privateRoot + "/hosts";
      mkHost = { gnome ? false, extraModules ? [] }: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = extraModules
          ++ [ ./home.nix ./neovide.nix ./nvim.nix ./xdg.nix ./xmonad.nix ./zmx.nix
               { targets.genericLinux.nixGL.packages = nixgl.packages; } ]
          ++ (if gnome then [ ./gnome.nix ] else [])
          ++ nixFilesFrom privateRoot;
      };
      allHosts = builtins.foldl' (a: b: a // b) {}
        (map (f: import f { inherit mkHost; }) (nixFilesFrom hostsDir));

      # Lets `home-manager switch --flake .` (no `#user@host`) auto-detect
      # via bare $USER. See ./bare-aliases.nix for the matching logic.
      bareAliases = import ./bare-aliases.nix { inherit allHosts; };
    in
    {
      homeConfigurations = allHosts // bareAliases;
    };
}
