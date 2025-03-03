[macos]
update:
    nix flake update
    darwin-rebuild build --flake .\#simple

[macos]
switch:
    darwin-rebuild switch --flake .\#simple

[macos]
init:
    nix flake init -t nix-darwin 
    nix run nix-darwin -- switch --flake .\#simple
    rustup default stable

[macos]
install:
    curl \
      --proto '=https' \
      --tlsv1.2 \
      -sSf \
      -L https://install.determinate.systems/nix \
      | sh -s -- install
