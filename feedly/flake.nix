{
  description = "Feedly feed scraper";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.uv pkgs.chromedriver ];
        };
        
        packages.default = pkgs.writeShellScriptBin "feedly-feeds" ''
          export PATH=${pkgs.chromedriver}/bin:$PATH
          cd ${./.}
          ${pkgs.uv}/bin/uv run ./feedly-feeds
        '';
      });
}
