update:
    darwin-rebuild build --flake .\#simple

init:
    nix flake init -t nix-darwin 
    nix run nix-darwin -- switch --flake .\#simple
