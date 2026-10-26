#Requires AutoHotkey v1.1.37+
#NoEnv
#NoTrayIcon
#Persistent
#SingleInstance, Off
SetBatchLines, -1
mode := A_Args[1], ready := A_Args[2]
if (mode = "lock") {
    if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
        ExitApp, 1
    FileAppend, ready, % ready
    return
}
if (mode = "delayed") {
    OnMessage(0x305, "SlowRender") ; WM_RENDERFORMAT
    DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
    DllCall("EmptyClipboard")
    format := DllCall("RegisterClipboardFormat", "Str", "Clipjump.SlowFixture", "UInt")
    DllCall("SetClipboardData", "UInt", format, "Ptr", 0)
    DllCall("CloseClipboard")
    FileAppend, ready, % ready
    return
}
ExitApp, 2

SlowRender() {
    Sleep, 10000
    return 0
}
