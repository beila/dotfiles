{
  description = "GCC 4.8 shell for the IgnitionX Linux gcc-4.8 CI configuration";

  # nixos-24.05 is the last release that has gcc48 in the binary cache.
  # Its glibc 2.39 and GStreamer 1.24 also match the Ubuntu 24.04 CI image.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      gcc48 = pkgs.gcc48;
      gcc48Stdenv = pkgs.overrideCC pkgs.stdenv gcc48;

      # The repository toolchain file forces /usr/bin/g++-4.8 into the cache.
      # A -D override cannot replace it, so this copy uses the Nix compiler paths.
      # Keep the other settings equal to portingplatforms/linux/cmake/gcc-4.8-toolchain.cmake.
      toolchainFile = pkgs.writeText "gcc-4.8-toolchain.cmake" ''
        set(CMAKE_SYSTEM_NAME Linux)
        set(CMAKE_SYSTEM_PROCESSOR ''${CMAKE_HOST_SYSTEM_PROCESSOR})

        set(CMAKE_CXX_COMPILER "${gcc48}/bin/g++" CACHE FILEPATH "The C++ compiler location" FORCE)
        set(CMAKE_C_COMPILER "${gcc48}/bin/gcc" CACHE FILEPATH "The C compiler location" FORCE)

        set(CMAKE_FIND_ROOT_PATH "/")
      '';

      # CMake looks for gmake before make. Without this link it finds the host /usr/bin/gmake.
      versionedNames = pkgs.runCommand "gcc-4.8-versioned-names" { } ''
        mkdir -p $out/bin
        ln -s ${gcc48}/bin/gcc $out/bin/gcc-4.8
        ln -s ${gcc48}/bin/g++ $out/bin/g++-4.8
        ln -s ${pkgs.gnumake}/bin/make $out/bin/gmake
      '';

      gst = pkgs.gst_all_1;
    in
    {
      devShells.${system}.default = (pkgs.mkShell.override { stdenv = gcc48Stdenv; }) {
        # The CI compiler does not add Nix hardening flags.
        hardeningDisable = [ "all" ];

        nativeBuildInputs = with pkgs; [
          cmake
          gnumake
          ninja
          pkg-config
          python3
          versionedNames
        ];

        # Without zlib here, pkg-config finds the host /usr/lib64/libz.so.
        buildInputs = with pkgs; [
          zlib
          SDL2
          libGL
          mesa
          xorg.libX11
          glib
          gst.gstreamer
          gst.gst-plugins-base
          gst.gst-plugins-bad
          alsa-lib
          libpulseaudio
          openssl
          curl
          libjpeg
          libpng
          ffmpeg
        ];

        # ignition_find_package calls pkg-config with --define-variable=prefix=//usr.
        # On Ubuntu this has no effect. Nix .pc files that use ${libdir} in Cflags then point
        # into the host /usr/lib, so add those include directories directly.
        NIX_CFLAGS_COMPILE = toString [
          "-isystem ${pkgs.glib.out}/lib/glib-2.0/include"
          "-isystem ${gst.gst-plugins-base.out}/lib/gstreamer-1.0/include"
        ];

        IGNX_GCC48_TOOLCHAIN_FILE = toolchainFile;
      };
    };
}
