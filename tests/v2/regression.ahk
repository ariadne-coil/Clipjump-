#Requires AutoHotkey v2.0.31+
#SingleInstance Off
#NoTrayIcon
#ClipboardTimeout 250
#Include Includes.ahk
global Checks := 0, Failures := 0, Sent := [], CJ_UserPluginLoader := 0
root := A_ScriptDir "\..\..", temporary := A_Temp "\Clipjump-v2-test-" CJNewId()
DirCreate(temporary)
original := ClipboardAll(), store := false, app := false, fixture := 0
try {
    text := "Unicode Ω 漢字 🦋 ' quote`r`nsecond line"
    snapshot := CJSnapshot.FromText(text)
    Check(snapshot.Text = text, "Unicode snapshot")
    AddFormat(snapshot, "HTML Format", "<b>rich</b>")
    AddFormat(snapshot, "Rich Text Format", "{\rtf1\b rich}")
    AddFormat(snapshot, "Adobe Illustrator AICB", "opaque" Chr(1))
    AddFormat(snapshot, "PDF", "%PDF-1.7")
    AddFormat(snapshot, "image/svg+xml", '<svg xmlns="http://www.w3.org/2000/svg"/>')
    A_Clipboard := snapshot.Native()
    captured := CJClipboard.Capture()
    Check(captured.Text = text, "Native text replay")
    for name in ["HTML Format", "Rich Text Format", "Adobe Illustrator AICB", "PDF", "image/svg+xml"]
        Check(IsObject(captured.Find(name)), "Rich format preserved: " name)
    path := temporary "\portable.cjc", snapshot.Save(path)
    loaded := CJSnapshot.Load(path)
    Check(snapshot.Equals(loaded), "Portable archive round trip")
    loaded.Entries[2].Id := 0xFFFF
    Check(snapshot.Equals(loaded), "Registered IDs do not affect archive identity")
    A_Clipboard := loaded.Native()
    Check(DllCall("IsClipboardFormatAvailable", "UInt", DllCall("RegisterClipboardFormatW", "Str", "HTML Format", "UInt")), "Named formats remap on restore")
    for name in ["Biff8", "XML Spreadsheet", "Object Descriptor", "Embed Source"]
        Check(!CJClipboard.OfficeFormat(0xC123, name), "Office excludes live data: " name)
    for name in ["HTML Format", "Rich Text Format", "PNG", "image/svg+xml", "CSV"]
        Check(CJClipboard.OfficeFormat(0xC123, name), "Office retains transferable format: " name)
    Check(!CJClipboard.VolatileFormat("Adobe Illustrator AICB") && CJClipboard.VolatileFormat("Ole Private Data"), "Private application data policy")
    FileAppend("trailing", path)
    Throws(() => CJSnapshot.Load(path), "Reject trailing archive bytes")
    invalid := Buffer(12, 0)
    NumPut("UInt", 13, invalid), NumPut("UInt", 99999, invalid, 4)
    Throws(() => CJSnapshot.FromNative(invalid), "Reject native record overflow")
    for width in [4, 8] {
        legacyRaw := Legacy(snapshot, width), legacyPath := temporary "\legacy" width ".avc"
        legacyFile := FileOpen(legacyPath, "w"), legacyFile.RawWrite(legacyRaw), legacyFile.Close()
        migrated := CJLegacyImport.Snapshot(legacyPath)
        Check(migrated.Text = text && migrated.Entries.Length = 1, "Safe v1 import " width * 8 " bit")
        Check(CJLegacyImport.Snapshot(legacyPath, true).Entries.Length = snapshot.Entries.Length, "Same-session registered import " width * 8 " bit")
    }
    library := root "\runtime-v2\" (A_PtrSize = 8 ? "x64" : "x86") "\sqlite3.dll"
    store := CJStore(temporary "\store", library)
    id := store.Add(snapshot)
    Check(store.Snapshot(id).Equals(snapshot), "History retains binary formats")
    Check(store.Get(id).text = text, "Bound Unicode and quoted SQL value")
    Check(store.Add(snapshot, 0, true, true) = id, "Optional binary deduplication")
    channel := store.AddChannel("Pinned Ω", true, true)
    Check(store.Channel(channel).protected && store.Channel(channel).no_history, "Channel metadata")
    store.Move(id, 0, channel, true)
    Check(store.List(0).Length = 1 && store.List(channel).Length = 1, "Copy channel membership")
    store.Pin(id, channel, true), store.Compact(channel, 0)
    Check(store.List(channel).Length = 1 && store.List(channel)[1].pinned, "Compaction preserves pinned clips")
    store.Tag(id, "tag ' Ω")
    Check(store.List(channel, false, "tag ' Ω").Length = 1, "Literal tag search")
    Check(store.List(channel, false, "%").Length = 0, "Search treats wildcard literally")
    store.Move(id, 0, channel)
    Check(!store.List(0).Length && store.List(channel).Length = 1, "Move channel membership")
    store.Replace(id, CJSnapshot.FromText("replacement"))
    Check(store.Snapshot(id).Text = "replacement", "Replace history archive")
    store.Remove(id, channel)
    Check(store.List(0, true).Length = 1, "History survives channel removal")
    store.Remove(id, 0, true)
    Check(!store.List(0, true).Length, "Remove unreferenced archive")
    store.DB.Exec("INSERT INTO clips(created,text,kind,bytes,file) VALUES ('2000-01-01','bad','text',0,'..\outside.cjc')")
    Throws(() => store.Path(store.DB.LastId), "Reject database path traversal")
    store.DB.Exec("DELETE FROM clips WHERE file='..\outside.cjc'")
    oldRoot := temporary "\legacy", DirCreate(oldRoot "\cache\clips")
    FileCopy(temporary "\legacy8.avc", oldRoot "\cache\clips\1.avc")
    IniWrite("v1 tag", oldRoot "\cache\clips\prefs.ini", "1", "Tags")
    IniWrite(1, oldRoot "\cache\clips\prefs.ini", "1", "fixed")
    before := FileRead(oldRoot "\cache\clips\1.avc", "RAW")
    importer := CJLegacyImport(store, library), report := importer.Run(oldRoot)
    Check(report.Imported = 1 && report.Failed = 0, "Import v1 channel directory")
    Check(store.List(0)[1].tag = "v1 tag" && store.List(0)[1].pinned, "Import legacy tags and pins")
    Check(importer.Run(oldRoot).Skipped = 1, "Legacy import is idempotent")
    Check(FileRead(oldRoot "\cache\clips\1.avc", "RAW").Size = before.Size, "Legacy source preserved")
    Throws(() => importer.SourceFile(oldRoot, "..\outside.avc"), "Reject legacy path escape")
    legacyDB := CJDatabase(oldRoot "\cache\data.db", library)
    legacyDB.Exec("PRAGMA journal_mode=DELETE")
    legacyDB.Exec("CREATE TABLE history (id INTEGER PRIMARY KEY,data TEXT,type INTEGER,fileid TEXT,time TEXT,size INTEGER,snapshot TEXT)")
    legacyDB.Exec("INSERT INTO history VALUES (1,?1,0,'','2026-10-26 12:00:00',10,'')", ["old history Ω '"])
    legacyDB.Exec("INSERT INTO history VALUES (2,'snapshot',0,'','2026-10-26 12:01:00',10,'cache\clips\1.avc')")
    legacyDB.Close()
    beforeDB := FileRead(oldRoot "\cache\data.db", "RAW")
    report := importer.Run(oldRoot)
    Check(report.Imported = 2 && !report.Failed, "Import legacy text and binary history")
    Check(store.List(0, true, "old history Ω '").Length = 1, "Imported history preserves Unicode and quotes")
    afterDB := FileRead(oldRoot "\cache\data.db", "RAW")
    Check(beforeDB.Size = afterDB.Size && !DllCall("msvcrt\memcmp", "Ptr", beforeDB, "Ptr", afterDB, "UPtr", beforeDB.Size, "Cdecl Int"), "Legacy database opened read-only")
    Check(importer.Run(oldRoot).Skipped = 3, "History import is idempotent")
    ; A 2x2 DIB exercises image encoding and decoding without touching the clipboard.
    image := CJSnapshot(), dib := Buffer(56, 0)
    NumPut("UInt", 40, dib), NumPut("Int", 2, dib, 4), NumPut("Int", 2, dib, 8)
    NumPut("UShort", 1, dib, 12), NumPut("UShort", 32, dib, 14)
    loop 4
        NumPut("UInt", 0xFFFF8000, dib, 40 + (A_Index - 1) * 4)
    image.Entries.Push({Id: 8, Name: "", Data: dib})
    Check(CJImage.Thumbnail(image, temporary "\image.png", true), "Encode saved DIB image")
    decoded := CJImage.FromFile(temporary "\image.png")
    Check(decoded.Find(17).Size = 140 && decoded.Find(8).Size = 56, "Decode DIBV5 and DIB fallback")
    Check(CJImage.Thumbnail(decoded, temporary "\thumb.jpg"), "Thumbnail imported image")
    NumPut("Int", 100000, dib, 4)
    Check(!CJImage.Thumbnail(image, temporary "\invalid.jpg"), "Reject truncated DIB pixel data")
    store.Close(), store := false
    previousDirectory := A_WorkingDir
    SetWorkingDir(temporary)
    relativeConfig := CJConfig(temporary, "relative-data")
    Check(relativeConfig.Data = temporary "\relative-data", "Relative data paths resolve before worker launch")
    SetWorkingDir(previousDirectory)
    app := CJApp(root, temporary "\app-data", {ConfigRoot: temporary, Hooks: false, Sender: RecordSend})
    Check(app.Plugins.Transform("upper", "Ω hello") = "Ω HELLO", "Native v2 uppercase plugin")
    Check(app.Plugins.Transform("sentence", "hELLO. wORLD!") = "Hello. World!", "Sentence plugin")
    Check(app.Plugins.Transform("numbered", "one`ntwo") = "1. one`r`n2. two", "Numbered list plugin")
    Check(app.Plugins.Transform("unhtml", '<script>bad()</script><p>&lt;b&gt; &#x3A9;</p>') = "<b> Ω", "HTML text parser avoids executable markup")
    Check(app.Plugins.Transform("regex", "a1b2", "\d`nX") = "aXbX", "Regex plugin")
    Throws(() => app.Plugins.Transform("regex", "abc", "[`nX"), "Invalid regex returns controlled error")
    app.Plugins.Register("test", "Test callback", (value, parameter) => value parameter)
    Check(app.Plugins.Transform("test", "a", "b") = "ab", "Native v2 plugin extension")
    old := app.AddSnapshot(CJSnapshot.FromText("older")), latest := app.AddSnapshot(snapshot)
    app.LastSnapshot := snapshot, app.LastId := latest
    app.LastSequence := app.WriteClipboard(snapshot), sequence := CJClipboard.Sequence()
    app.BeginPaste(), SetTimer(app.PasteTimer, 0)
    Check(app.Mode.Native && CJClipboard.Sequence() = sequence, "First paste leaves live application clipboard intact")
    app.FinishPaste()
    Check(Sent.Length = 1 && Sent[1] = "^v" && CJClipboard.Sequence() = sequence, "Native first paste sends once")
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.Cycle(1)
    Check(A_Clipboard = "older", "Paste mode cycles saved history")
    app.CancelPaste(true)
    restored := CJClipboard.Capture()
    Check(restored.Text = snapshot.Text && IsObject(restored.Find("HTML Format")) && IsObject(restored.Find("Adobe Illustrator AICB")), "Cancel restores original rich clip")
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.Cycle(1), app.FinishPaste()
    app.BeginPaste(), SetTimer(app.PasteTimer, 0)
    Check(IsObject(app.Mode) && app.Mode.Native && app.Mode.Items[app.Mode.Index].id = old, "Repeated paste mode remembers saved selection")
    app.CancelPaste(false)
    app.LastSnapshot := snapshot, app.LastId := latest, app.LastSequence := app.WriteClipboard(snapshot)
    FileDelete(app.Store.Path(old))
    app.BeginPaste(), SetTimer(app.PasteTimer, 0)
    Throws(() => app.Cycle(1), "Missing history archive returns controlled error")
    Check(!app.Mode, "Missing archive cancels paste instead of sending another clip")
    app.LastSequence := CJClipboard.Sequence()
    app.BeginPaste(), SetTimer(app.PasteTimer, 0)
    A_Clipboard := "external newer copy"
    sentBefore := Sent.Length, app.FinishPaste()
    Check(Sent.Length = sentBefore && A_Clipboard = "external newer copy", "External clipboard changes cancel stale paste")
    app.Config.Set("IncognitoStopsCapture", 1), app.Config.Set("Incognito", 1), Check(!app.QueueCapture(), "Strict private mode refuses capture worker")
    app.Config.Set("Incognito", 0), app.Config.Set("IgnoredProcesses", "test.exe")
    Check(app.Config.Ignored("TEST.EXE", "") && !app.Config.Ignored("other.exe", ""), "Ignored source matching")
    app.Config.Set("CopyMessage", 0)
    A_Clipboard := "queued application clip"
    app.QueueCapture()
    Check(app.Job.ProcessHandle && app.Job.Pending, "Copy starts the isolated capture worker immediately")
    deadline := A_TickCount + 4500
    while app.Job.Pending && A_TickCount < deadline
        Sleep(25)
    Check(IsObject(app.LastSnapshot) && app.LastSnapshot.Text = "queued application clip", "Application commits completed capture worker")
    Check(app.Store.Get(app.LastId).text = "queued application clip", "Application capture updates history metadata")
    IniWrite("history", app.Config.CustomFile, "Hotkeys", "^!F12")
    IniWrite("Synthetic hotstring", app.Config.HotPasteFile, "Text", "cj-test")
    app.LoadCustomizations()
    Check(app.Hotkeys.Has("$^!F12") && app.Hotstrings.Length = 1, "Native custom hotkey and hotstring registration")
    app.UnregisterHotkeys()
    Check(app.Smoke(), "All native interface dialogs construct without clipboard mutation")
    apiId := app.AddSnapshot(CJSnapshot.FromText("API`r`nline\tail"))
    callback := ObjBindMethod(app, "ReceiveAPI"), OnMessage(0x4A, callback)
    resultPath := temporary "\api-result.txt"
    Run('"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\APIClient.ahk" ' A_ScriptHwnd ' "' resultPath '"', , "Hide", &client)
    deadline := A_TickCount + 6000
    while !FileExist(resultPath) && A_TickCount < deadline
        Sleep(20)
    Check(FileExist(resultPath) && FileRead(resultPath) = "OK", "Cross-process API, escaped parameters, bounded errors")
    OnMessage(0x4A, callback, 0)
    app.Shutdown(), app := false
    A_Clipboard := "worker clip"
    job := CJCaptureJob(temporary "\worker", A_AhkPath, root "\v2\CaptureWorker.ahk", 0, 3000)
    job.Queue(0), sequence := CJClipboard.Sequence(), status := PollJob(job)
    Check(status = "ready", "Isolated clipboard worker completes")
    if status = "ready"
        Check(CJSnapshot.Load(job.Prefix ".cjc").Text = "worker clip", "Worker archive content")
    Check(CJClipboard.Sequence() = sequence, "Worker never modifies clipboard")
    job.Cancel(), Check(!job.ProcessHandle && !job.Pending, "Worker handles cleaned")
    job.Queue(0), A_Clipboard := "newer"
    Check(job.Poll() = "stale", "Stale capture discarded")
    for mode in ["lock", "delayed"] {
        ready := temporary "\" mode ".ready"
        Run('"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\ClipboardFixture.ahk" ' mode ' "' ready '"', , "Hide", &fixture)
        deadline := A_TickCount + 3000
        while !FileExist(ready) && A_TickCount < deadline
            Sleep(10)
        Check(FileExist(ready), mode " fixture starts")
        job.Queue(0), started := A_TickCount, status := PollJob(job)
        Check((status = "timeout" || status = "error") && A_TickCount - started < 5000, mode " clipboard failure is bounded")
        Check(!job.ProcessHandle && !job.Pending, mode " failed worker cleaned")
        if ProcessExist(fixture)
            ProcessClose(fixture)
        fixture := 0
        Sleep(50)
    }
} catch as err {
    Failures += 1
    FileAppend("FAIL Unhandled: " err.Message " " err.File ":" err.Line "`n" err.Stack "`n", "*")
} finally {
    if fixture && ProcessExist(fixture)
        ProcessClose(fixture)
    if IsObject(app)
        app.Shutdown()
    if IsObject(store)
        store.Close()
    A_Clipboard := original
    CJImage.Stop()
    ; This uniquely generated test directory is the only deletion target.
    try DirDelete(temporary, true)
}
FileAppend("RESULT " Checks " checks; " Failures " failures; ptr=" A_PtrSize "`n", "*")
ExitApp(Failures ? 1 : 0)

Check(condition, name) {
    global Checks, Failures
    Checks += 1
    if !condition
        Failures += 1
    FileAppend((condition ? "PASS " : "FAIL ") name "`n", "*")
}
Throws(callback, name) {
    rejected := false
    try callback.Call()
    catch
        rejected := true
    Check(rejected, name)
}
AddFormat(snapshot, name, value) {
    data := CJDatabase.Utf8(value)
    snapshot.Entries.Push({Id: DllCall("RegisterClipboardFormatW", "Str", name, "UInt"), Name: name, Data: data})
}
Legacy(snapshot, width) {
    bytes := 4
    for entry in snapshot.Entries
        bytes += 4 + width + entry.Data.Size
    raw := Buffer(bytes, 0), offset := 0
    for entry in snapshot.Entries {
        NumPut("UInt", entry.Id, raw, offset)
        NumPut(width = 8 ? "UInt64" : "UInt", entry.Data.Size, raw, offset + 4)
        DllCall("RtlMoveMemory", "Ptr", raw.Ptr + offset + 4 + width, "Ptr", entry.Data, "UPtr", entry.Data.Size)
        offset += 4 + width + entry.Data.Size
    }
    return raw
}
RecordSend(keys) {
    global Sent
    Sent.Push(keys)
}
PollJob(job) {
    deadline := A_TickCount + 4500, status := "waiting"
    while status = "waiting" && A_TickCount < deadline {
        status := job.Poll()
        Sleep(20)
    }
    return status
}
