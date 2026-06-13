# Bare-username aliases for home-manager auto-detection.
#
# Why: when invoked as `home-manager switch --flake .` (no `#user@host`
# suffix), home-manager tries bare `$USER` keys first. Our `hosts/*.nix`
# entries are keyed by `user@<static-hostname>` (so the same user across
# different machines doesn't collide), so the bare key would otherwise
# never match.
#
# Fix: at eval time, read /etc/hostname (FQDN and short form), find every
# `user@<live-host>` entry in allHosts, and expose it under bare `user`.
# Returns an attrset to merge into homeConfigurations.
#
# Pure eval safety: if /etc/hostname is unreadable, hostname is "" and
# nothing matches — the alias map comes out empty.

{ allHosts }:

let
  hostnameRaw =
    if builtins.pathExists /etc/hostname
    then builtins.readFile /etc/hostname
    else "";
  hostname =
    let m = builtins.match "([^\n]*)\n?.*" hostnameRaw;
    in if m == null then "" else builtins.head m;
  shortHostname =
    let m = builtins.match "([^.]*).*" hostname;
    in if m == null then hostname else builtins.head m;

  # builtins.split returns [pre sep-list1 mid sep-list2 post …]; for "u@h"
  # the bits we want sit at indices 0 (user) and 2 (host).
  splitAt = key:
    let
      parts = builtins.split "@" key;
      user = if builtins.length parts >= 1 then builtins.head parts else "";
      host = if builtins.length parts >= 3 then builtins.elemAt parts 2 else "";
    in { inherit user host; };

  matches = key:
    let p = splitAt key;
    in p.host != "" && (p.host == hostname || p.host == shortHostname);

  toEntry = key:
    let p = splitAt key;
    in { name = p.user; value = allHosts.${key}; };
in
  builtins.listToAttrs (map toEntry (builtins.filter matches (builtins.attrNames allHosts)))
