# Cross-backend scheduler for periodic jobs.
#
# Why: cloud-desktop AL2 (electra) doesn't run a per-user systemd instance —
# its system systemd is too old, and switching the host to cgroup v2 (which
# nix's systemd >=256 needs) requires a kernel cmdline change + reboot. Cron
# is available everywhere AL2 is. This module lets a host pick the backend
# without changing the job definitions.
#
# Usage:
#   dotfiles.schedule.backend = "systemd" | "cron";    # per-host, default systemd
#   dotfiles.schedule.environment = { LOG_ROOT = "..."; };  # cron-mode top-level env
#   dotfiles.schedule.pathExtra   = [ "/some/dir" ];        # prepended to PATH in cron header
#   dotfiles.schedule.jobs.<name> = {
#     description = "...";
#     command     = "%h/.dotfiles/script/foo";  # %h expands to the user's home dir
#     schedule    = { systemd = "*:0/10"; cron = "*/10 * * * *"; };
#     # optional:
#     nice               = 19;
#     ioSchedulingClass  = "idle";
#     randomizedDelaySec = 7200;   # native under systemd; emitted as `sleep $((RANDOM % N))` prefix under cron
#     persistent         = true;   # native under systemd; cron has no equivalent (best-effort no-op)
#     env                = { FOO = "bar"; };  # per-job env (cron: prefixed via /usr/bin/env on the command line)
#   };
{ config, lib, pkgs, ... }:
let
  cfg = config.dotfiles.schedule;

  jobType = lib.types.submodule ({ ... }: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to schedule this job. Set to false to declare a job in shared modules but skip it on a specific host (e.g. battery-notify on a desktop with no battery).";
      };
      description = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable description.";
      };
      command = lib.mkOption {
        type = lib.types.str;
        description = "Command to run. May contain %h (expanded to home dir) for portability.";
      };
      schedule = {
        systemd = lib.mkOption {
          type = lib.types.str;
          description = "OnCalendar value for the systemd backend.";
        };
        cron = lib.mkOption {
          type = lib.types.str;
          description = "5-field cron schedule for the cron backend.";
        };
      };
      nice = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      ioSchedulingClass = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Random delay before execution. Native under systemd; emitted as `sleep $((RANDOM % N))` under cron.";
      };
      persistent = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run missed jobs after wake. Native under systemd; no-op under cron.";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Per-job environment variables.";
      };
    };
  });

  # %h handling for the cron path: cron has no token like %h, so we expand at
  # eval time using the home directory we're configured for.
  expandHome = s: lib.replaceStrings [ "%h" ] [ config.home.homeDirectory ] s;

  # Drop jobs explicitly disabled (e.g. battery-notify on a battery-less host).
  enabledJobs = lib.filterAttrs (_: job: job.enable) cfg.jobs;

  # Render a single cron entry from a job spec.
  renderCronLine = name: job:
    let
      nicePrefix =
        let parts = lib.optional (job.nice != null) "-n ${toString job.nice}"
                  ++ lib.optional (job.ioSchedulingClass != null) "-c ${
                       {
                         "none"        = "0";
                         "realtime"    = "1";
                         "best-effort" = "2";
                         "idle"        = "3";
                       }.${job.ioSchedulingClass} or job.ioSchedulingClass
                     }";
        in
          if parts == [] then ""
          else "ionice ${lib.concatStringsSep " " parts} ";

      delayPrefix =
        if job.randomizedDelaySec != null && job.randomizedDelaySec > 0
        then "sleep $((RANDOM \\% ${toString job.randomizedDelaySec})) && "
        else "";

      envPrefix =
        if job.env == { } then ""
        else
          let kv = lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") job.env;
          in "/usr/bin/env ${lib.concatStringsSep " " kv} ";

      # Wrap the whole thing in `bash -lc '...'` so RANDOM / && / sleep are
      # interpreted by bash even when cron's default shell is /bin/sh.
      bodyRaw = "${delayPrefix}${nicePrefix}${envPrefix}${expandHome job.command}";
      needsShell = job.randomizedDelaySec != null && job.randomizedDelaySec > 0;
      body = if needsShell
             then "/bin/bash -c ${lib.escapeShellArg bodyRaw}"
             else bodyRaw;

      comment = "# ${name}: ${job.description}";
    in
      "${job.schedule.cron}  ${body}  ${comment}";

  envHeader =
    let
      pathLine =
        if cfg.pathExtra == [] then ""
        else "PATH=${lib.concatStringsSep ":" (cfg.pathExtra ++ [ "/usr/bin" "/bin" ])}\n";
      envLines = lib.concatMapStrings (k: "${k}=${cfg.environment.${k}}\n")
                   (lib.attrNames cfg.environment);
    in
      "MAILTO=\"\"\n" + pathLine + envLines;

  beginMarker = "# >>> home-manager managed (dotfiles.schedule) >>>";
  endMarker   = "# <<< home-manager managed (dotfiles.schedule) <<<";

  crontabBlock =
    let
      lines = lib.mapAttrsToList renderCronLine enabledJobs;
    in
      lib.concatStringsSep "\n" (
        [ beginMarker
          "# Generated by ~/.dotfiles/home-manager.configsymlink/schedule.nix — do not hand-edit inside this block."
          envHeader
        ]
        ++ lines
        ++ [ endMarker ""]
      );

  crontabFile = pkgs.writeText "dotfiles-schedule.cron" crontabBlock;
in
{
  options.dotfiles.schedule = {
    backend = lib.mkOption {
      type = lib.types.enum [ "systemd" "cron" ];
      default = "systemd";
      description = "Which scheduler to drive. 'cron' is the fallback for hosts where a per-user systemd instance isn't available.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Top-level environment variables to inject. Cron mode emits them in the crontab header; systemd mode ignores them (use environment.d / systemd Environment= for that backend).";
    };

    pathExtra = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Directories prepended to PATH in cron mode. systemd mode ignores it.";
    };

    jobs = lib.mkOption {
      type = lib.types.attrsOf jobType;
      default = { };
    };
  };

  config = lib.mkMerge [
    # ----- defaults --------------------------------------------------------
    {
      # Cron's default PATH is /usr/bin:/bin — too narrow for our scripts,
      # which call nix-installed tools (jj, plocate, claude, kiro-cli) and
      # user-local helpers. /nix/var/nix/profiles/default/bin is where the
      # multi-user nix daemon installs `nix` itself; without it scripts that
      # shell out to nix (e.g. flake-update) fail with "nix not found on PATH".
      # Use mkDefault so a host can override if it has an unusual layout.
      dotfiles.schedule.pathExtra = lib.mkDefault [
        "${config.home.homeDirectory}/.nix-profile/bin"
        "/nix/var/nix/profiles/default/bin"
        "${config.home.homeDirectory}/.local/bin"
        "/run/current-system/sw/bin"
        "/usr/local/bin"
      ];
    }

    # ----- systemd backend -------------------------------------------------
    (lib.mkIf (cfg.backend == "systemd") {
      systemd.user.services = lib.mapAttrs (_: job: {
        Unit.Description = job.description;
        Service =
          { Type = "oneshot"; ExecStart = expandHome job.command; }
          // (lib.optionalAttrs (job.nice != null) { Nice = job.nice; })
          // (lib.optionalAttrs (job.ioSchedulingClass != null) { IOSchedulingClass = job.ioSchedulingClass; })
          // (lib.optionalAttrs (job.env != { }) {
               Environment = lib.mapAttrsToList (k: v: "${k}=${v}") job.env;
             });
      }) enabledJobs;

      systemd.user.timers = lib.mapAttrs (_: job: {
        Unit.Description = "${job.description} (timer)";
        Timer =
          { OnCalendar = job.schedule.systemd; }
          // (lib.optionalAttrs (job.randomizedDelaySec != null) {
               RandomizedDelaySec = "${toString job.randomizedDelaySec}s";
             })
          // (lib.optionalAttrs job.persistent { Persistent = true; });
        Install.WantedBy = [ "timers.target" ];
      }) enabledJobs;
    })

    # ----- cron backend ----------------------------------------------------
    (lib.mkIf (cfg.backend == "cron") {
      home.activation.dotfilesScheduleCrontab = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Home-manager activation runs with a minimal PATH (nix store only).
        # crontab(1) is a system tool, almost always under /usr/bin or
        # /usr/sbin. Prepend both so install-crontab.sh finds the binary.
        export PATH="/usr/bin:/usr/sbin:$PATH"
        $DRY_RUN_CMD ${pkgs.bash}/bin/bash ${./install-crontab.sh} \
          ${lib.escapeShellArg beginMarker} \
          ${lib.escapeShellArg endMarker} \
          ${crontabFile}
      '';
    })
  ];
}
