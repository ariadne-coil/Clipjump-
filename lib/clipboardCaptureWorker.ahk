#Requires AutoHotkey v1.1.37+
#NoEnv
#NoTrayIcon
#SingleInstance, Off
#ClipboardTimeout 250
SetBatchLines, -1
FileEncoding, UTF-8-RAW

; This worker only reads the live clipboard. A parent deadline covers calls
; blocked inside GetClipboardData / a third-party delayed renderer.
if (A_Args.Length() != 2)
    ExitApp, 2
prefix := A_Args[1], sequence := A_Args[2] + 0
captured := false
Loop, 5 {
    if CJ_ReadClipboard(snapshot, text, sequence, prefix) {
        captured := true
        break
    }
    if (CJ_ClipboardSequence() != sequence)
        break
    Sleep, 50
}
if !captured {
    FileAppend, capture-failed, % prefix ".error"
    ExitApp, 1
}
if !CJ_WriteSnapshot(prefix ".avc", snapshot) {
    FileAppend, write-failed, % prefix ".error"
    ExitApp, 1
}
file := FileOpen(prefix ".txt", "w", "UTF-8-RAW")
if !IsObject(file) {
    FileAppend, text-write-failed, % prefix ".error"
    ExitApp, 1
}
file.Write(text)
file.Close()
if (CJ_ClipboardSequence() != sequence) {
    FileAppend, sequence-changed, % prefix ".error"
    ExitApp, 1
}
FileAppend, % sequence, % prefix ".ready"
ExitApp, 0

#Include %A_ScriptDir%\clipboardIO.ahk
