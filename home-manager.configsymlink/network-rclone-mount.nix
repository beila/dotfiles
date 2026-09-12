{ config, lib, pkgs, ... }:

let
  cfg = config.dotfiles.networkRcloneMount;
  mountUnit = "network-rclone-mount.service";
  mountCommand = lib.concatStringsSep " " (
    map lib.escapeShellArg (
      [
        "${pkgs.rclone}/bin/rclone"
        "mount"
        cfg.remote
        cfg.mountPoint
      ]
      ++ cfg.extraArgs
    )
  );
  watchCommand = lib.concatStringsSep " " (
    map lib.escapeShellArg [
      "${../bin/network-unit-watch}"
      cfg.connectionName
      mountUnit
    ]
  );
in
{
  options.dotfiles.networkRcloneMount = {
    enable = lib.mkEnableOption "an rclone mount scoped to one NetworkManager connection";

    connectionName = lib.mkOption {
      type = lib.types.str;
      description = "Exact NetworkManager connection profile that enables the mount.";
    };

    remote = lib.mkOption {
      type = lib.types.str;
      description = "rclone remote and path to mount.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/mnt/synology";
      description = "Local mountpoint for the rclone filesystem.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments appended to rclone mount.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.connectionName != "";
        message = "dotfiles.networkRcloneMount.connectionName must not be empty";
      }
      {
        assertion = cfg.remote != "";
        message = "dotfiles.networkRcloneMount.remote must not be empty";
      }
      {
        assertion = cfg.mountPoint != "";
        message = "dotfiles.networkRcloneMount.mountPoint must not be empty";
      }
    ];

    systemd.user.services.network-rclone-mount = {
      Unit = {
        Description = "Network-scoped rclone mount";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg cfg.mountPoint}";
        ExecStart = mountCommand;
        Environment = [
          "PATH=${lib.makeBinPath [ pkgs.fuse3 pkgs.coreutils ]}:/usr/bin:/bin"
        ];
        KillSignal = "SIGINT";
        TimeoutStopSec = 20;
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    systemd.user.services.network-rclone-mount-watch = {
      Unit = {
        Description = "Start rclone mount on its configured network";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = watchCommand;
        Environment = [
          "PATH=${lib.makeBinPath [
            pkgs.coreutils
            pkgs.glib
            pkgs.networkmanager
            pkgs.systemd
          ]}"
        ];
        Restart = "always";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
