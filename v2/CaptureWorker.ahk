#Requires AutoHotkey v2.0.31+
;@Ahk2Exe-SetName Clipjump Capture Worker
;@Ahk2Exe-SetDescription Isolated clipboard capture worker for Clipjump Modern
;@Ahk2Exe-SetVersion 13.0.0.3
#SingleInstance Off
#NoTrayIcon
#ClipboardTimeout 250
#Include %A_ScriptDir%\SQLite.ahk
#Include %A_ScriptDir%\Clipboard.ahk
if A_Args.Length = 2 && A_Args[1] = "--updates" {
    try {
        Download("https://api.github.com/repos/ariadne-coil/Clipjump-/releases", A_Args[2])
        ExitApp(0)
    } catch
        ExitApp(1)
}
if A_Args.Length != 2
    ExitApp(2)
prefix := A_Args[1], sequence := Integer(A_Args[2]), success := false
loop 5 {
    try {
        snapshot := CJClipboard.Capture(sequence)
        snapshot.Save(prefix ".cjc")
        if CJClipboard.Sequence() != sequence
            throw Error("stale")
        FileAppend(sequence, prefix ".ready", "UTF-8-RAW")
        success := true
        break
    } catch {
        if CJClipboard.Sequence() != sequence
            break
        Sleep(50)
    }
}
if !success
    FileAppend("capture-failed", prefix ".error", "UTF-8-RAW")
ExitApp(success ? 0 : 1)
