{ pkgs, ... }:

let
  zmx = pkgs.stdenv.mkDerivation rec {
    pname = "zmx";
    version = "0.5.0";
    src = pkgs.fetchurl {
      url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
      sha256 = "0a0clnafaq863vcgb2h42216ygm2g41vv4fbwjxcmkfwajwgdhac";
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
}
