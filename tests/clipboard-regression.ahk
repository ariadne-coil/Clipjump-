#Requires AutoHotkey v1.1.37+
#NoEnv
#NoTrayIcon
#SingleInstance, Off
#ClipboardTimeout 250
SetBatchLines, -1
FileEncoding, UTF-8-RAW
SetWorkingDir, % A_ScriptDir "\.."

global failures := 0, checks := 0, job, fixturePid := 0
global savedClipboard := ClipboardAll
global testDir := A_Temp "\Clipjump-tests-" DllCall("GetCurrentProcessId")
FileCreateDir, % testDir
OnExit, Cleanup

unicode := "Clipjump " Chr(0x2713) " " Chr(0x4E2D) " " Chr(0x1F642)
html := "<html><body><!--StartFragment--><b>Clipjump</b><!--EndFragment--></body></html>"
header := "Version:0.9`r`nStartHTML:0000000105`r`nEndHTML:0000000000`r`nStartFragment:0000000000`r`nEndFragment:0000000000`r`n"
html := header html
html := StrReplace(html, "EndHTML:0000000000", "EndHTML:" Format("{:010}", StrPut(html, "UTF-8") - 1))
html := StrReplace(html, "StartFragment:0000000000", "StartFragment:" Format("{:010}", InStr(html, "<b>") - 1))
html := StrReplace(html, "EndFragment:0000000000", "EndFragment:" Format("{:010}", InStr(html, "<!--EndFragment-->") - 1))
rtf := "{\rtf1\ansi Plain \b bold\b0  \i italic\i0}"
pdf := "%PDF-1.7`nopaque-test-payload`n%%EOF"
aicb := "%!PS-Adobe-3.0`n%%Creator: Clipjump regression fixture"

Assert(TestOpenClipboard(), "open clipboard for fixture")
DllCall("EmptyClipboard")
SetFormat(13, unicode, "UTF-16")
SetFormat(DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt"), rtf)
SetFormat(DllCall("RegisterClipboardFormat", "Str", "HTML Format", "UInt"), html)
SetFormat(DllCall("RegisterClipboardFormat", "Str", "Portable Document Format", "UInt"), pdf)
SetFormat(DllCall("RegisterClipboardFormat", "Str", "Adobe Illustrator Clipboard", "UInt"), aicb)
SetFormat(DllCall("RegisterClipboardFormat", "Str", "image/svg+xml", "UInt"), "<svg xmlns=""http://www.w3.org/2000/svg""><path d=""M0 0L1 1""/></svg>")
SetFormat(DllCall("RegisterClipboardFormat", "Str", "Biff12", "UInt"), "private-formula-fixture")
SetFormat(DllCall("RegisterClipboardFormat", "Str", "XML Spreadsheet", "UInt"), "private-formula-fixture")
; Include embedded zero bytes to catch accidental string serialization.
VarSetCapacity(opaque, 16, 0)
NumPut(0xFEFF0001, opaque, 0, "UInt"), NumPut(0xDEADBEEF, opaque, 12, "UInt")
custom := DllCall("RegisterClipboardFormat", "Str", "Clipjump.BinaryFixture", "UInt")
SetRawFormat(custom, opaque, 16)
VarSetCapacity(dib, 44, 0)
NumPut(40, dib, 0, "UInt"), NumPut(1, dib, 4, "Int"), NumPut(1, dib, 8, "Int")
NumPut(1, dib, 12, "UShort"), NumPut(32, dib, 14, "UShort"), NumPut(4, dib, 20, "UInt")
NumPut(0xFF336699, dib, 40, "UInt")
SetRawFormat(8, dib, 44)
DllCall("CloseClipboard")

sequence := CJ_ClipboardSequence()
SplitPath, A_AhkPath, ownerName
Assert(CJ_ClipboardSourceProcess() = ownerName, "resolve clipboard owner through hidden window PID")
Assert(CJ_ReadClipboard(snapshot, text, sequence), "capture all rich formats")
Assert(text = unicode, "Unicode and emoji text survive capture")
Assert(CJ_ClipboardSequence() = sequence, "capture leaves live clipboard unchanged")
Assert(CJ_SnapshotText(snapshot) = unicode, "decode archive text without touching clipboard")
Assert(CJ_ClipboardSequence() = sequence, "archive indexing leaves live clipboard unchanged")
path := testDir "\rich snapshot " Chr(0x4E2D) ".avc"
Assert(CJ_WriteSnapshot(path, snapshot), "atomic binary archive write with Unicode path")
Assert(CJ_SnapshotEqualsFile(path, snapshot), "archive preserves every byte including embedded zeros")
FileRead, restored, *c %path%
Clipboard := "temporary replacement"
Clipboard := restored
Assert(GetFormatText("Rich Text Format") = rtf, "RTF formatting restores")
Assert(GetFormatText("HTML Format") = html, "HTML format and byte offsets restore")
Assert(GetFormatText("Portable Document Format") = pdf, "Adobe PDF payload restores")
Assert(GetFormatText("Adobe Illustrator Clipboard") = aicb, "Adobe Illustrator payload restores")
Assert(GetFormatText("image/svg+xml") != "", "SVG registered format restores")
Assert(FormatMatches(custom, opaque, 16), "opaque binary payload restores")
Assert(FormatMatches(8, dib, 44), "DIB image restores")
Assert(CJ_SaveThumbnail(snapshot, testDir "\preview.jpg"), "generate image preview from archive without reopening clipboard")
Assert(CJ_ReadOfficeClipboard(officeSnapshot), "Office safe capture completes")
Assert(CJ_WriteSnapshot(testDir "\office.avc", officeSnapshot), "Office snapshot is a valid binary archive")
Assert(CJ_SnapshotText(officeSnapshot) = unicode, "Office safe capture preserves Unicode text")
Clipboard := officeSnapshot
Assert(GetFormatText("Rich Text Format") = rtf, "Office safe capture preserves RTF")
Assert(GetFormatText("HTML Format") = html, "Office safe capture preserves HTML")
Assert(FormatMatches(8, dib, 44), "Office safe capture preserves DIB images")
Assert(GetFormatText("Biff12") = "", "Office history omits instance-dependent BIFF formulas")
Assert(GetFormatText("XML Spreadsheet") = "", "Office history omits formula-bearing spreadsheet XML")
Clipboard := restored

; Same text with new formatting must not collapse into the old clip.
TestOpenClipboard()
SetFormat(DllCall("RegisterClipboardFormat", "Str", "Rich Text Format", "UInt"), "{\rtf1 changed}")
DllCall("CloseClipboard")
Assert(CJ_ReadClipboard(changed, changedText), "capture changed formatting")
Assert(changedText = unicode && !CJ_SnapshotEqualsFile(path, changed), "same text with different formatting is a distinct clip")

; A failed write must not remove a valid archive.
FileCreateDir, % path ".pending"
Assert(!CJ_WriteSnapshot(path, changed), "report unwritable temporary archive")
Assert(CJ_SnapshotEqualsFile(path, snapshot), "failed write keeps prior archive intact")
FileRemoveDir, % path ".pending"

job := new CJ_CaptureJob(testDir "\worker", A_AhkPath, A_WorkingDir "\lib\clipboardCaptureWorker.ahk", 20, 3000)
job.Queue(1, 0)
Assert(WaitJob(job) = "ready", "isolated capture worker completes")
FileRead, workerData, % "*c " job.Prefix ".avc"
Assert(CJ_SnapshotEqualsFile(job.Prefix ".avc", changed), "worker preserves full binary clipboard")
job.Cancel()
job.Queue(1, 0)
Clipboard := "newer clipboard sequence"
Assert(job.Poll() = "stale", "reject stale capture after clipboard change")

; A busy clipboard must return within the explicit access deadline.
RunFixture("lock")
started := DllCall("GetTickCount64", "UInt64")
Assert(!CJ_ClipboardWait(120), "busy clipboard returns failure")
Assert(DllCall("GetTickCount64", "UInt64") - started < 750, "clipboard lock wait is bounded")
StopFixture()

; A hostile/slow delayed renderer cannot freeze the parent process.
RunFixture("delayed")
job := new CJ_CaptureJob(testDir "\timeout", A_AhkPath, A_WorkingDir "\lib\clipboardCaptureWorker.ahk", 20, 500)
job.Queue(2, 0)
started := DllCall("GetTickCount64", "UInt64")
Assert(WaitJob(job) = "timeout", "slow delayed renderer is terminated at worker deadline")
Assert(DllCall("GetTickCount64", "UInt64") - started < 2000, "parent remains responsive during slow rendering")
StopFixture()

FileAppend, % "RESULT " checks " checks; " failures " failures; " (A_PtrSize * 8) "-bit`n", *
ExitApp, % failures ? 1 : 0

Assert(condition, name) {
    global checks, failures
    checks += 1
    if !condition
        failures += 1
    FileAppend, % (condition ? "PASS " : "FAIL ") name "`n", *
}

SetFormat(format, text, encoding := "UTF-8") {
    size := StrPut(text, encoding)
    VarSetCapacity(bytes, size * (encoding = "UTF-16" ? 2 : 1), 0)
    StrPut(text, &bytes, size, encoding)
    return SetRawFormat(format, bytes, VarSetCapacity(bytes))
}

SetRawFormat(format, ByRef bytes, size) {
    handle := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", size, "Ptr")
    ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
    DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", &bytes, "UPtr", size)
    DllCall("GlobalUnlock", "Ptr", handle)
    if !DllCall("SetClipboardData", "UInt", format, "Ptr", handle, "Ptr") {
        DllCall("GlobalFree", "Ptr", handle)
        return false
    }
    return true
}

GetFormatText(name) {
    if !TestOpenClipboard()
        return ""
    handle := DllCall("GetClipboardData", "UInt", DllCall("RegisterClipboardFormat", "Str", name, "UInt"), "Ptr")
    ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
    text := ptr ? StrGet(ptr, "UTF-8") : ""
    if ptr
        DllCall("GlobalUnlock", "Ptr", handle)
    DllCall("CloseClipboard")
    return text
}

FormatMatches(format, ByRef bytes, size) {
    if !TestOpenClipboard()
        return false
    handle := DllCall("GetClipboardData", "UInt", format, "Ptr")
    ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
    matches := ptr && !DllCall("msvcrt\memcmp", "Ptr", ptr, "Ptr", &bytes, "UPtr", size, "Cdecl Int")
    if ptr
        DllCall("GlobalUnlock", "Ptr", handle)
    DllCall("CloseClipboard")
    return matches
}

TestOpenClipboard() {
    started := A_TickCount
    while !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
        if (A_TickCount - started >= 500)
            return false
        Sleep, 10
    }
    return true
}

WaitJob(job) {
    started := DllCall("GetTickCount64", "UInt64")
    loop {
        status := job.Poll()
        if (status != "waiting")
            return status
        if (DllCall("GetTickCount64", "UInt64") - started > 5000)
            return "test-timeout"
        Sleep, 20
    }
}

RunFixture(mode) {
    global fixturePid, testDir
    ready := testDir "\fixture.ready"
    FileDelete, % ready
    command := """" A_AhkPath """ /ErrorStdOut """ A_ScriptDir "\clipboard-fixture.ahk"" " mode " """ ready """"
    Run, % command,, Hide, fixturePid
    started := A_TickCount
    while !FileExist(ready) && A_TickCount - started < 2000
        Sleep, 10
    Assert(FileExist(ready), mode " fixture started")
}

StopFixture() {
    global fixturePid
    if fixturePid {
        Process, Close, % fixturePid
        fixturePid := 0
    }
}

Cleanup:
    if IsObject(job)
        job.Cancel()
    StopFixture()
    try Clipboard := savedClipboard
    ; Leave the uniquely named temporary directory available if a test fails.
    ExitApp, % failures ? 1 : 0

#Include %A_ScriptDir%\..\lib\clipboardIO.ahk
#Include %A_ScriptDir%\..\lib\clipboardThumbnail.ahk
#Include %A_ScriptDir%\..\lib\gdip_min.ahk
