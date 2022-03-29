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
    If ((A_TickCount-cDown)<400)  ; Modify press time as needed (milliseconds)
        Send {Blind}{Ctrl Up}{Esc}
    Else
        Send {Blind}{Ctrl Up}
Return

; https://gist.github.com/mistic100/d3c0c1eb63fb7e4ee545
ScrollLock::Send       {Media_Play_Pause}
PrintScreen::Send        {Media_Prev}
Pause::Send       {Media_Next}
;^!NumpadMult::Send  {Volume_Mute}
;F12::Send   {Volume_Up}
;F11::Send   {Volume_Down}