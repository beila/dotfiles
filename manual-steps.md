### Vivaldi Kerberos
https://forum.vivaldi.net/topic/30893/how-to-manage-policies-on-vivaldi-kerberos-sso

### WSL

#### at startup

```
cmd.exe /C $(wslpath -w "$(realpath ~/home/dotfiles/AutoHotkey.ahk)") &&
  sudo /etc/init.d/screen-cleanup start
  && exec zsh
```

#### after connecting to VPN

```
sudo cp ~/resolv.header.conf /etc/resolv.conf && ipconfig.exe /all |
  grep "DNS Servers.*:.*\." |
  awk '{print "nameserver " $NF}' |
  tr -d '\r' |
  sudo tee --append /etc/resolv.conf
```
