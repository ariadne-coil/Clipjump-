#Requires AutoHotkey v2.0.31+
; Include in a v2 script: cj := Clipjump(), MsgBox(cj.getVar("version"))
class Clipjump {
    __New(hwnd := 0, timeout := 2000) {
        this.DefineProp("Target", {Value: hwnd})
        this.DefineProp("Timeout", {Value: timeout})
    }
    __Call(method, parameters) => this.Call(method, parameters*)
    __Get(name, parameters) => this.Call("getvar", name)
    __Set(name, parameters, value) => this.Call("setvar", name, value)
    Call(method, parameters*) {
        hidden := A_DetectHiddenWindows, mode := A_TitleMatchMode
        try {
            DetectHiddenWindows(true), SetTitleMatchMode(2)
            target := this.Target || WinExist("Clipjump.ahk ahk_class AutoHotkey")
            if !target
                throw Error("Clipjump v2 is not running.")
            token := Format("{:08x}{:08x}", Random(0, 0x7FFFFFFF), Random(0, 0x7FFFFFFF))
            path := A_Temp "\ClipjumpV2-" DllCall("GetCurrentProcessId") "-" token ".txt"
            message := "CJ2:" token "`r" method
            for parameter in parameters {
                encoded := StrReplace(String(parameter), "\", "\\")
                encoded := StrReplace(encoded, "`r", "\r")
                message .= "`r" StrReplace(encoded, "`n", "\n")
            }
            if StrLen(message) > 524287
                throw Error("API request is too large.")
            packet := Buffer(3 * A_PtrSize, 0)
            NumPut("UInt", (StrLen(message) + 1) * 2, packet, A_PtrSize)
            NumPut("Ptr", StrPtr(message), packet, 2 * A_PtrSize)
            result := 0
            delivered := DllCall("SendMessageTimeoutW", "Ptr", target, "UInt", 0x4A, "Ptr", A_ScriptHwnd, "Ptr", packet, "UInt", 2, "UInt", this.Timeout, "Ptr*", &result, "Ptr")
            if !delivered || !result || !FileExist(path)
                throw Error("Clipjump API did not respond before the deadline.")
            response := FileRead(path, "UTF-8")
            if SubStr(response, 1, 3) != "OK`n"
                throw Error(SubStr(response, 7))
            return SubStr(response, 4)
        } finally {
            DetectHiddenWindows(hidden), SetTitleMatchMode(mode)
            if IsSet(path) && FileExist(path)
                FileDelete(path)
        }
    }
}
