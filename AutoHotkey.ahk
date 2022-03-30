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
    If ((A_TickCount-cDown)<300)  ; Modify press time as needed (milliseconds)
        Send {Blind}{Ctrl Up}{Esc}
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

*PgDn::
  SetKeyDelay -1
  Send {Blind}{Ctrl Down}{Alt Down}{Shift Down}
return

*PgDn up::
  SetKeyDelay -1
  Send {Blind}{Ctrl Up}{Alt Up}{Shift Up}
return

; https://gist.github.com/mistic100/d3c0c1eb63fb7e4ee545
ScrollLock::Send {Media_Play_Pause}
PrintScreen::Send {Media_Prev}
Pause::Send {Media_Next}
^!+F10::Send {Volume_Mute}
^!+F12::Send {Volume_Up}
^!+F11::Send {Volume_Down}