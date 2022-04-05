#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

; https://gist.github.com/volks73/1e889e01ad0a736159a5d56268a300a8
*CapsLock::
    Send {Blind}{Ctrl Down}
    cDown := A_TickCount
Return
*CapsLock up::
    If ((A_TickCount-cDown)<100)  ; Modify press time as needed (milliseconds)
        Send {Blind}{Ctrl Up}{Esc}
    Else
        Send {Blind}{Ctrl Up}
Return

*'::
    Send {Blind}{Ctrl Down}
    cDown := A_TickCount
Return
*' up::
    If ((A_TickCount-cDown)<100)  ; Modify press time as needed (milliseconds)
        Send {Blind}{Ctrl Up}{'}
    Else
        Send {Blind}{Ctrl Up}
Return

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
#F12::Send {Volume_Up}
#F11::Send {Volume_Down}
+PrintScreen::Send {Volume_Mute}
+Pause::Send {Volume_Up}
+ScrollLock::Send {Volume_Down}

; Activate/deactivate the first app in the task bar (ex. Windows Terminal)
F12::Send {LWin down}{1}{LWin up}

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

