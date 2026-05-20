{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl.url = "github:nix-community/nixGL";
    # `private` is intentionally pinned to a stable upstream so flake.lock is
    # portable across machines. At evaluation time we override the input path
    # to the local $HOME/.dotfiles/private-dotfiles checkout so local edits
    # apply without pushing — no per-machine flake.lock churn.
    private = {
      url = "github:beila/private-dotfiles";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, home-manager, nixgl, private, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Resolve private-dotfiles from the current user's $HOME so the flake
      # works on any machine without rewriting flake.lock. Falls back to the
      # upstream-pinned `private` input if HOME is unset (e.g. CI/sandbox eval).
      home = builtins.getEnv "HOME";
      localPrivate = home + "/.dotfiles/private-dotfiles";
      privateRoot =
        if home != "" && builtins.pathExists localPrivate
        then /. + localPrivate
        else private;
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
    in
    {
      homeConfigurations = builtins.foldl' (a: b: a // b) {}
        (map (f: import f { inherit mkHost; }) (nixFilesFrom hostsDir));
    };
}
