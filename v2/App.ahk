#Requires AutoHotkey v2.0.31+
class CJApp {
    static Version := "13.0.0-beta.1"
    static ProjectPage := "https://github.com/ariadne-coil/Clipjump-"

    __New(root, dataDirectory := "", options := false) {
        this.Root := root, this.Closed := false
        configRoot := IsObject(options) && options.HasOwnProp("ConfigRoot") ? options.ConfigRoot : root
        this.Config := CJConfig(configRoot, dataDirectory)
        architecture := A_PtrSize = 8 ? "x64" : "x86"
        this.Library := root "\runtime-v2\" architecture "\sqlite3.dll"
        if !FileExist(this.Library)
            this.Library := root "\runtime\" architecture "\sqlite3.dll"
        this.Store := CJStore(this.Config.Data, this.Library)
        this.Channel := this.Config.Get("Channel")
        try this.Store.Channel(this.Channel)
        catch
            this.Channel := 0
        this.HooksEnabled := !IsObject(options) || !options.HasOwnProp("Hooks") || options.Hooks
        this.Sender := IsObject(options) && options.HasOwnProp("Sender") ? options.Sender : (keys) => SendEvent(keys)
        this.Hotkeys := Map(), this.Hotstrings := [], this.TemporaryKeys := []
        this.ReleaseKey := InStr(this.Config.Get("PasteHotkey"), "^") ? "Ctrl" : "LWin"
        this.PastePrefix := this.ReleaseKey = "Ctrl" ? "^" : "#"
        this.LastSnapshot := false, this.LastSequence := 0, this.LastId := 0, this.OwnSequence := 0
        this.LastSelectedId := 0, this.Mode := false, this.BlockCount := 0, this.CaptureBusy := false
        this.PendingPlain := false, this.LastTarget := 0
        this.Plugins := CJPlugins(this), this.UI := CJUI(this)
        if !this.Plugins.Items.Has(this.Config.Get("DefaultFormat"))
            this.Config.Set("DefaultFormat", "none", false)
        worker := A_IsCompiled ? root "\ClipjumpCapture.exe" : root "\v2\CaptureWorker.ahk"
        if A_IsCompiled && !FileExist(worker)
            throw Error("ClipjumpCapture.exe is missing. Extract the complete portable ZIP before running Clipjump.exe.")
        this.Job := CJCaptureJob(this.Config.Data "\capture", A_AhkPath, worker)
        this.CaptureTimer := ObjBindMethod(this, "CapturePoll")
        this.PasteTimer := ObjBindMethod(this, "CheckPasteRelease")
        this.ClipboardCallback := ObjBindMethod(this, "ClipboardChanged")
        this.ApiCallback := ObjBindMethod(this, "ReceiveAPI")
        this.Store.Expire(this.Config.Get("HistoryDays"))
        if !FileExist(this.Config.File)
            this.Config.Save()
        if this.HooksEnabled {
            this.RegisterHotkeys()
            this.LoadCustomizations()
            this.BuildTray()
            OnClipboardChange(this.ClipboardCallback)
            OnMessage(0x4A, this.ApiCallback)
        }
    }

    Guard(callback, notify := true) {
        try return callback.Call()
        catch as err {
            try FileAppend(CJNow() " " Type(err) " " err.File ":" err.Line "`r`n", this.Config.Data "\diagnostics.log", "UTF-8-RAW")
            if notify
                MsgBox(err.Message, "Clipjump Modern", "Icon!")
            return false
        }
    }

    BuildTray() {
        menu := A_TrayMenu
        menu.Delete()
        commands := [["&History`t" this.Config.Get("HistoryHotkey"), "history"], ["&Channels`t" this.Config.Get("ChannelsHotkey"), "channels"], ["&Settings", "settings"], ["&Plugins", "plugins"], ["Common &Formats", "formats"], ["&Hold / edit current clip", "hold"], ["Import &v1 data…", "import-v1"]]
        for command in commands
            menu.Add(command[1], ObjBindMethod(this, "MenuAction", command[2]))
        menu.Add()
        menu.Add("Capture clipboard changes", ObjBindMethod(this, "MenuAction", "monitor"))
        if this.Config.Get("Monitoring")
            menu.Check("Capture clipboard changes")
        menu.Add("Private mode", ObjBindMethod(this, "MenuAction", "incognito"))
        if this.Config.Get("Incognito")
            menu.Check("Private mode")
        menu.Add()
        menu.Add("Project and compatibility notes", ObjBindMethod(this, "MenuAction", "project"))
        menu.Add("Restart", ObjBindMethod(this, "MenuAction", "restart"))
        menu.Add("Exit", ObjBindMethod(this, "MenuAction", "exit"))
        menu.Default := commands[1][1]
        A_IconTip := "Clipjump Modern v2 {" this.Store.Channel(this.Channel).name "}"
        if FileExist(this.Root "\icons\icon.ico")
            TraySetIcon(this.Root "\icons\icon.ico")
    }

    MenuAction(action, *) => this.Guard(ObjBindMethod(this, "Action", action))

    RegisterHotkeys() {
        this.UnregisterHotkeys()
        actions := Map("HistoryHotkey", "history", "ActionHotkey", "actions", "ChannelsHotkey", "channels", "PlainHotkey", "plain")
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
            if seen.Has(StrLower(key))
                throw Error("Each shortcut must have a different key combination.")
            this.BindKey("$" key, ObjBindMethod(this, "MenuAction", action))
            seen[StrLower(key)] := true
        }
        this.ObserveCopyKeys()
    }

    BindKey(key, callback) {
        Hotkey(key, callback, "On")
        this.Hotkeys[key] := callback
    }
    ObserveCopyKeys() {
        ; The application always receives its original copy/cut keystrokes.
        this.BindKey("~$^c", ObjBindMethod(this, "CopyObserved"))
        this.BindKey("~$^x", ObjBindMethod(this, "CopyObserved"))
    }
    CopyObserved(*) {
        if !this.Mode
            this.PendingPlain := false
    }
    UnregisterHotkeys() {
        for key in this.Hotkeys
            try Hotkey(key, "Off")
        this.Hotkeys.Clear()
        for trigger in this.Hotstrings
            try Hotstring(trigger, "Off")
        this.Hotstrings := []
    }

    LoadCustomizations() {
        if FileExist(this.Config.CustomFile) {
            body := IniRead(this.Config.CustomFile, "Hotkeys", , "")
            for pair in this.IniPairs(body) {
                callback := ObjBindMethod(this, "MenuAction", pair.Value)
                this.BindKey("$" pair.Key, callback)
            }
            body := IniRead(this.Config.CustomFile, "AutoRun", , "")
            for pair in this.IniPairs(body)
                this.Guard(ObjBindMethod(this, "Action", pair.Value))
        }
        if FileExist(this.Config.HotPasteFile) {
            Hotstring("EndChars", "`n `t")
            for section in ["Text", "Clips"] {
                body := IniRead(this.Config.HotPasteFile, section, , "")
                for pair in this.IniPairs(body) {
                    if !RegExMatch(pair.Key, "^[\w.-]{1,80}$")
                        continue
                    action := section = "Text" ? "text:" pair.Value : "paste:" pair.Value
                    trigger := ":XO:" pair.Key
                    Hotstring(trigger, ObjBindMethod(this, "HotPaste", action))
                    this.Hotstrings.Push(trigger)
                }
            }
        }
    }
    IniPairs(body) {
        pairs := []
        for line in StrSplit(body, "`n", "`r") {
            line := Trim(line)
            if line = "" || SubStr(line, 1, 1) = ";" || !InStr(line, "=")
                continue
            position := InStr(line, "=")
            pairs.Push({Key: Trim(SubStr(line, 1, position - 1)), Value: Trim(SubStr(line, position + 1))})
        }
        return pairs
    }
    HotPaste(action, *) {
        this.Guard(ObjBindMethod(this, "Action", action))
        if A_EndChar != ""
            SendText(A_EndChar)
    }

    ApplySettings(values) {
        if values["HistoryDays"] < 0 || values["HistoryDays"] > 36500 || values["MaximumChannelClips"] < 1 || values["MaximumChannelClips"] > 100000
            throw Error("History days must be 0–36500; channel capacity must be 1–100000.")
        previous := this.Config.Values
        this.CancelPaste(false), this.Job.Cancel()
        this.Config.Values := values
        try {
            if this.HooksEnabled {
                this.RegisterHotkeys()
                this.LoadCustomizations()
            }
        } catch as err {
            this.Config.Values := previous
            if this.HooksEnabled {
                this.RegisterHotkeys()
                this.LoadCustomizations()
            }
            throw err
        }
        this.Config.Save(), this.Config.LoadLanguage()
        if this.Config.Get("Incognito") || !this.Config.Get("Monitoring")
            this.LastSequence := 0
        if this.HooksEnabled
            this.BuildTray()
    }
    ReloadConfiguration() {
        fresh := CJConfig(this.Config.Root, this.Config.Data)
        this.ApplySettings(fresh.Values)
    }

    ActiveIgnored() {
        try return this.Config.Ignored(WinGetProcessName("A"), WinGetClass("A"))
        catch
            return false
    }

    ClipboardChanged(kind) {
        if this.Closed || this.BlockCount || CJClipboard.Sequence() = this.OwnSequence
            return
        if this.Mode
            this.CancelPaste(false)
        this.PendingPlain := false
        if !kind || !this.Config.Get("Monitoring") || this.Config.Get("Incognito")
            return
        source := CJClipboard.Source()
        if this.Config.Ignored(source.Process, source.Class)
            return
        this.QueueCapture(false)
    }
    QueueCapture(forced := false) {
        if this.Config.Get("Incognito")
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
        if this.Mode || (!this.ForcedCapture && !this.Config.Get("Monitoring")) || this.Config.Get("Incognito") || this.Job.Channel != this.Channel {
            this.Job.Cancel()
            SetTimer(this.CaptureTimer, 0)
            return
        }
        status := this.Job.Poll()
        if status = "waiting"
            return
        SetTimer(this.CaptureTimer, 0)
        if status != "ready" {
            this.PendingPlain := false
            return
        }
        sequence := this.Job.Sequence, channel := this.Job.Channel
        try snapshot := CJSnapshot.Load(this.Job.Prefix ".cjc")
        catch {
            this.Job.Cancel()
            return
        }
        this.Job.Cancel()
        if CJClipboard.Sequence() != sequence
            return
        this.CaptureBusy := true
        try {
            metadata := this.Store.Channel(channel)
            if metadata.protected && MsgBox("Store this clip in the protected channel '" metadata.name "'?", "Clipjump Modern", "YesNo Icon?") != "Yes"
                return
            id := this.AddSnapshot(snapshot, channel)
            this.LastSnapshot := snapshot, this.LastSequence := sequence, this.LastId := id
            if this.Config.Get("CopyMessage")
                this.Tip("Transferred to Clipjump {" metadata.name "}", 600)
            if IsObject(this.PendingPlain) && this.PendingPlain.Sequence = sequence {
                target := this.PendingPlain.Target
                this.PendingPlain := false
                if WinExist("A") = target
                    this.PasteSnapshot(CJSnapshot.FromText(RTrim(snapshot.Text, "`r`n")), target)
            }
            this.UI.RefreshHistory()
        } catch as err {
            this.Guard(() => this.Raise(err))
        } finally {
            this.CaptureBusy := false
            if this.Job.Pending
                SetTimer(this.CaptureTimer, 40)
        }
    }
    Raise(err) {
        throw err
    }
    AddSnapshot(snapshot, channel := -1) {
        if channel < 0
            channel := this.Channel
        metadata := this.Store.Channel(channel)
        archive := !metadata.no_history && !this.Config.Get("Incognito") && this.Config.Get("HistoryDays") > 0
        id := this.Store.Add(snapshot, channel, archive, this.Config.Get("Deduplicate"))
        this.Store.Compact(channel, this.Config.Get("MaximumChannelClips"))
        return id
    }

    WriteClipboard(snapshot) {
        previous := A_IsCritical
        Critical("On")
        this.BlockCount += 1
        try {
            A_Clipboard := snapshot.Native()
            this.OwnSequence := CJClipboard.Sequence()
            return this.OwnSequence
        } finally {
            this.BlockCount -= 1
            Critical(previous)
        }
    }
    CurrentText() => IsObject(this.LastSnapshot) && this.LastSequence = CJClipboard.Sequence() ? this.LastSnapshot.Text : ""
    CopyClip(id) => this.WriteClipboard(this.Store.Snapshot(id))

    BeginPaste(*) {
        if this.Mode
            return this.Cycle(1)
        if this.ActiveIgnored() || !this.Config.Get("Monitoring") || this.Config.Get("Incognito") || this.LastSequence != CJClipboard.Sequence() || !IsObject(this.LastSnapshot) {
            this.Sender.Call("^v")
            return
        }
        records := this.Store.List(this.Channel)
        if !records.Length {
            this.Sender.Call("^v")
            return
        }
        index := 1
        for position, record in records
            if record.id = this.LastId
                index := position
        if this.Config.Get("PreservePosition") && this.LastSelectedId {
            for position, record in records
                if record.id = this.LastSelectedId
                    index := position
        }
        this.Mode := {Items: records, Index: index, Target: this.ExternalTarget(), Original: this.LastSnapshot, OriginalId: this.LastId, SelectedSnapshot: this.LastSnapshot, StartSequence: CJClipboard.Sequence(), CurrentSequence: CJClipboard.Sequence(), Changed: false, Native: records[index].id = this.LastId, Format: this.Config.Get("DefaultFormat"), MultiPaste: false}
        if !this.Mode.Native
            this.Select(index)
        this.Job.Cancel()
        this.InstallPasteKeys()
        this.ShowPasteTip()
        SetTimer(this.PasteTimer, 25)
    }
    InstallPasteKeys() {
        if !this.HooksEnabled
            return
        prefix := this.PastePrefix
        commands := Map("c", "previous", "x", "cancel", "z", "format", "f", "search", "Up", "up-channel", "Down", "down-channel", "Space", "pin", "q", "first", "t", "tag", "h", "hold", "e", "export", "Enter", "multi", "Delete", "delete")
        for key, action in commands {
            shortcut := "$" prefix key
            Hotkey(shortcut, ObjBindMethod(this, "PasteAction", action), "On")
            this.TemporaryKeys.Push(shortcut)
        }
        loop 9 {
            shortcut := "$" prefix A_Index
            Hotkey(shortcut, ObjBindMethod(this, "SelectHotkey", A_Index), "On")
            this.TemporaryKeys.Push(shortcut)
        }
    }
    RemovePasteKeys() {
        for key in this.TemporaryKeys
            try Hotkey(key, "Off")
        this.TemporaryKeys := []
        if this.HooksEnabled && !this.Closed
            this.ObserveCopyKeys()
    }
    SelectHotkey(index, *) => this.Guard(ObjBindMethod(this, "Select", index))
    PasteAction(action, *) => this.Guard(ObjBindMethod(this, "DoPasteAction", action))
    DoPasteAction(action) {
        if !this.Mode
            return
        id := this.Mode.Items[this.Mode.Index].id
        switch action {
            case "previous": this.Cycle(-1)
            case "cancel": this.CancelPaste(true)
            case "format":
                formats := this.Plugins.Formats(), index := 1
                for position, format in formats
                    if format.Id = this.Mode.Format
                        index := position
                this.Mode.Format := formats[Mod(index, formats.Length) + 1].Id
                this.ShowPasteTip()
            case "search":
                this.CancelPaste(false)
                this.UI.ShowHistory(false)
            case "up-channel": this.CycleChannel(-1)
            case "down-channel": this.CycleChannel(1)
            case "pin":
                record := this.Mode.Items[this.Mode.Index]
                this.Store.Pin(id, this.Channel, !record.pinned)
                record.pinned := !record.pinned
                this.ShowPasteTip()
            case "first":
                this.Store.AddMembership(id, this.Channel)
                this.Mode.Items := this.Store.List(this.Channel)
                this.Select(1)
            case "tag":
                this.CancelPaste(false)
                response := InputBox("Tag this clip", "Clipjump Modern", "w360 h140", this.Store.Get(id).tag)
                if response.Result = "OK"
                    this.Store.Tag(id, response.Value)
            case "hold":
                this.CancelPaste(false)
                this.UI.ShowHold(id)
            case "export":
                this.CancelPaste(false)
                this.UI.ExportArchive(id)
            case "delete":
                this.Store.Remove(id, this.Channel)
                this.Mode.Items := this.Store.List(this.Channel)
                if this.Mode.Items.Length
                    this.Select(Min(this.Mode.Index, this.Mode.Items.Length))
                else
                    this.CancelPaste(true)
            case "multi":
                this.ApplyModeFormat()
                this.Sender.Call("^v")
                this.Mode.MultiPaste := true
        }
    }
    Cycle(direction) {
        if this.Mode
            this.Select(Mod(this.Mode.Index - 1 + direction + this.Mode.Items.Length, this.Mode.Items.Length) + 1)
    }
    Select(index) {
        if !this.Mode || !this.Mode.Items.Length
            return
        index := Max(1, Min(index, this.Mode.Items.Length))
        try snapshot := this.Store.Snapshot(this.Mode.Items[index])
        catch as err {
            this.CancelPaste(true)
            throw err
        }
        this.Mode.CurrentSequence := this.WriteClipboard(snapshot)
        this.Mode.SelectedSnapshot := snapshot
        this.Mode.Index := index, this.Mode.Changed := true, this.Mode.Native := false, this.Mode.MultiPaste := false
        this.ShowPasteTip()
    }
    CycleChannel(direction) {
        channels := this.Store.Channels(), index := 1
        for position, channel in channels
            if channel.id = this.Channel
                index := position
        index := Mod(index - 1 + direction + channels.Length, channels.Length) + 1
        this.Channel := channels[index].id
        this.Config.Set("Channel", this.Channel)
        this.Mode.Items := this.Store.List(this.Channel)
        if this.Mode.Items.Length
            this.Select(1)
        else
            this.CancelPaste(true)
    }
    ShowPasteTip() {
        if this.Mode
            this.UI.ShowOverlay(this.Mode.Items[this.Mode.Index], this.Mode.Index, this.Mode.Items.Length, this.Mode.Format)
    }
    CheckPasteRelease() {
        if this.Mode && !GetKeyState(this.ReleaseKey)
            this.Guard(ObjBindMethod(this, "FinishPaste"))
    }
    ApplyModeFormat() {
        if !this.Mode || this.Mode.Format = "none"
            return
        snapshot := this.Mode.Native ? this.Mode.Original : this.Store.Snapshot(this.Mode.Items[this.Mode.Index])
        if snapshot.Kind != "text" && snapshot.Kind != "files"
            throw Error("This paste format applies to text clips only.")
        text := this.Plugins.Transform(this.Mode.Format, snapshot.Text)
        this.Mode.SelectedSnapshot := CJSnapshot.FromText(text)
        this.Mode.CurrentSequence := this.WriteClipboard(this.Mode.SelectedSnapshot)
        this.Mode.Changed := true, this.Mode.Native := false
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
        try this.ApplyModeFormat()
        catch as err {
            this.CancelPaste(true)
            throw err
        }
        mode := this.Mode, this.Mode := false
        SetTimer(this.PasteTimer, 0), this.RemovePasteKeys(), this.UI.HideOverlay()
        this.LastSelectedId := mode.Items[mode.Index].id
        this.LastSnapshot := mode.SelectedSnapshot, this.LastSequence := mode.CurrentSequence, this.LastId := this.LastSelectedId
        if !mode.MultiPaste {
            this.Sender.Call("^v")
            if GetKeyState("Shift")
                this.Store.Remove(this.LastSelectedId, this.Channel)
        }
    }
    CancelPaste(restore := true) {
        if !this.Mode
            return
        mode := this.Mode, this.Mode := false
        SetTimer(this.PasteTimer, 0), this.RemovePasteKeys(), this.UI.HideOverlay()
        if restore && mode.Changed && CJClipboard.Sequence() = mode.CurrentSequence {
            this.LastSequence := this.WriteClipboard(mode.Original)
            this.LastSnapshot := mode.Original, this.LastId := mode.OriginalId
        }
    }

    ExternalTarget() {
        hwnd := WinExist("A"), pid := 0
        DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
        if hwnd && pid != DllCall("GetCurrentProcessId")
            this.LastTarget := hwnd
        return this.LastTarget
    }
    PasteSnapshot(snapshot, target := 0) {
        this.WriteClipboard(snapshot)
        if this.HooksEnabled {
            if !target || !WinExist("ahk_id " target) {
                this.Tip("Clip copied. Select a destination and paste.")
                return false
            }
            WinActivate("ahk_id " target)
            if !WinWaitActive("ahk_id " target, , 1)
                return false
        }
        this.Sender.Call("^v")
        return true
    }
    PasteIds(ids, target := 0) {
        for index, id in ids {
            if index > 1
                this.Sender.Call("{Enter}")
            if !this.PasteSnapshot(this.Store.Snapshot(id), target)
                break
            if index < ids.Length
                Sleep(120)
        }
    }
    PastePlain() {
        target := this.ExternalTarget()
        if IsObject(this.LastSnapshot) && this.LastSequence = CJClipboard.Sequence()
            return this.PasteSnapshot(CJSnapshot.FromText(RTrim(this.LastSnapshot.Text, "`r`n")), target)
        if this.QueueCapture(true)
            this.PendingPlain := {Target: target, Sequence: CJClipboard.Sequence()}
    }

    SetChannel(id) {
        this.Store.Channel(id)
        this.CancelPaste(false), this.Job.Cancel()
        this.Channel := id, this.LastSelectedId := 0
        this.Config.Set("Channel", id)
        if this.HooksEnabled
            this.BuildTray()
    }
    ToggleSetting(name, explicit := "") {
        value := explicit = "" ? !this.Config.Get(name) : explicit = "on" || explicit = "1"
        this.Config.Set(name, value ? 1 : 0)
        this.Job.Cancel(), this.CancelPaste(false)
        if name = "Incognito" || !value
            this.LastSequence := 0
        if this.HooksEnabled
            this.BuildTray()
    }

    Action(action, *) {
        parts := StrSplit(action, ":", , 2), command := StrLower(parts[1]), argument := parts.Length > 1 ? parts[2] : ""
        switch command {
            case "history": this.CancelPaste(false), this.UI.ShowHistory(true)
            case "channel-clips": this.CancelPaste(false), this.UI.ShowHistory(false)
            case "channels": this.CancelPaste(false), this.UI.ShowChannels()
            case "settings": this.CancelPaste(false), this.UI.ShowSettings()
            case "plugins": this.CancelPaste(false), this.UI.ShowPlugins()
            case "formats": this.CancelPaste(false), this.UI.ShowFormats()
            case "hold": this.CancelPaste(false), this.UI.ShowHold()
            case "ignore": this.UI.ShowIgnored()
            case "ini": this.UI.ShowIni()
            case "custom": this.UI.ShowIni("custom")
            case "hotpaste": this.UI.ShowIni("hotpaste")
            case "translations": this.UI.ShowTranslations()
            case "import-v1": this.UI.ShowLegacyImport()
            case "import": this.UI.ImportArchive()
            case "plain": this.PastePlain()
            case "sync": this.QueueCapture(true)
            case "monitor": this.ToggleSetting("Monitoring", argument)
            case "incognito": this.ToggleSetting("Incognito", argument)
            case "channel": this.SetChannel(this.Store.ChannelId(argument))
            case "plugin": return this.Plugins.Run(argument)
            case "format":
                if !this.Plugins.Items.Has(argument)
                    throw Error("Unknown paste format.")
                this.Config.Set("DefaultFormat", argument)
            case "text": return this.PasteSnapshot(CJSnapshot.FromText(argument), this.ExternalTarget())
            case "paste":
                parameters := StrSplit(argument, ","), channel := parameters.Length && parameters[1] != "" ? this.Store.ChannelId(Trim(parameters[1])) : this.Channel
                index := parameters.Length > 1 ? Integer(parameters[2]) : 1
                rows := this.Store.List(channel)
                if index < 1 || index > rows.Length
                    throw Error("Clip index is out of range.")
                return this.PasteSnapshot(this.Store.Snapshot(rows[index]), this.ExternalTarget())
            case "tip": this.Tip(argument)
            case "send": this.Sender.Call(argument)
            case "sleep": Sleep(Max(0, Min(10000, Integer(argument))))
            case "delete-files": this.CleanPaths(false)
            case "history-paths": this.CleanPaths(true)
            case "copy-file-data":
                path := FileSelect(1, , "Copy image file data", "Images (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.tif)")
                if path != "" {
                    snapshot := CJImage.FromFile(path)
                    this.AddSnapshot(snapshot)
                    this.WriteClipboard(snapshot)
                }
            case "copy-file-path", "copy-folder-path":
                path := command = "copy-folder-path" ? DirSelect(, 0, "Copy a folder path") : FileSelect(1, , "Copy a file path")
                if path != "" {
                    snapshot := CJSnapshot.FromText(path)
                    this.AddSnapshot(snapshot), this.WriteClipboard(snapshot)
                }
            case "actions":
                this.CancelPaste(false)
                this.ActionMenu()
            case "project": Run(CJApp.ProjectPage)
            case "restart": Reload()
            case "exit": this.Shutdown(), ExitApp()
            default: throw Error("Unknown Clipjump action: " command)
        }
        return true
    }

    ActionMenu() {
        actionsMenu := Menu()
        for pair in [["&History", "history"], ["&Channels", "channels"], ["&Settings", "settings"], ["&Plugins", "plugins"], ["&Formats", "formats"], ["H&old / edit", "hold"], ["Paste &plain text", "plain"], ["S&ync clipboard", "sync"], ["&Monitor clipboard", "monitor"], ["&Incognito / private mode", "incognito"], ["Import &v1 data", "import-v1"]]
            actionsMenu.Add(pair[1], ObjBindMethod(this, "MenuAction", pair[2]))
        actionsMenu.Show()
    }
    CleanPaths(history) {
        if MsgBox(history ? "Remove file-path clips from History?" : "Remove file/folder clips from this channel?", "Clipjump Modern", "YesNo Icon?") != "Yes"
            return 0
        count := 0
        for record in this.Store.List(this.Channel, history) {
            matches := record.kind = "files"
            if !matches && history && record.text != "" {
                matches := true
                for line in StrSplit(Trim(record.text, "`r`n"), "`n", "`r")
                    if !RegExMatch(line, 'i)^(?:[A-Z]:\\|\\\\)[^*?"|]+$')
                        matches := false
            }
            if matches {
                this.Store.Remove(record.id, this.Channel, history)
                count += 1
            }
        }
        this.UI.RefreshHistory()
        this.Tip("Removed " count " clips.")
        return count
    }
    ImportLegacy(root, registered := false) => CJLegacyImport(this.Store, this.Library).Run(root, registered)
    Tip(text, duration := 1200) {
        ToolTip(text, , , 2)
        SetTimer(() => ToolTip(, , , 2), -duration)
    }

    Smoke() {
        sequence := CJClipboard.Sequence()
        this.BuildTray()
        this.UI.ShowHistory(true, false)
        this.UI.ShowChannels(false)
        this.UI.ShowSettings(false)
        this.UI.ShowIgnored(false)
        this.UI.ShowPlugins(false)
        this.UI.ShowFormats(0, false)
        this.UI.ShowMove([], 0, false, false)
        this.UI.ShowLegacyImport(false)
        this.UI.Destroy()
        return sequence = CJClipboard.Sequence()
    }

    ReceiveAPI(wParam, lParam, *) => CJAPIServer.Receive(this, wParam, lParam)

    Shutdown(*) {
        if this.Closed
            return
        this.Closed := true
        this.CancelPaste(false)
        this.Job.Cancel()
        SetTimer(this.CaptureTimer, 0), SetTimer(this.PasteTimer, 0)
        if this.HooksEnabled {
            OnClipboardChange(this.ClipboardCallback, 0)
            OnMessage(0x4A, this.ApiCallback, 0)
        }
        this.UnregisterHotkeys()
        this.Config.Set("Channel", this.Channel)
        this.UI.Destroy()
        this.Store.Close()
        CJImage.Stop()
    }
}
