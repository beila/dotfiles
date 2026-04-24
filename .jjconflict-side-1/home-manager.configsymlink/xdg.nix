{ config, ... }:
{
  xdg.desktopEntries.firefox-container = {
    name = "Firefox Container";
    comment = "Open external links in a firefox container";
    exec = "${config.home.homeDirectory}/.dotfiles/firefox/firefox-container %u";
    type = "Application";
    noDisplay = true;
    mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "firefox-container.desktop";
      "application/xhtml+xml" = "firefox-container.desktop";
      "x-scheme-handler/http" = "firefox-container.desktop";
      "x-scheme-handler/https" = "firefox-container.desktop";
      "x-scheme-handler/chrome" = "firefox-container.desktop";
    };
  };
}
