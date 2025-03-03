update:
    nix flake update
    darwin-rebuild build --flake .\#simple

build:
    darwin-rebuild switch --flake .\#simple

init:
    nix flake init -t nix-darwin 
    nix run nix-darwin -- switch --flake .\#simple
