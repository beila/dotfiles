{
  description = "Home Manager configuration of hojin";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
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
      privateDir = ./. + "/../private-dotfiles";
      nixFilesFrom = dir:
        if builtins.pathExists dir then
          builtins.filter (f: f != null)
            (map (name: if builtins.match ".*\\.nix" name != null then dir + "/${name}" else null)
              (builtins.attrNames (builtins.readDir dir)))
        else [];
    in
    {
      homeConfigurations."hojin" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = [
          ./home.nix
          ./neovide.nix
          ./nvim.nix
          ./xdg.nix
          ./xmonad.nix
          {
            targets.genericLinux.nixGL.packages = nixgl.packages;
          }
        ] ++ (if builtins.pathExists /usr/bin/dconf then [ ./gnome.nix ] else [])
          ++ nixFilesFrom privateDir;
      };
    };
}
