#Requires AutoHotkey v2.0.31+
#SingleInstance Off
#NoTrayIcon
mode := A_Args[1], ready := A_Args[2]
if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
    ExitApp(1)
if mode = "delayed" {
    DllCall("EmptyClipboard")
    clipboardFormat := DllCall("RegisterClipboardFormatW", "Str", "ClipjumpTestSlowRenderer", "UInt")
    OnMessage(0x305, (*) => Sleep(10000))
    DllCall("SetClipboardData", "UInt", clipboardFormat, "Ptr", 0)
    DllCall("CloseClipboard")
}
FileAppend("ready", ready)
SetTimer(() => ExitApp(), -15000)
Persistent(true)
