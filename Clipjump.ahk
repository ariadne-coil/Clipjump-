#Requires AutoHotkey v2.0.31+
#SingleInstance Force
#ClipboardTimeout 250
#Include v2\SQLite.ahk
#Include v2\Clipboard.ahk
#Include v2\Config.ahk
#Include v2\Image.ahk
#Include v2\Store.ahk
#Include v2\Import.ahk
#Include v2\Plugins.ahk
#Include v2\UI.ahk
#Include v2\API.ahk
#Include v2\App.ahk

global CJ_UserPluginLoader := 0
#Include *i plugins-v2\User.ahk
SetWorkingDir(A_ScriptDir)
smoke := false, dataDirectory := ""
for index, argument in A_Args {
    if argument = "--smoke-test"
        smoke := true
    if argument = "--data-dir" && index < A_Args.Length
        dataDirectory := A_Args[index + 1]
}
try {
    global ClipjumpApp := CJApp(A_ScriptDir, dataDirectory)
    OnExit(ObjBindMethod(ClipjumpApp, "Shutdown"))
    if smoke {
        unchanged := ClipjumpApp.Smoke()
        ClipjumpApp.Shutdown()
        FileAppend("STARTUP_OK clipboard_unchanged=" unchanged "`n", "*")
        ExitApp(unchanged ? 0 : 1)
    }
    Persistent(true)
} catch as err {
    if smoke
        FileAppend(err.Message "`n" err.File ":" err.Line "`n" err.Stack, "**", "UTF-8")
    else
        MsgBox(err.Message "`n" err.File ":" err.Line, "Clipjump Modern — startup error", "Icon!")
    ExitApp(1)
}
