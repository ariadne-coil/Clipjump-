#Requires AutoHotkey v2.0.31+
#SingleInstance Off
#NoTrayIcon
#ClipboardTimeout 250
#Include Includes.ahk
#Include ..\..\publicAPI.ahk

checks := 0, failures := 0, hostPid := 0, job := false
temporary := A_Temp "\Clipjump-compiled-test-" CJNewId()
original := ClipboardAll(), architecture := A_PtrSize = 8 ? "x64" : "x86"
try {
    package := A_Args[1], hostRoot := temporary "\standalone"
    DirCreate(hostRoot "\runtime-v2\" architecture)
    FileCopy(package "\Clipjump.exe", hostRoot "\Clipjump.exe")
    FileCopy(package "\ClipjumpCapture.exe", hostRoot "\ClipjumpCapture.exe")
    FileCopy(package "\runtime-v2\" architecture "\sqlite3.dll", hostRoot "\runtime-v2\" architecture "\sqlite3.dll")
    Check(!FileExist(hostRoot "\Clipjump.ahk") && !FileExist(hostRoot "\runtime-v2\" architecture "\AutoHotkey.exe"), "Standalone fixture has no interpreter or source scripts")
    DetectHiddenWindows(true)
    Run('"' hostRoot '\Clipjump.exe" /ErrorStdOut=UTF-8 --data-dir "' temporary '\data"', hostRoot, "Hide", &hostPid)
    hwnd := WinWait("ahk_pid " hostPid " ahk_class AutoHotkey", , 5)
    if !hwnd
        throw Error("Compiled application did not start.")
    client := Clipjump(hwnd)
    version := WaitForAPI(client)
    Check(version = "13.0.0-beta.2", "Compiled application exposes v2 API")
    Check(Clipjump().getVar("version") = "13.0.0-beta.2", "API discovers compiled application automatically")
    snapshot := CJSnapshot.FromText("Compiled Ω 漢字 🦋 clipboard")
    payload := Buffer(8, 0)
    NumPut("UInt", 0xFF00FE00, payload), NumPut("UInt", 0x01020003, payload, 4)
    snapshot.Entries.Push({Id: DllCall("RegisterClipboardFormatW", "Str", "Adobe Illustrator AICB", "UInt"), Name: "Adobe Illustrator AICB", Data: payload})
    A_Clipboard := snapshot.Native(), sequence := CJClipboard.Sequence()
    deadline := A_TickCount + 5500
    while Integer(client.getChStrength(0)) = 0 && A_TickCount < deadline
        Sleep(25)
    Check(client.getClipAt(0, 1) = snapshot.Text, "Compiled worker captures into compiled application history")
    stored := CJSnapshot.Load(client.getClipLoc(0, 1)), restored := stored.Find("Adobe Illustrator AICB")
    Check(IsObject(restored) && restored.Size = payload.Size && !DllCall("msvcrt\memcmp", "Ptr", restored, "Ptr", payload, "UPtr", payload.Size, "Cdecl Int"), "Compiled capture preserves opaque binary formats")
    Check(CJClipboard.Sequence() = sequence, "Compiled capture leaves live clipboard unchanged")
    Check(!WinExist("ahk_class tooltips_class32 ahk_pid " hostPid), "Compiled copy capture displays no confirmation popup")
    job := CJCaptureJob(temporary "\direct-worker", "unused-interpreter.exe", hostRoot "\ClipjumpCapture.exe", 0, 3000)
    job.Queue(0), status := Poll(job)
    Check(status = "ready", "Compiled worker runs with no interpreter dependency")
    job.Cancel()
    Check(!job.ProcessHandle && !job.Pending, "Compiled worker process handles are released")
    client.action("exit")
    ProcessWaitClose(hostPid, 4)
    Check(!ProcessExist(hostPid), "Compiled application shuts down through public API")
    hostPid := 0
} catch as err {
    failures += 1
    FileAppend("FAIL " err.Message " " err.File ":" err.Line "`n" err.Stack "`n", "*")
} finally {
    if IsObject(job)
        job.Cancel()
    if hostPid && ProcessExist(hostPid)
        ProcessClose(hostPid)
    A_Clipboard := original
    ; The only recursive deletion target is this test's generated GUID directory.
    try DirDelete(temporary, true)
}
FileAppend("RESULT " checks " checks; " failures " failures; compiled ptr=" A_PtrSize "`n", "*")
ExitApp(failures ? 1 : 0)

Check(condition, name) {
    global checks, failures
    checks += 1
    if !condition
        failures += 1
    FileAppend((condition ? "PASS " : "FAIL ") name "`n", "*")
}
Poll(job) {
    deadline := A_TickCount + 4500, status := "waiting"
    while status = "waiting" && A_TickCount < deadline {
        status := job.Poll()
        Sleep(20)
    }
    return status
}
WaitForAPI(client) {
    deadline := A_TickCount + 6000
    loop {
        try return client.getVar("version")
        catch as err {
            if A_TickCount >= deadline
                throw err
            Sleep(50)
        }
    }
}
