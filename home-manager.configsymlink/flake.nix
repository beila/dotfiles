{
  description = "Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl.url = "github:nix-community/nixGL";
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
      nixFilesFrom = dir:
        if builtins.pathExists dir then
          builtins.filter (f: f != null)
            (map (name: if builtins.match ".*\\.nix" name != null then dir + "/${name}" else null)
              (builtins.attrNames (builtins.readDir dir)))
        else [];
      hostsDir = private + "/hosts";
      mkHost = extraModules: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = extraModules
          ++ [ ./home.nix ./neovide.nix ./nvim.nix ./xdg.nix ./xmonad.nix
               { targets.genericLinux.nixGL.packages = nixgl.packages; } ]
          ++ (if builtins.pathExists /usr/bin/dconf then [ ./gnome.nix ] else [])
          ++ nixFilesFrom private;
      };
    in
    {
      homeConfigurations = builtins.foldl' (a: b: a // b) {}
        (map (f: import f { inherit mkHost; }) (nixFilesFrom hostsDir));
    };
}
