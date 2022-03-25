#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

; https://www.autohotkey.com/boards/viewtopic.php?p=410634#p410634
SetCapsLockState Off

WaitingForCtrlInput := false
SentCtrlDownWithKey := false

*CapsLock::
	key := 
	WaitingForCtrlInput := true
	Input, key, B C L1 T1, {Esc}
	WaitingForCtrlInput := false
	if (ErrorLevel = "Max") {
		SentCtrlDownWithKey := true
		Send {Ctrl Down}%key%
	}
	KeyWait, CapsLock
	Return

*CapsLock up::
	If (SentCtrlDownWithKey) {
		Send {Ctrl Up}
		SentCtrlDownWithKey := false
	} else {
		if (A_TimeSincePriorHotkey < 1000) {
			if (WaitingForCtrlInput) {
				Send, {Esc 2}
			} else {
				Send, {Esc}
			}
		}
	}
	Return

