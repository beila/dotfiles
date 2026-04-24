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
ipconfig.exe /all |
  grep "DNS Servers.*:.*\." |
  awk '{print "nameserver " $NF}' |
  tr -d '\r' |
  sudo tee /etc/resolv.conf
```

##### Update Anyconnect Adapter Interface Metric for WSL2 from "Task Scheduler"

- General
  - Run with highest privileges: Check
- Triggers
  - Begin the task: On an event
    - Log: Cisco AnyConnect Secure Mobility Client
    - Source: acvpnagent
    - Event ID: 2039
- Actions
  - Action: Start a program
    - Program/script: Powershell.exe
    - Add arguments: -ExecutionPolicy Bypass -File %HOMEPATH%\dotfiles\wsl\UpdateAnyConnectInterfaceMetric.ps1
