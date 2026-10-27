#Requires AutoHotkey v2.0.31+
#SingleInstance Off
#NoTrayIcon
#ClipboardTimeout 250
#Include Includes.ahk
global Checks := 0, Failures := 0, Sent := [], UpdateDone := false, CJ_UserPluginLoader := 0
root := A_ScriptDir "\..\..", temporary := A_Temp "\Clipjump-features-" CJNewId()
DirCreate(temporary)
original := ClipboardAll(), app := false, store := false
try {
    app := MakeApp("main"), store := app.Store
    Check(app.Config.Get("RememberFormat") && app.Config.Get("KeepSession"), "Retention and remembered-format controls exist")
    Check(app.Config.Get("StoreImages") && !app.Config.Get("LimitAllChannels"), "Image history and default-channel-only limits")
    values := app.Config.Values.Clone(), values["MaximumChannelClips"] := 0
    CJFeatureSettings.Validate(values)
    Check(true, "Unlimited channel limit is valid")
    for pair in [["ClipThreshold", 0], ["ThumbnailQuality", 101], ["BeepFrequency", 10], ["PasteX", "invalid"], ["ProcessPriority", "unknown"], ["FormatKey", "x"]] {
        invalid := values.Clone(), invalid[pair[1]] := pair[2]
        Throws(() => CJFeatureSettings.Validate(invalid), "Reject invalid setting: " pair[1])
    }
    a := store.Add(CJSnapshot.FromText("oldest"), 0, false)
    b := store.Add(CJSnapshot.FromText("fixed"), 0, false)
    c := store.Add(CJSnapshot.FromText("newest"), 0, false)
    store.Pin(b, 0, true)
    d := store.Add(CJSnapshot.FromText("later"), 0, false)
    Check(store.List(0)[2].id = b, "Fixate retains exact slot after a new copy")
    e := store.Add(CJSnapshot.FromText("later again"), 0, false)
    Check(store.List(0)[2].id = b && store.List(0)[1].id = e, "Fixate survives repeated new copies")
    store.Compact(0, 2)
    Check(store.List(0).Length = 3 && store.List(0)[2].id = b, "Compaction retains fixed slot and pinned archive")
    store.SwapClips(d, e, 0, 0)
    Check(store.List(0)[1].id = d && store.List(0)[2].id = b, "Clip swaps exchange positions without moving other fixed clips")
    work := store.AddChannel("Work"), id := store.Add(CJSnapshot.FromText("work clip"), work, false)
    store.SwapChannels(0, work)
    Check(store.List(0)[1].id = id && store.List(work)[2].id = b, "Channel swap preserves content and fixed positions")
    Check(store.Channel(work).name = "Work", "Channel swap retains channel identity")
    store.SwapClips(id, d, 0, work)
    Check(store.List(0)[1].id = d, "Cross-channel clip swap")
    store.Move(id, work, 0, true)
    Throws(() => store.SwapClips(d, id, 0, work), "Swap rejects duplicate membership collision")
    Check(store.List(-1).Length = 4, "Combined channel view lists shared clips once")
    store.Move(id, -1, work)
    Check(!store.DB.Query("SELECT 1 FROM memberships WHERE clip_id=?1 AND channel_id<>?2", [id, work]).Length, "Move from combined view moves all memberships")
    Check(CJStore.Matches("red middle blue", "red blue", true), "Partial search matches all space-delimited terms")
    Check(!CJStore.Matches("red middle blue", "red blue", false), "Contiguous search remains distinct from partial search")
    Check(!CJStore.Matches("red blue", "red green", true), "Partial search requires every term")
    Check(CJStore.Matches("Österreich 漢字", "österreich", false), "Search handles Unicode case folding")
    Check(CJUI.FindRange("one two one", "one", 5).Position = 9, "Preview find advances")
    Check(CJUI.FindRange("one two", "one", 5).Position = 1, "Preview find wraps")
    Check(CJUI.FindRange("one middle two", "one two", 2, true).Position = 12, "Preview partial find searches individual terms")
    store.Clear(-1)
    app.Config.Set("MaximumChannelClips", 2), app.Config.Set("ClipThreshold", 3)
    loop 4
        app.AddSnapshot(CJSnapshot.FromText("threshold " A_Index))
    Check(store.List(0).Length = 4, "Threshold allows a temporary batch above minimum")
    app.AddSnapshot(CJSnapshot.FromText("threshold 5"))
    Check(store.List(0).Length = 2, "Threshold cleanup returns to configured minimum")
    loop 6
        app.AddSnapshot(CJSnapshot.FromText("unlimited work " A_Index), work)
    Check(store.List(work).Length = 6, "Non-default channels are unlimited by default")
    app.Config.Set("MaximumChannelClips", 0)
    loop 6
        app.AddSnapshot(CJSnapshot.FromText("unlimited default " A_Index))
    Check(store.List(0).Length = 8, "Zero limit disables channel trimming")
    image := MakeImage(0xFFFF4000)
    app.Config.Set("StoreImages", 0)
    imageId := app.AddSnapshot(image)
    Check(!store.Get(imageId).in_history && IsObject(store.Snapshot(imageId)), "Image-history opt-out keeps channel image")
    app.Config.Set("StoreImages", 1)
    Check(store.Get(app.AddSnapshot(image)).in_history, "Image-history opt-in archives image")
    Check(CJImage.Thumbnail(image, temporary "\low.jpg", false, 10) && CJImage.Thumbnail(image, temporary "\high.jpg", false, 100), "JPEG quality encoder accepts both settings")
    low := FileRead(temporary "\low.jpg", "RAW"), high := FileRead(temporary "\high.jpg", "RAW")
    Check(low.Size != high.Size || DllCall("msvcrt\memcmp", "Ptr", low, "Ptr", high, "UPtr", Min(low.Size, high.Size), "Cdecl Int"), "JPEG quality changes encoded data")
    dimensions := CJImage.Dimensions(temporary "\high.jpg")
    Check(dimensions.Width = 2 && dimensions.Height = 2, "Image preview reports original dimensions")
    app.Config.Set("Incognito", 1), app.Config.Set("IncognitoStopsCapture", 0)
    Check(app.QueueCapture(), "History-only incognito allows channel capture")
    app.Job.Cancel(), SetTimer(app.CaptureTimer, 0)
    privateId := app.AddSnapshot(CJSnapshot.FromText("channel only private"))
    Check(!store.Get(privateId).in_history && store.List(0, false, "channel only private").Length, "History-only incognito excludes global history")
    app.Config.Set("IncognitoStopsCapture", 1)
    Check(!app.QueueCapture(), "Strict private option still stops capture")
    app.Config.Set("Incognito", 0), app.Config.Set("IncognitoStopsCapture", 0)
    app.Config.Set("ManualCaptureOnly", 1), app.CopyIntent := false
    Check(!app.ManualAllowed(), "Manual-only capture rejects programmatic changes")
    app.ArmCopy()
    Check(app.ManualAllowed(), "Explicit copy opens capture intent")
    app.CopyIntent.PID := 123
    Check(!app.ManualAllowed(456), "Manual capture rejects unrelated clipboard owner")
    app.CopyIntent.Until := A_TickCount - 1
    Check(!app.ManualAllowed(), "Copy intent expires")
    app.Config.Set("WinCopyCut", 1), app.CopyIntent := false
    app.CopyObserved()
    Check(!app.ManualAllowed(), "Win split mode ignores ordinary Ctrl+C")
    sentBefore := Sent.Length, app.WinCopy(false)
    Check(app.ManualAllowed() && Sent.Length = sentBefore + 1 && Sent[Sent.Length] = "^c", "Win copy sends one native copy and arms capture")
    app.Config.Set("WinCopyCut", 0), app.Config.Set("ManualCaptureOnly", 0)
    app.OneTimeStop(), A_Clipboard := "ignored single copy"
    app.ClipboardChanged(1)
    Check(!app.SkipNextCopy && !app.Job.Pending, "One Time Stop consumes one copy")
    app.SuppressUntil := 0, A_Clipboard := "next copy captured", app.ClipboardChanged(1)
    Check(app.Job.Pending, "Capture resumes after One Time Stop")
    app.Job.Cancel(), SetTimer(app.CaptureTimer, 0)
    app.SetChannel(work), app.PitSwap()
    Check(StrLower(store.Channel(app.Channel).name) = "pit", "PitSwap activates Pit")
    app.PitSwap()
    Check(app.Channel = work, "PitSwap returns to previous channel")
    app.SetChannel(0), store.Clear(0)
    rich := CJSnapshot.FromText("Rich Ω`r`n`r`n")
    rich.Entries.Push({Id: DllCall("RegisterClipboardFormatW", "Str", "Rich Text Format", "UInt"), Name: "Rich Text Format", Data: CJDatabase.Utf8("{\rtf1\b Rich}")})
    richId := app.AddSnapshot(rich)
    app.LastId := richId, app.LastSnapshot := rich, app.LastSequence := app.WriteClipboard(rich)
    app.Config.Set("DefaultFormat", "plain"), app.Config.Set("RememberFormat", 0)
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.FinishPaste()
    Check(A_Clipboard = rich.Text, "Plain-text default preserves exact Unicode and trailing newlines")
    Check(!DllCall("IsClipboardFormatAvailable", "UInt", DllCall("RegisterClipboardFormatW", "Str", "Rich Text Format", "UInt")), "Plain-text paste strips rich formats")
    app.Config.Set("RememberFormat", 1), app.Config.Set("LastFormat", "plain")
    app.PasteIds([richId])
    Check(A_Clipboard = rich.Text && !DllCall("IsClipboardFormatAvailable", "UInt", DllCall("RegisterClipboardFormatW", "Str", "Rich Text Format", "UInt")), "History instant paste uses remembered plain-text format")
    app.PasteIds([app.AddSnapshot(image)])
    Check(DllCall("IsClipboardFormatAvailable", "UInt", 8), "Text formatting preference preserves image-only history paste")
    app.Config.Set("RememberFormat", 0)
    table := MakeImage(0xFF0000FF)
    table.Entries.Push(rich.Entries[1])
    Check(table.Kind = "text", "Office text remains text when a DIB representation is also offered")
    app.LastSnapshot := table, app.LastSequence := app.WriteClipboard(table)
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.FinishPaste()
    Check(A_Clipboard = rich.Text && !DllCall("IsClipboardFormatAvailable", "UInt", 8), "Plain-text default handles mixed Office text and bitmap formats")
    app.LastSnapshot := image, app.LastSequence := app.WriteClipboard(image)
    sequence := CJClipboard.Sequence(), sentBefore := Sent.Length
    app.PastePlain()
    Check(CJClipboard.Sequence() = sequence && Sent.Length = sentBefore, "One-time plain paste leaves image-only clipboard intact")
    app.Config.Set("DefaultFormat", "none"), app.Config.Set("RememberFormat", 1), app.Config.Set("LastFormat", "upper")
    Check(app.InitialFormat() = "upper", "Retain-last-used overrides default")
    app.LastSnapshot := rich, app.LastSequence := app.WriteClipboard(rich)
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.DoPasteAction("plain"), app.FinishPaste()
    Check(app.Config.Get("LastFormat") = "plain", "Paste-mode plain-text choice is remembered")
    app.LastSequence := CJClipboard.Sequence()
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.Mode.Format := "lower", app.CancelPaste(true)
    Check(app.Config.Get("LastFormat") = "plain", "Cancel does not overwrite last-used format")
    app.LastSnapshot := rich, app.LastSequence := app.WriteClipboard(rich)
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.Mode.Format := "plain"
    app.ApplyModeFormat(), app.Mode.Format := "none", app.ApplyModeFormat()
    Check(DllCall("IsClipboardFormatAvailable", "UInt", DllCall("RegisterClipboardFormatW", "Str", "Rich Text Format", "UInt")), "Switching back to original restores rich data")
    app.Mode.Format := "plain", app.DoPasteAction("multi"), app.Mode.Format := "lower", app.FinishPaste()
    Check(app.Config.Get("LastFormat") = "plain", "Last-used format records the actual multipaste, not an unused selection")
    app.Config.Set("RememberFormat", 0), app.Config.Set("DefaultFormat", "plain")
    app.LastSequence := 0, A_Clipboard := rich.Native(), sentBefore := Sent.Length
    app.BeginPaste()
    Check(IsObject(app.PendingRequest) && app.Job.Pending, "Fast plain paste waits for isolated capture instead of leaking rich formatting")
    deadline := A_TickCount + 4500
    while app.Job.Pending && A_TickCount < deadline
        Sleep(20)
    Check(Sent.Length = sentBefore + 1 && A_Clipboard = rich.Text && !DllCall("IsClipboardFormatAvailable", "UInt", DllCall("RegisterClipboardFormatW", "Str", "Rich Text Format", "UInt")), "Fast plain paste converts and sends exactly once")
    app.AddSnapshot(CJSnapshot.FromText("queued older"))
    app.LastSequence := 0, A_Clipboard := "queued new", sentBefore := Sent.Length
    app.BeginPaste(), queuedAt := app.Job.QueuedAt, app.BeginPaste()
    Check(app.Job.QueuedAt = queuedAt && app.PendingRequest.Cycles = 1, "Repeated paste while capturing queues a relative jump without restarting worker")
    deadline := A_TickCount + 4500
    while app.Job.Pending && A_TickCount < deadline
        Sleep(20)
    Check(A_Clipboard = "queued older" && Sent.Length = sentBefore + 1, "Queued paste-mode jump selects older clip after capture")
    app.LastSequence := 0, A_Clipboard := "superseded paste", sentBefore := Sent.Length
    app.BeginPaste(), A_Clipboard := "new copy after paste request", app.ClipboardChanged(1)
    Check(!app.PendingRequest && app.Job.Pending && !app.ForcedCapture, "New copy cancels queued paste and enters normal capture")
    deadline := A_TickCount + 4500
    while app.Job.Pending && A_TickCount < deadline
        Sleep(20)
    Check(Sent.Length = sentBefore && store.List(0, false, "new copy after paste request").Length, "Superseding copy is archived without pasting")
    app.Config.Set("DefaultFormat", "none")
    app.Config.Set("RememberFormat", 0)
    Check(app.InitialFormat() = "none", "Reset-to-default ignores remembered format")
    app.LastSnapshot := rich, app.LastSequence := app.WriteClipboard(rich)
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), sentBefore := Sent.Length
    app.DoPasteAction("clipboard")
    Check(!app.Mode && Sent.Length = sentBefore, "S copies without sending a paste")
    app.LastSequence := CJClipboard.Sequence()
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.DoPasteAction("cycle-action")
    Check(app.Mode.Action = "cancel", "X enters cancel mode")
    sentBefore := Sent.Length, app.FinishPaste()
    Check(!app.Mode && Sent.Length = sentBefore, "Release in cancel mode sends nothing")
    app.LastSequence := CJClipboard.Sequence()
    app.BeginPaste(), SetTimer(app.PasteTimer, 0)
    for expected in ["cancel", "delete", "move", "copy", "delete-all", "cancel"] {
        app.DoPasteAction("cycle-action")
        Check(app.Mode.Action = expected, "X cycles action: " expected)
    }
    app.CancelPaste(true)
    second := app.AddSnapshot(CJSnapshot.FromText("relative 2")), third := app.AddSnapshot(CJSnapshot.FromText("relative 3"))
    app.LastId := third, app.LastSnapshot := store.Snapshot(third), app.LastSequence := app.WriteClipboard(app.LastSnapshot)
    app.BeginPaste(), SetTimer(app.PasteTimer, 0), app.RelativeSelect(2)
    Check(app.Mode.Index = 3, "Number keys jump relative to current clip")
    app.DoPasteAction("first-index")
    Check(app.Mode.Index = 1, "A jumps to first clip without reordering")
    app.CancelPaste(true)
    app.RegisterHotkeys(), app.InstallPasteKeys()
    Check(!HasValue(app.TemporaryKeys, "$" app.Config.Get("PasteHotkey")), "Paste-mode bindings preserve global paste callback")
    app.RemovePasteKeys(), app.UnregisterHotkeys()
    app.UI.ShowSearchMode(false)
    Check(app.UI.History.SearchMode && app.UI.History.List.GetNext() = 1, "Search-paste mode works without holding modifier")
    app.UI.History.Search.Value := "relative", app.UI.RefreshHistory()
    Check(app.UI.History.Rows.Length = 2, "Search-paste filtering updates selection")
    app.UI.ShowHistory(false, false), app.UI.History.Search.Value := "", app.UI.History.Scope.Choose(2), app.UI.RefreshHistory()
    Check(app.UI.History.Scopes[2].Channel = -1 && app.UI.History.Rows.Length >= 3, "Combined channel view is selectable")
    app.UI.ShowSettings(false)
    Check(app.UI.Settings.Controls.Has("RememberFormat") && app.UI.Settings.Controls.Has("StoreImages") && app.UI.Settings.Controls.Has("OneTimeHotkey"), "Settings exposes restored controls")
    app.UI.ShowHeld(rich, 0, false)
    cachedSnapshot := app.LastSnapshot
    app.UI.HeldFormats(app.UI.Held, false)
    Check(app.LastSnapshot = cachedSnapshot, "Inspecting held formats leaves live clipboard cache intact")
    app.UI.Held.Edit.Value := "new from editor"
    app.UI.HoldResult(app.UI.Held, "save")
    Check(store.List(0, false, "new from editor").Length = 1, "New Clip saves text into active channel")
    beforeCount := store.List(-1).Length
    app.CompleteSelection(rich, {Action: "hold", Target: 0})
    Check(store.List(-1).Length = beforeCount && app.HeldSnapshot.Text = rich.Text, "Fresh Hold capture stays outside channel history")
    key := app.Edits.Open(richId, false), editPath := app.Edits.Sessions[key].Path
    writer := FileOpen(editPath, "w", "UTF-8"), writer.Write("edited Ω"), writer.Close()
    Check(app.Edits.Commit(key) && store.Snapshot(richId).Text = "edited Ω", "External text editor save reimports clip")
    Check(!app.Edits.Commit(key), "Unchanged external editor file does not rewrite archive")
    app.Edits.Finish(key)
    imageId := app.AddSnapshot(image), imageKey := app.Edits.Open(imageId, false)
    Check(CJImage.Thumbnail(MakeImage(0xFF00FF00), app.Edits.Sessions[imageKey].Path, true), "External image workspace can be saved")
    Check(app.Edits.Commit(imageKey) && store.Snapshot(imageId).Kind = "image", "External image editor reimports saved image")
    app.Edits.Finish(imageKey)
    app.UI.ShowPreview(richId, false), app.UI.PreviewState.Query.Value := "Ω"
    Check(app.UI.FindPreview(), "Native preview Find selects matching text")
    app.UI.ShowPreview(imageId, false)
    Check(app.UI.PreviewState.Dimensions.Width = 2, "Image preview uses full saved image")
    app.UI.ShowPasteHelp(false)
    Check(app.UI.Windows.Has("paste-help"), "F1 help contains current configured keys")
    app.UI.ShowSwapChannels(false)
    swapUI := app.UI.ShowSwapClips(richId, false)
    Check(swapUI.Rows.Length > 0, "Cross-channel swap is exposed in native UI")
    textPath := temporary "\file Ω.txt", FileAppend("file content Ω", textPath, "UTF-8")
    secondPath := temporary "\second.txt", FileAppend("second", secondPath)
    paths := app.UseFiles("copy-file-path", [textPath, secondPath])
    Check(paths.Text = textPath "`r`n" secondPath, "Explorer action copies multiple selected paths")
    Check(app.UseFiles("copy-folder-path", [], temporary).Text = temporary, "Explorer action copies active folder")
    Check(app.UseFiles("copy-file-data", [textPath]).Text = "file content Ω", "File data action reads non-image Unicode text")
    Check(CJExplorer.Paths(CJSnapshot.FromText(textPath "`r`n" secondPath)).Length = 2, "Standard file-list fallback resolves selected paths")
    app.ExplorerProvider := (hwnd) => {Paths: [textPath], Folder: temporary}
    app.StartSelection("copy-file-data")
    Check(A_Clipboard = "file content Ω", "Explorer provider integrates directly without a file picker")
    startup := temporary "\startup", DirCreate(startup)
    link := CJSystem.Startup(root, true, false, A_AhkPath, startup)
    FileGetShortcut(link, &target, &working, &arguments)
    Check(target = A_AhkPath && InStr(arguments, "Clipjump.ahk"), "Startup shortcut uses bundled source runtime")
    CJSystem.Startup(root, false, false, A_AhkPath, startup)
    Check(!FileExist(link), "Startup toggle removes its own shortcut")
    Check(CJUpdates.Compare("13.0.0-beta.10", "13.0.0-beta.2") > 0, "Update comparison orders prerelease numbers numerically")
    Check(CJUpdates.Compare("13.0.0", "13.0.0-beta.99") > 0, "Stable release ranks above prerelease")
    Check(CJUpdates.Latest('[{"tag_name":"v13.0.0-beta.2"},{"tag_name":"v13.0.0-beta.10"}]').Version = "13.0.0-beta.10", "Update checker selects newest published version")
    Throws(() => CJUpdates.Latest("invalid response"), "Update checker handles malformed response")
    for mode in ["fast", "slow"] {
        UpdateDone := false
        updater := CJUpdates(RecordUpdate, root, temporary "\" mode)
        updater.Worker := A_ScriptDir "\UpdateFixture.ahk"
        updater.Deadline := mode = "slow" ? 200 : 3000
        started := A_TickCount, updater.Check()
        Check(A_TickCount - started < 500, "Update request does not block UI: " mode)
        deadline := A_TickCount + 4500
        while !IsObject(UpdateDone) && A_TickCount < deadline
            Sleep(20)
        Check(IsObject(UpdateDone) && (mode = "fast" ? UpdateDone.HasOwnProp("Version") : UpdateDone.HasOwnProp("Error")), "Update completion or timeout is reported: " mode)
        Check(!updater.Handle && !FileExist(updater.Output), "Update worker and response file are cleaned: " mode)
        updater.Cancel()
    }
    for language in ["english", "german", "Nederlands", "PortugueseBR", "Russian", "swedish", "简体中文"] {
        app.Config.Set("Language", language), app.Config.LoadLanguage()
        Check(app.Config.Labels.Has("Retain last-used paste format") && app.Config.Labels.Has("Default channel limit (0 = unlimited)"), "Language catalog contains feature settings: " language)
        canonical := CJLabels.Read(root "\languages-v2\english.txt"), translated := CJLabels.Read(root "\languages-v2\" language ".txt"), complete := true
        for key, value in canonical
            if !translated.Has(key) || translated[key] = ""
                complete := false
        Check(complete, "Language catalog covers every v2 label: " language)
    }
    Check(app.Config.L("Plain text") = "纯文本", "Unicode language filename loads Chinese labels")
    Check(store.Snapshot(richId).Text = "edited Ω", "Localization leaves clipboard content unchanged")
    app.Config.Set("Language", "german"), app.Config.LoadLanguage()
    Check(app.Config.L("Retain last-used paste format") != "Retain last-used paste format", "New controls translate beyond legacy labels")
    app.Config.Set("Language", "english"), app.Config.LoadLanguage()
    app.Shutdown(), app := false, store := false
    session := MakeApp("session")
    session.Config.Set("KeepSession", 0)
    session.AddSnapshot(CJSnapshot.FromText("session default"))
    channel := session.Store.AddChannel("Retained"), kept := session.AddSnapshot(CJSnapshot.FromText("other channel"), channel)
    session.Shutdown()
    session := MakeApp("session")
    Check(!session.Store.List(0).Length && session.Store.List(channel)[1].id = kept, "Session-only default channel clears while other channels persist")
    Check(session.Store.List(0, true, "session default").Length = 1, "Session retention option does not delete History")
    session.Shutdown()
    migratedRoot := temporary "\migrated", DirCreate(migratedRoot)
    IniWrite(1, migratedRoot "\settings-v2.ini", "General", "Incognito")
    migrated := CJConfig(migratedRoot)
    Check(migrated.Get("IncognitoStopsCapture") = 1, "Upgrade preserves existing strict private mode")
    migrationPath := temporary "\database-migration", library := root "\runtime-v2\" (A_PtrSize = 8 ? "x64" : "x86") "\sqlite3.dll"
    migration := CJStore(migrationPath, library)
    fixedId := migration.Add(CJSnapshot.FromText("migrated fixed")), laterId := migration.Add(CJSnapshot.FromText("migrated later"))
    migration.Pin(fixedId, 0, true), migration.DB.Exec("ALTER TABLE memberships DROP COLUMN fixed_slot"), migration.Close()
    migration := CJStore(migrationPath, library)
    migration.Add(CJSnapshot.FromText("copy after migration"))
    Check(migration.List(0)[1].id = fixedId && migration.Snapshot(laterId).Text = "migrated later", "Beta.1 database migration retains pinned order and archive data")
    migration.Close()
} catch as err {
    Failures += 1
    FileAppend("FAIL Unhandled: " err.Message " " err.File ":" err.Line "`n" err.Stack "`n", "*")
} finally {
    if IsObject(app)
        app.Shutdown()
    if IsSet(session) && IsObject(session) && !session.Closed
        session.Shutdown()
    A_Clipboard := original
    CJImage.Stop()
    ; Only this test's generated directory is removed.
    try DirDelete(temporary, true)
}
FileAppend("RESULT " Checks " checks; " Failures " failures; features ptr=" A_PtrSize "`n", "*")
ExitApp(Failures ? 1 : 0)
MakeApp(name) {
    global root, temporary
    configuration := temporary "\" name
    DirCreate(configuration)
    return CJApp(root, configuration "\data", {ConfigRoot: configuration, Hooks: false, Sender: RecordSend})
}
MakeImage(color) {
    snapshot := CJSnapshot(), data := Buffer(56, 0)
    NumPut("UInt", 40, data), NumPut("Int", 2, data, 4), NumPut("Int", 2, data, 8), NumPut("UShort", 1, data, 12), NumPut("UShort", 32, data, 14)
    loop 4
        NumPut("UInt", color, data, 40 + (A_Index - 1) * 4)
    snapshot.Entries.Push({Id: 8, Name: "", Data: data})
    return snapshot
}
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
RecordSend(keys) {
    global Sent
    Sent.Push(keys)
}
RecordUpdate(value) {
    global UpdateDone
    UpdateDone := value
}
HasValue(items, value) {
    for item in items
        if item = value
            return true
    return false
}
