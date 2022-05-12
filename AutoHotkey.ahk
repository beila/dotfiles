#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

; https://gist.github.com/volks73/1e889e01ad0a736159a5d56268a300a8
;*CapsLock::
;    Send {Blind}{Ctrl Down}
;    cDown := A_TickCount
;Return
;*CapsLock up::
;    If ((A_TickCount-cDown)<100)  ; Modify press time as needed (milliseconds)
;        Send {Blind}{Ctrl Up}{Esc}
;    Else
;        Send {Blind}{Ctrl Up}
;Return

*CapsLock::
    Send {Blind}{Ctrl Down}
Return
*CapsLock up::
    If (A_PriorKey = "CapsLock")  ; When no other key is pressed
        Send {Blind}{Ctrl Up}{Esc}
    Else
        Send {Blind}{Ctrl Up}
Return

;*'::
;    Send {Blind}{Ctrl Down}
;Return
;*' up::
;    If (A_PriorKey = "'")  ; When no other key is pressed
;        Send {Blind}{Ctrl Up}{'}
;    Else
;        Send {Blind}{Ctrl Up}
;Return

;backslashDownTickCount := 0
;*\::
;    If (backslashDownTickCount = 0)
;		backslashDownTickCount := A_TickCount
;Return
;*\ up::
;    If ((A_TickCount-backslashDownTickCount)<300)
;        Send {Blind}{Tab}
;    Else
;        Send {Blind}{\}
;	backslashDownTickCount := 0
;Return

; https://www.autohotkey.com/board/topic/104173-capslock-to-control-and-escape/?p=669777
;CapsLock::
;   key=
;   Input, key, B C L1 T1, {Esc}
;   if (ErrorLevel = "Max")
;       Send {Ctrl Down}%key%
;   KeyWait, CapsLock
;   Return
;CapsLock up::
;   If key
;       Send {Ctrl Up}
;   else
;       If (A_TimeSincePriorHotkey < 1000)
;           Send, {Esc 2}
;   Return

; https://gist.github.com/mistic100/d3c0c1eb63fb7e4ee545
PrintScreen::Send {Media_Prev}
ScrollLock::Send {Media_Play_Pause}
Pause::Send {Media_Next}
#F10::Send {Volume_Mute}
#F11::Send {Volume_Down}
#F12::Send {Volume_Up}
+PrintScreen::Send {Volume_Mute}
+ScrollLock::Send {Volume_Down}
+Pause::Send {Volume_Up}

; Activate/deactivate the first app in the task bar (ex. Windows Terminal)
; But this disabled #F12
;F12::Send {LWin down}{1}{LWin up}
F12::
	if WinActive("ahk_exe WindowsTerminal.exe")
		WinMinimize
	else
		WinActivate, ahk_exe WindowsTerminal.exe
return

;LCtrl & Tab::AltTab
;LCtrl & =::ShiftAltTab

; Rearrange modifier keys for Kinesis Advantage 2
LCtrl::LAlt
LAlt::LCtrl
RWin::RCtrl
RCtrl::RAlt
*End::
  SetKeyDelay -1
  Send {Blind}{LWin Down}
return
*End up::
  SetKeyDelay -1
  Send {Blind}{LWin Up}
return
*PgDn::
  SetKeyDelay -1
  Send {Blind}{RWin Down}
return
*PgDn up::
  SetKeyDelay -1
  Send {Blind}{RWin Up}
return

