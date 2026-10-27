#Requires AutoHotkey v2.0.31+
class CJApp extends CJAppBase {
    __New(root, dataDirectory := "", options := false) {
        this.CopyIntent := false, this.SkipNextCopy := false, this.SuppressUntil := 0
        this.PendingRequest := false, this.HeldSnapshot := false, this.PitPrevious := -1
        this.ExplorerProvider := IsObject(options) && options.HasOwnProp("ExplorerProvider") ? options.ExplorerProvider : ObjBindMethod(CJExplorer, "Resolve")
        super.__New(root, dataDirectory, options)
        this.Store.ThumbnailQuality := this.Config.Get("ThumbnailQuality")
        if !this.Config.Get("KeepSession")
            this.Store.Clear(0)
        this.Config.Save()
        this.Edits := CJEdits(this)
        this.Updater := CJUpdates(ObjBindMethod(this, "UpdatesResult"), root, this.Config.Data "\updates", A_AhkPath)
        this.MaintenanceTimer := ObjBindMethod(this, "Maintenance")
        this.LastTrim := A_TickCount
        if this.HooksEnabled {
            this.ApplySystemSettings(false)
            SetTimer(this.MaintenanceTimer, 750)
        }
    }
    StrictPrivate() => this.Config.Get("Incognito") && this.Config.Get("IncognitoStopsCapture")
    ExternalTarget() {
        hwnd := WinExist("A")
        if hwnd {
            try {
                className := WinGetClass("ahk_id " hwnd)
                if WinGetPID("ahk_id " hwnd) != DllCall("GetCurrentProcessId") && !RegExMatch(className, "^(?:Shell_(?:Secondary)?TrayWnd|NotifyIconOverflowWindow|#32768)$")
                    this.LastTarget := hwnd
            }
        }
        return this.LastTarget && WinExist("ahk_id " this.LastTarget) ? this.LastTarget : 0
    }
    InitialFormat() {
        id := this.Config.Get("RememberFormat") && this.Config.Get("LastFormat") != "" ? this.Config.Get("LastFormat") : this.Config.Get("DefaultFormat")
        return this.Plugins.Items.Has(id) && this.Plugins.Items[id].Kind = "format" ? id : "none"
    }
    RememberFormat(id) {
        if this.Plugins.Items.Has(id) && this.Plugins.Items[id].Kind = "format"
            this.Config.Set("LastFormat", id)
    }
    RegisterHotkeys() {
        this.UnregisterHotkeys()
        actions := Map("HistoryHotkey", "history", "ActionHotkey", "actions", "ChannelsHotkey", "channels", "PlainHotkey", "plain", "PitSwapHotkey", "pitswap", "OneTimeHotkey", "one-time", "SystemCopyHotkey", "system-copy", "SystemCutHotkey", "system-cut", "HoldHotkey", "hold", "CopyFilesHotkey", "copy-file-path", "CopyFolderHotkey", "copy-folder-path", "CopyDataHotkey", "copy-file-data", "PluginHotkey", "plugins")
        seen := Map(), paste := this.Config.Get("PasteHotkey")
        if paste = "" || (!InStr(paste, "^") && !InStr(paste, "#"))
            throw Error("Paste mode needs a Ctrl or Windows modifier.")
        this.ReleaseKey := InStr(paste, "^") ? "Ctrl" : "LWin"
        this.PastePrefix := InStr(paste, "^") ? "^" : "#"
        this.BindKey("$" paste, (*) => this.Guard(ObjBindMethod(this, "BeginPaste"))), seen[StrLower(paste)] := true
        for name, action in actions {
            key := this.Config.Get(name)
            if key = ""
                continue
            if seen.Has(StrLower(key)) || RegExMatch(key, "i)^\^[cx]$") || (this.Config.Get("WinCopyCut") && RegExMatch(key, "i)^#[cx]$"))
                throw Error("Each shortcut must have a different key combination.")
            this.BindKey("$" key, ObjBindMethod(this, "MenuAction", action))
            seen[StrLower(key)] := true
        }
        this.ObserveCopyKeys()
    }
    ObserveCopyKeys() {
        this.BindKey("~$^c", ObjBindMethod(this, "CopyObserved"))
        this.BindKey("~$^x", ObjBindMethod(this, "CopyObserved"))
        if this.Config.Get("WinCopyCut") {
            this.BindKey("$#c", ObjBindMethod(this, "WinCopy", false))
            this.BindKey("$#x", ObjBindMethod(this, "WinCopy", true))
        }
    }
    CopyObserved(*) {
        if this.Mode
            this.CancelPaste(false)
        this.PendingPlain := false
        if !this.Config.Get("WinCopyCut")
            this.ArmCopy()
    }
    ArmCopy() {
        pid := 0
        try pid := WinGetPID("A")
        this.CopyIntent := {At: A_TickCount, Until: A_TickCount + 2000, Consumed: false, PID: pid}
        this.SuppressUntil := 0
    }
    WinCopy(cut, *) {
        this.ArmCopy()
        this.Sender.Call(cut ? "^x" : "^c")
    }
    ManualAllowed(pid := 0) {
        if !this.Config.Get("ManualCaptureOnly") && !this.Config.Get("WinCopyCut")
            return true
        if !IsObject(this.CopyIntent) || A_TickCount > this.CopyIntent.Until
            return false
        if pid && this.CopyIntent.PID && pid != this.CopyIntent.PID
            return false
        if !this.CopyIntent.Consumed {
            this.CopyIntent.Consumed := true
            this.CopyIntent.Until := A_TickCount + 250
        }
        return true
    }
    ClipboardChanged(kind) {
        if this.Closed || this.BlockCount || CJClipboard.Sequence() = this.OwnSequence || !kind
            return
        if this.Mode
            this.CancelPaste(false)
        if IsObject(this.PendingRequest) {
            if this.PendingRequest.Action = "paste-ready" && CJClipboard.Sequence() != this.PendingRequest.Before {
                this.PendingRequest := false, this.Job.Cancel()
                this.Tip(this.Config.L("The clipboard changed. Paste was canceled."))
            } else {
                if CJClipboard.Sequence() != this.PendingRequest.Before
                    this.QueueCapture(true)
                return
            }
        }
        this.PendingPlain := false
        if this.SkipNextCopy {
            this.SkipNextCopy := false, this.SuppressUntil := A_TickCount + 250
            this.Job.Cancel()
            return
        }
        if A_TickCount < this.SuppressUntil || !this.Config.Get("Monitoring") || this.StrictPrivate()
            return
        source := CJClipboard.Source()
        if !this.Config.Ignored(source.Process, source.Class) && this.ManualAllowed(source.Pid)
            this.QueueCapture(false)
    }
    QueueCapture(forced := false) {
        if this.StrictPrivate()
            return false
        this.ForcedCapture := forced
        this.Job.Queue(this.Channel)
        SetTimer(this.CaptureTimer, 40)
        return true
    }
    CapturePoll() {
        if this.Closed || this.CaptureBusy
            return
        if !this.Job.Pending {
            SetTimer(this.CaptureTimer, 0)
            return
        }
        if this.Mode || (!this.ForcedCapture && !this.Config.Get("Monitoring")) || this.StrictPrivate() || this.Job.Channel != this.Channel {
            this.Job.Cancel(), this.PendingRequest := false
            SetTimer(this.CaptureTimer, 0)
            return
        }
        status := this.Job.Poll()
        if status = "waiting"
            return
        SetTimer(this.CaptureTimer, 0)
        if status != "ready" {
            this.PendingPlain := false, this.PendingRequest := false
            return
        }
        sequence := this.Job.Sequence, channel := this.Job.Channel
        try snapshot := CJSnapshot.Load(this.Job.Prefix ".cjc")
        catch {
            this.Job.Cancel(), this.PendingRequest := false
            return
        }
        this.Job.Cancel()
        if CJClipboard.Sequence() != sequence
            return
        this.CaptureBusy := true
        try {
            if IsObject(this.PendingRequest) {
                request := this.PendingRequest, this.PendingRequest := false
                this.CompleteSelection(snapshot, request)
                return
            }
            metadata := this.Store.Channel(channel)
            if metadata.protected && MsgBox(this.Config.L("Store this clip in the protected channel?") "`n" metadata.name, "Clipjump Modern", "YesNo Icon?") != "Yes"
                return
            id := this.AddSnapshot(snapshot, channel)
            this.LastSnapshot := snapshot, this.LastSequence := sequence, this.LastId := id
            if this.Config.Get("CopyMessage")
                this.Tip(this.Config.L("Transferred to Clipjump") " {" metadata.name "}", 600)
            if this.Config.Get("CopyBeep")
                SoundBeep(this.Config.Get("BeepFrequency"), 65)
            if IsObject(this.PendingPlain) && this.PendingPlain.Sequence = sequence {
                target := this.PendingPlain.Target, this.PendingPlain := false
                if snapshot.Text != "" && WinExist("A") = target
                    this.PasteSnapshot(CJSnapshot.FromText(snapshot.Text), target)
            }
            this.UI.RefreshHistory()
        } catch as err
            this.Guard(() => this.Raise(err))
        finally {
            this.CaptureBusy := false
            if this.Job.Pending
                SetTimer(this.CaptureTimer, 40)
        }
    }
    AddSnapshot(snapshot, channel := -1) {
        if channel < 0
            channel := this.Channel
        metadata := this.Store.Channel(channel)
        archive := !metadata.no_history && !this.Config.Get("Incognito") && this.Config.Get("HistoryDays") > 0 && (snapshot.Kind != "image" || this.Config.Get("StoreImages"))
        id := this.Store.Add(snapshot, channel, archive, this.Config.Get("Deduplicate"))
        maximum := this.Config.Get("MaximumChannelClips"), threshold := this.Config.Get("ClipThreshold")
        if maximum > 0 && (channel = 0 || this.Config.Get("LimitAllChannels")) {
            count := this.Store.DB.Query("SELECT COUNT(*) AS count FROM memberships WHERE channel_id=?1 AND pinned=0", [channel])[1].count
            if count >= maximum + threshold
                this.Store.Compact(channel, maximum)
        }
        return id
    }
    BeginPaste(forceNormal := false, *) {
        this.SkipNextCopy := false
        if this.Mode
            return this.Cycle(1)
        if IsObject(this.PendingRequest) && this.PendingRequest.Action = "paste-ready" && this.PendingRequest.Before = CJClipboard.Sequence() {
            this.PendingRequest.Cycles += 1
            return
        }
        if !forceNormal && this.Config.Get("StartSearch") && this.Config.Get("Monitoring") && !this.StrictPrivate() && !this.ActiveIgnored()
            return this.UI.ShowSearchMode()
        if !this.ActiveIgnored() && this.Config.Get("Monitoring") && !this.StrictPrivate() && this.InitialFormat() != "none" && (this.LastSequence != CJClipboard.Sequence() || !IsObject(this.LastSnapshot)) {
            this.PendingRequest := {Action: "paste-ready", Target: this.ExternalTarget(), Before: CJClipboard.Sequence(), At: A_TickCount, Format: this.InitialFormat(), Cycles: 0}
            this.QueueCapture(true)
            return
        }
        if this.ActiveIgnored() || !this.Config.Get("Monitoring") || this.StrictPrivate() || this.LastSequence != CJClipboard.Sequence() || !IsObject(this.LastSnapshot) {
            this.Sender.Call("^v")
            return
        }
        records := this.Store.List(this.Channel, false, "", 100000)
        if !records.Length {
            this.Sender.Call("^v")
            return
        }
        index := 1
        for position, record in records
            if record.id = this.LastId
                index := position
        if this.Config.Get("PreservePosition") && this.LastSelectedId
            for position, record in records
                if record.id = this.LastSelectedId
                    index := position
        this.Mode := {Items: records, Index: index, Target: this.ExternalTarget(), Original: this.LastSnapshot, OriginalId: this.LastId, SelectedSnapshot: this.LastSnapshot, RawSnapshot: this.LastSnapshot, AppliedFormat: "none", StartSequence: CJClipboard.Sequence(), CurrentSequence: CJClipboard.Sequence(), Changed: false, Native: records[index].id = this.LastId, Format: this.InitialFormat(), MultiPaste: false, Action: "paste", Direction: 1}
        if !this.Mode.Native
            this.Select(index)
        this.Job.Cancel()
        this.InstallPasteKeys(), this.ShowPasteTip()
        SetTimer(this.PasteTimer, 25)
    }
    InstallPasteKeys() {
        if !this.HooksEnabled
            return
        bindings := Map("NextKey", "next", "PreviousKey", "previous", "ModeKey", "cycle-action", "FormatKey", "format", "PlainKey", "plain", "SearchKey", "search", "ClipboardKey", "clipboard", "FirstKey", "first-index", "FrontKey", "first", "PinKey", "pin", "TagKey", "tag", "EditKey", "hold", "ExportKey", "export", "HelpKey", "help")
        for name, action in bindings {
            shortcut := "$" this.PastePrefix this.Config.Get(name)
            if StrLower(shortcut) = StrLower("$" this.Config.Get("PasteHotkey"))
                continue
            Hotkey(shortcut, ObjBindMethod(this, "PasteAction", action), "On")
            this.TemporaryKeys.Push(shortcut)
        }
        for key, action in Map("Up", "up-channel", "Down", "down-channel", "Enter", "multi", "Delete", "delete", "Escape", "cancel", "Home", "cancel") {
            shortcut := "$" this.PastePrefix key
            Hotkey(shortcut, ObjBindMethod(this, "PasteAction", action), "On")
            this.TemporaryKeys.Push(shortcut)
        }
        loop 9 {
            shortcut := "$" this.PastePrefix A_Index
            Hotkey(shortcut, ObjBindMethod(this, "SelectHotkey", A_Index), "On")
            this.TemporaryKeys.Push(shortcut)
        }
    }
    SelectHotkey(distance, *) => this.Guard(ObjBindMethod(this, "RelativeSelect", distance))
    RelativeSelect(distance) {
        if this.Mode
            this.Cycle(this.Mode.Direction * distance)
    }
    Select(index) {
        super.Select(index)
        if this.Mode
            this.Mode.RawSnapshot := this.Mode.SelectedSnapshot, this.Mode.AppliedFormat := "none"
    }
    Cycle(direction) {
        if this.Mode {
            this.Mode.Direction := direction < 0 ? -1 : 1
            this.Mode.Action := "paste"
            super.Cycle(direction)
        }
    }
    DoPasteAction(action) {
        if !this.Mode
            return
        switch action {
            case "next": this.Cycle(1)
            case "multi":
                this.ApplyModeFormat(), this.Sender.Call("^v")
                this.RememberFormat(this.Mode.Format)
                this.Mode.MultiPaste := true
            case "cycle-action":
                modes := ["cancel", "delete", "move", "copy", "delete-all"], next := 1
                for index, mode in modes
                    if mode = this.Mode.Action
                        next := Mod(index, modes.Length) + 1
                this.Mode.Action := modes[next], this.ShowPasteTip()
            case "clipboard": this.CommitPaste(false)
            case "plain": this.Mode.Format := "plain", this.Mode.Action := "paste", this.ShowPasteTip()
            case "first-index": this.Select(1), this.Mode.Action := "paste"
            case "help": this.UI.ShowPasteHelp()
            case "up-channel": this.CycleChannel(1)
            case "down-channel": this.CycleChannel(-1)
            case "search": this.CancelPaste(false), this.UI.ShowSearchMode()
            case "hold":
                id := this.Mode.Items[this.Mode.Index].id
                this.CancelPaste(false), this.Edits.Open(id)
            case "first":
                id := this.Mode.Items[this.Mode.Index].id
                this.Store.ToFront(id, this.Channel)
                this.Mode.Items := this.Store.List(this.Channel, false, "", 100000)
                this.Select(1)
            default: super.DoPasteAction(action)
        }
    }
    ShowPasteTip() {
        if this.Mode && this.Config.Get("ShowPasteTip")
            this.UI.ShowOverlay(this.Mode.Items[this.Mode.Index], this.Mode.Index, this.Mode.Items.Length, this.Mode.Format)
    }
    ApplyModeFormat() {
        if !this.Mode
            return
        snapshot := this.Mode.RawSnapshot
        if this.Mode.Format = "none" {
            if this.Mode.AppliedFormat != "none" {
                this.Mode.SelectedSnapshot := snapshot
                this.Mode.CurrentSequence := this.WriteClipboard(snapshot)
                this.Mode.Changed := true, this.Mode.Native := false, this.Mode.AppliedFormat := "none"
            }
            return
        }
        ; A text default never blocks image/binary pasting or discards an image.
        if snapshot.Kind != "text" && snapshot.Kind != "files"
            return
        this.Mode.SelectedSnapshot := CJSnapshot.FromText(this.Plugins.Transform(this.Mode.Format, snapshot.Text))
        this.Mode.CurrentSequence := this.WriteClipboard(this.Mode.SelectedSnapshot)
        this.Mode.Changed := true, this.Mode.Native := false, this.Mode.AppliedFormat := this.Mode.Format
    }
    FinishPaste() {
        if !this.Mode
            return
        if CJClipboard.Sequence() != this.Mode.CurrentSequence {
            this.CancelPaste(false)
            return
        }
        if this.Mode.Target && this.HooksEnabled && WinExist("A") != this.Mode.Target {
            this.CancelPaste(true)
            return
        }
        action := this.Mode.Action, id := this.Mode.Items[this.Mode.Index].id
        if action != "paste" {
            channel := this.Channel
            this.CancelPaste(true)
            switch action {
                case "delete": this.Store.Remove(id, channel)
                case "delete-all":
                    if MsgBox(this.Config.L("Clear the clips in this view?"), "Clipjump Modern", "YesNo Icon?") = "Yes"
                        this.Store.Clear(channel)
                case "move", "copy": this.UI.ShowMove([id], channel, action = "copy")
            }
            this.UI.RefreshHistory()
            return
        }
        this.CommitPaste(true)
    }
    CommitPaste(send := true) {
        if !this.Mode || CJClipboard.Sequence() != this.Mode.CurrentSequence
            return this.CancelPaste(false)
        try {
            if !send || !this.Mode.MultiPaste
                this.ApplyModeFormat()
        }
        catch as err {
            this.CancelPaste(true)
            throw err
        }
        mode := this.Mode, this.Mode := false
        SetTimer(this.PasteTimer, 0), this.RemovePasteKeys(), this.UI.HideOverlay()
        if !send || !mode.MultiPaste
            this.RememberFormat(mode.Format)
        this.LastSelectedId := mode.Items[mode.Index].id
        this.LastSnapshot := mode.SelectedSnapshot, this.LastSequence := mode.CurrentSequence, this.LastId := this.LastSelectedId
        if send && !mode.MultiPaste {
            if this.Config.Get("ShowPastingTip")
                this.Tip(this.Config.L("Pasting..."), 500)
            this.Sender.Call("^v")
            if GetKeyState("Shift")
                this.Store.Remove(this.LastSelectedId, this.Channel)
        }
    }
    PasteIds(ids, target := 0) {
        format := this.InitialFormat()
        for index, id in ids {
            snapshot := this.Store.Snapshot(id)
            if format != "none" && (snapshot.Kind = "text" || snapshot.Kind = "files")
                snapshot := CJSnapshot.FromText(this.Plugins.Transform(format, snapshot.Text))
            if index > 1
                this.Sender.Call("{Enter}")
            if !this.PasteSnapshot(snapshot, target)
                break
            this.RememberFormat(format)
            this.LastSnapshot := snapshot, this.LastSequence := CJClipboard.Sequence(), this.LastId := id
            if index < ids.Length
                Sleep(120)
        }
    }
    PastePlain() {
        target := this.ExternalTarget()
        if IsObject(this.LastSnapshot) && this.LastSequence = CJClipboard.Sequence() {
            if this.LastSnapshot.Text = ""
                return this.Tip(this.Config.L("This clip has no text to paste."))
            return this.PasteSnapshot(CJSnapshot.FromText(this.LastSnapshot.Text), target)
        }
        if this.QueueCapture(true)
            this.PendingPlain := {Target: target, Sequence: CJClipboard.Sequence()}
    }
    ApplySettings(values) {
        previous := this.Config.Values
        CJFeatureSettings.Validate(values)
        if values["DefaultFormat"] != previous["DefaultFormat"] || values["RememberFormat"] != previous["RememberFormat"]
            values["LastFormat"] := ""
        if values["WinCopyCut"] && !previous["WinCopyCut"]
            values["PasteHotkey"] := "#v"
        else if !values["WinCopyCut"] && previous["WinCopyCut"] && values["PasteHotkey"] = "#v"
            values["PasteHotkey"] := "^v"
        this.CancelPaste(true), this.Job.Cancel()
        this.Config.Values := values
        try {
            if this.HooksEnabled {
                this.RegisterHotkeys(), this.LoadCustomizations()
                this.ApplySystemSettings(values["StartWithWindows"] != previous["StartWithWindows"])
            }
        } catch as err {
            this.Config.Values := previous
            if this.HooksEnabled
                this.RegisterHotkeys(), this.LoadCustomizations()
            throw err
        }
        this.Store.ThumbnailQuality := values["ThumbnailQuality"]
        this.Config.Save(), this.Config.LoadLanguage()
        if !values["Monitoring"] || this.StrictPrivate()
            this.LastSequence := 0
        if this.HooksEnabled
            this.BuildTray()
    }
    ApplySystemSettings(changeStartup) {
        ProcessSetPriority(this.Config.Get("ProcessPriority"))
        if changeStartup || this.Config.Get("StartWithWindows")
            CJSystem.Startup(this.Root, this.Config.Get("StartWithWindows"), A_IsCompiled, A_AhkPath)
    }
    ToggleSetting(name, explicit := "") {
        value := explicit = "" ? !this.Config.Get(name) : explicit = "on" || explicit = "1"
        this.Config.Set(name, value ? 1 : 0)
        this.Job.Cancel(), this.CancelPaste(true)
        if !this.Config.Get("Monitoring") || this.StrictPrivate()
            this.LastSequence := 0
        if this.HooksEnabled
            this.BuildTray()
    }
    PitSwap() {
        if this.PitPrevious >= 0 {
            target := this.PitPrevious, this.PitPrevious := -1
            try this.SetChannel(target)
            catch
                this.SetChannel(0)
            return
        }
        try target := this.Store.ChannelId("Pit")
        catch
            target := this.Store.AddChannel("Pit", false, true)
        if target = this.Channel
            return this.SetChannel(0)
        this.PitPrevious := this.Channel
        this.SetChannel(target)
    }
    OneTimeStop() {
        this.Job.Cancel(), this.SkipNextCopy := true
        this.Tip(this.Config.L("One Time Stop"))
    }
    StartSelection(action) {
        target := this.ExternalTarget()
        if action != "hold" {
            selection := this.ExplorerProvider.Call(target)
            if IsObject(selection) && (action = "copy-folder-path" || selection.Paths.Length)
                return this.UseFiles(action, selection.Paths, selection.Folder)
        }
        if this.StrictPrivate()
            throw Error("Capture is paused by private mode.")
        if this.HooksEnabled && target {
            WinActivate("ahk_id " target)
            if !WinWaitActive("ahk_id " target, , 1)
                throw Error("The selection window could not be activated.")
        }
        this.PendingRequest := {Action: action, Target: target, Before: CJClipboard.Sequence(), At: A_TickCount}
        this.Sender.Call("^c")
    }
    CompleteSelection(snapshot, request) {
        if request.Action = "paste-ready" {
            if this.HooksEnabled && WinExist("A") != request.Target
                return
            id := this.AddSnapshot(snapshot)
            this.LastSnapshot := snapshot, this.LastId := id, this.LastSequence := CJClipboard.Sequence()
            if this.HooksEnabled && GetKeyState(this.ReleaseKey) {
                this.BeginPaste(true)
                if this.Mode
                    this.Mode.Format := request.Format
                if this.Mode && request.Cycles
                    this.Cycle(request.Cycles)
                return
            }
            if request.Cycles {
                rows := this.Store.List(this.Channel, false, "", 100000), current := 1
                for index, row in rows
                    if row.id = id
                        current := index
                selected := rows[Mod(current - 1 + request.Cycles, rows.Length) + 1]
                snapshot := this.Store.Snapshot(selected)
                this.LastId := selected.id, this.LastSnapshot := snapshot
            }
            applies := request.Format != "none" && (snapshot.Kind = "text" || snapshot.Kind = "files")
            if applies {
                converted := CJSnapshot.FromText(this.Plugins.Transform(request.Format, snapshot.Text))
                this.PasteSnapshot(converted, request.Target)
                this.LastSnapshot := converted, this.LastSequence := CJClipboard.Sequence()
            } else if request.Cycles {
                this.PasteSnapshot(snapshot, request.Target)
                this.LastSequence := CJClipboard.Sequence()
            } else
                this.Sender.Call("^v")
            this.RememberFormat(request.Format)
        } else if request.Action = "hold" {
            this.HeldSnapshot := snapshot
            this.UI.ShowHeld(snapshot, request.Target, this.HooksEnabled)
        } else
            this.UseFiles(request.Action, CJExplorer.Paths(snapshot), "")
    }
    UseFiles(action, paths, folder := "") {
        if action = "copy-folder-path" {
            if folder = ""
                throw Error("The active folder is unavailable. Open it in File Explorer.")
            snapshot := CJSnapshot.FromText(folder)
        } else {
            if !paths.Length
                throw Error("Select one or more files in File Explorer first.")
            if action = "copy-file-data"
                snapshot := CJExplorer.Read(paths[1])
            else {
                text := ""
                for path in paths
                    text .= (text = "" ? "" : "`r`n") path
                snapshot := CJSnapshot.FromText(text)
            }
        }
        id := this.AddSnapshot(snapshot), this.WriteClipboard(snapshot)
        this.LastSnapshot := snapshot, this.LastSequence := CJClipboard.Sequence(), this.LastId := id
        return snapshot
    }
    UpdatesResult(result) {
        if result.HasOwnProp("Error")
            return MsgBox(this.Config.L("Could not check for updates.") "`n" result.Error, "Clipjump Modern", "Icon!")
        newer := CJUpdates.Compare(result.Version, CJApp.Version) > 0
        if newer {
            if MsgBox(this.Config.L("A new release is available. Open its download page?") "`n" result.Version, "Clipjump Modern", "YesNo Iconi") = "Yes"
                Run(result.URL)
        } else
            MsgBox(this.Config.L("No updates available") "`n" CJApp.Version, "Clipjump Modern", "Iconi")
    }
    Tip(text, duration := 1200) {
        if this.HooksEnabled
            super.Tip(this.Config.L(text), duration)
    }
    Maintenance() {
        if this.Closed
            return
        this.ExternalTarget()
        if IsObject(this.PendingRequest) && !this.Job.Pending && A_TickCount - this.PendingRequest.At > 3000 {
            this.PendingRequest := false
            this.Tip(this.Config.L("No selection could be copied."))
        }
        this.Edits.Poll()
        if this.Config.Get("RAMFlush") && A_TickCount - this.LastTrim > 60000
            CJSystem.TrimMemory(), this.LastTrim := A_TickCount
    }
    BuildTray() {
        menu := A_TrayMenu, menu.Delete()
        for pair in [["History", "history"], ["Channels", "channels"], ["Settings", "settings"], ["Plugins", "plugins"], ["Common Formats", "formats"], ["Hold selection", "hold"], ["One Time Stop", "one-time"], ["PitSwap", "pitswap"], ["Import v1 data…", "import-v1"]]
            menu.Add(this.Config.L(pair[1]), ObjBindMethod(this, "MenuAction", pair[2]))
        menu.Add()
        menu.Add(this.Config.L("Capture clipboard changes"), ObjBindMethod(this, "MenuAction", "monitor"))
        if this.Config.Get("Monitoring")
            menu.Check(this.Config.L("Capture clipboard changes"))
        menu.Add(this.Config.L("Incognito: no history"), ObjBindMethod(this, "MenuAction", "incognito"))
        if this.Config.Get("Incognito")
            menu.Check(this.Config.L("Incognito: no history"))
        menu.Add()
        for pair in [["Check for updates", "updates"], ["Project and compatibility notes", "project"], ["Restart", "restart"], ["Exit", "exit"]]
            menu.Add(this.Config.L(pair[1]), ObjBindMethod(this, "MenuAction", pair[2]))
        menu.Default := this.Config.L("History")
        A_IconTip := "Clipjump Modern " CJApp.Version " {" this.Store.Channel(this.Channel).name "}"
        if FileExist(this.Root "\icons\icon.ico")
            TraySetIcon(this.Root "\icons\icon.ico")
    }
    ActionMenu() {
        actionsMenu := Menu()
        for pair in [["H", "History", "history"], ["O", "Channels", "channels"], ["E", "Settings", "settings"], ["M", "Plugins", "plugins"], ["B", "Hold selection", "hold"], ["C", "Copy selected file paths", "copy-file-path"], ["X", "Copy active folder path", "copy-folder-path"], ["F", "Copy selected file data", "copy-file-data"], ["P", "PitSwap", "pitswap"], ["T", "One Time Stop", "one-time"], ["D", "Capture clipboard changes", "monitor"], ["U", "Sync clipboard", "sync"], ["I", "Incognito: no history", "incognito"], ["J", "Plain text", "plain"], ["F1", "Paste-mode shortcuts", "paste-help"]]
            actionsMenu.Add("&" pair[1] "  " this.Config.L(pair[2]), ObjBindMethod(this, "MenuAction", pair[3]))
        loop 10 {
            id := A_Index - 1
            try channel := this.Store.Channel(id)
            catch
                continue
            actionsMenu.Add("&" id "  " channel.name, ObjBindMethod(this, "MenuAction", "channel:" id))
        }
        actionsMenu.Show()
    }
    Action(action, *) {
        parts := StrSplit(action, ":", , 2), command := StrLower(parts[1])
        switch command {
            case "one-time": this.OneTimeStop()
            case "system-copy", "system-cut": this.OneTimeStop(), this.Sender.Call(command = "system-cut" ? "^x" : "^c")
            case "pitswap": this.PitSwap()
            case "hold", "copy-file-path", "copy-folder-path", "copy-file-data": this.StartSelection(command)
            case "updates": this.Updater.Check()
            case "paste-help": this.UI.ShowPasteHelp()
            case "new-clip": this.UI.NewClip()
            case "external-edit": this.UI.HistoryAction("external-edit")
            case "format":
                id := parts.Length > 1 ? parts[2] : "none"
                if !this.Plugins.Items.Has(id) || this.Plugins.Items[id].Kind != "format"
                    throw Error("Unknown paste format.")
                this.Config.Set("DefaultFormat", id), this.Config.Set("LastFormat", "")
            default: return super.Action(action)
        }
        return true
    }
    Shutdown(*) {
        if this.Closed
            return
        if this.HasOwnProp("MaintenanceTimer")
            SetTimer(this.MaintenanceTimer, 0)
        if this.HasOwnProp("Updater")
            this.Updater.Cancel()
        if !this.Config.Get("KeepSession")
            this.Store.Clear(0)
        super.Shutdown()
    }
}
