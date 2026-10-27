#Requires AutoHotkey v2.0.31+
#NoTrayIcon
#Include ..\..\publicAPI.ahk
try {
    cj := Clipjump(Integer(A_Args[1]))
    if cj.getVar("version") != "13.0.0-beta.2"
        throw Error("Version response mismatch")
    if cj.getClipAt(0, 1) != "API`r`nline\tail"
        throw Error("Multiline API response mismatch")
    if cj.runPlugin("upper", "escaped`r`nline\tail") != "ESCAPED`r`nLINE\TAIL"
        throw Error("Escaped API parameters mismatch")
    rejected := false
    try cj.undefinedOperation()
    catch
        rejected := true
    if !rejected
        throw Error("Unknown API operation was accepted")
    FileAppend("OK", A_Args[2])
    ExitApp(0)
} catch as err {
    FileAppend(err.Message, A_Args[2])
    ExitApp(1)
}
