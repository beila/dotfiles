{ pkgs, ... }:

let
  zmx = pkgs.stdenv.mkDerivation rec {
    pname = "zmx";
    version = "0.8.1";
    src = pkgs.fetchurl {
      url = "https://github.com/neurosnap/zmx/releases/download/v${version}/zmx-${version}-linux-x86_64.tar.gz";
      sha256 = "sha256-39dXILlCRm8ohwcxzIbbwHr6cvuPO9XutP9wfk7s6+g=";
    };
    sourceRoot = ".";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    installPhase = ''
      install -Dm755 zmx $out/bin/zmx
    '';
    meta = {
      description = "Session persistence for terminal processes";
      homepage = "https://github.com/neurosnap/zmx";
      license = pkgs.lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  home.packages = [ zmx ];

  # zmx keeps scrollback only in memory. Persist bounded rendered snapshots and
  # cwd metadata so the picker can restore context after a crash or forced
  # reboot.
  systemd.user.services.zmx-history = {
    Unit.Description = "Persist zmx session scrollback";
    Service = {
      ExecStart = "%h/.dotfiles/bin/zmx-history";
      Environment = [ "ZMX_BIN=${zmx}/bin/zmx" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
