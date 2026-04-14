{
  description = "Home Manager configuration of hojin";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl.url = "github:nix-community/nixGL";
    private = {
      url = "git+file:../private-dotfiles";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, home-manager, nixgl, private, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      local =
        if builtins.pathExists ./local.nix then import ./local.nix
        else builtins.throw "local.nix not found. Copy local-template.nix to local.nix and fill in your values.";
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
          ++ nixFilesFrom private;
      };
    };
}
