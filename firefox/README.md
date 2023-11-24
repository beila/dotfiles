https://wiki.debian.org/DefaultWebBrowser#Default_for_foreign_programs_.28user-specific.29

Some applications use xdg-open (part of xdg-utils). xdg-settings can be used to both get and change the default browser. Local settings can also be found in the users' home in ~/.config/mimeapps.list.

```
$ xdg-settings get default-web-browser
chromium.desktop

$ xdg-settings set default-web-browser firefox-esr.desktop
```

Also, you should change mimeapps.list since some applications don't follow x-www-browser:

```
$ cat ~/.config/mimeapps.list
[Default Applications]
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop

[Added Associations]
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop
```
