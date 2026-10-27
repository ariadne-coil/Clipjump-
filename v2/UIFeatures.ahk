#Requires AutoHotkey v2.0.31+
class CJFeatureSettings {
    static Groups() => [
        ["General", [["Monitoring", "Enable clipboard capture", "bool"], ["Incognito", "Incognito: no history", "bool"], ["IncognitoStopsCapture", "Also stop channel capture in incognito", "bool"], ["KeepSession", "Retain default channel after restart", "bool"], ["RememberFormat", "Retain last-used paste format", "bool"], ["StartSearch", "Start paste mode with search", "bool"], ["PreservePosition", "Remember paste-mode position", "bool"], ["HistoryCloseOnPaste", "Close History after instant paste", "bool"], ["Deduplicate", "Skip consecutive identical clips", "bool"], ["DefaultFormat", "Default paste format", "format"]]],
        ["Storage", [["HistoryDays", "History days (0 disables new history)", "number"], ["StoreImages", "Store images in history", "bool"], ["MaximumChannelClips", "Default channel limit (0 = unlimited)", "number"], ["ClipThreshold", "Cleanup threshold", "number"], ["LimitAllChannels", "Apply this limit to every channel", "bool"], ["ThumbnailQuality", "JPEG preview quality (1–100)", "number"]]],
        ["Capture", [["ManualCaptureOnly", "Capture only explicit copy and cut", "bool"], ["WinCopyCut", "Use Win+C / Win+X for Clipjump", "bool"], ["CopyMessage", "Show capture confirmation", "bool"], ["CopyBeep", "Beep after capture", "bool"], ["BeepFrequency", "Beep frequency (37–32767 Hz)", "number"]]],
        ["Shortcuts", [["PasteHotkey", "Paste mode", "shortcut"], ["HistoryHotkey", "History", "shortcut"], ["ActionHotkey", "Action menu", "shortcut"], ["ChannelsHotkey", "Channels", "shortcut"], ["PlainHotkey", "Paste plain text", "shortcut"], ["PitSwapHotkey", "PitSwap", "shortcut"], ["OneTimeHotkey", "One Time Stop", "shortcut"], ["SystemCopyHotkey", "System clipboard copy only", "shortcut"], ["SystemCutHotkey", "System clipboard cut only", "shortcut"], ["HoldHotkey", "Hold selection", "shortcut"], ["CopyFilesHotkey", "Copy selected file paths", "shortcut"], ["CopyFolderHotkey", "Copy active folder path", "shortcut"], ["CopyDataHotkey", "Copy selected file data", "shortcut"], ["PluginHotkey", "Plugins", "shortcut"]]],
        ["Paste keys", [["NextKey", "Next clip", "key"], ["PreviousKey", "Previous clip", "key"], ["ModeKey", "Cancel / delete / move / copy", "key"], ["FormatKey", "Next paste format", "key"], ["PlainKey", "Plain text", "key"], ["SearchKey", "Search", "key"], ["ClipboardKey", "Copy without pasting", "key"], ["FirstKey", "Jump to first clip", "key"], ["FrontKey", "Move clip to first position", "key"], ["PinKey", "Fixate", "key"], ["TagKey", "Tag", "key"], ["EditKey", "External editor", "key"], ["ExportKey", "Export", "key"], ["HelpKey", "Paste-mode shortcuts", "key"]]],
        ["Appearance", [["Language", "Language", "language"], ["ShowPasteTip", "Show paste-mode overlay", "bool"], ["ShowPastingTip", "Show pasting confirmation", "bool"], ["PasteX", "Overlay X (blank = follow mouse)", "text"], ["PasteY", "Overlay Y (blank = follow mouse)", "text"]]],
        ["System", [["StartWithWindows", "Start with Windows", "bool"], ["TextEditor", "Text editor executable", "text"], ["ImageEditor", "Image editor executable", "text"], ["ProcessPriority", "Process priority", "priority"], ["RAMFlush", "Periodically trim working-set memory", "bool"]]]]
    static Validate(values) {
        for name, range in Map("HistoryDays", [0, 36500], "MaximumChannelClips", [0, 100000], "ClipThreshold", [1, 100000], "ThumbnailQuality", [1, 100], "BeepFrequency", [37, 32767])
            if values[name] < range[1] || values[name] > range[2]
                throw Error(name " must be between " range[1] " and " range[2] ".")
        keys := Map()
        for group in this.Groups()
            for field in group[2] {
                if field[3] = "bool" && values[field[1]] != 0 && values[field[1]] != 1
                    throw Error("Invalid checkbox value.")
                if field[3] = "key" {
                    key := StrLower(values[field[1]])
                    if !RegExMatch(key, "i)^(?:[a-z]|F(?:[1-9]|1\d|2[0-4])|Space|Tab)$") || keys.Has(key)
                        throw Error("Paste-mode keys must be valid and unique.")
                    keys[key] := true
                }
            }
        for name in ["PasteX", "PasteY"]
            if values[name] != "" && !RegExMatch(values[name], "^-?\d{1,6}$")
                throw Error("Overlay coordinates must be numbers or blank.")
        if !InStr("|Low|BelowNormal|Normal|AboveNormal|High|Realtime|", "|" values["ProcessPriority"] "|")
            throw Error("Choose a valid process priority.")
        if Trim(values["TextEditor"]) = "" || Trim(values["ImageEditor"]) = ""
            throw Error("Choose an editor executable in Settings.")
    }
}

class CJUI extends CJUIBase {
    __New(app) {
        super.__New(app)
        this.ExtraKeys := [], this.EditingWindows := Map()
    }
    New(name, title, options := "+Resize") {
        if this.Windows.Has(name) {
            this.ClearWindowKeys(this.Windows[name].Hwnd)
            this.Windows[name].Destroy()
            this.Windows.Delete(name)
        }
        window := CJWindow(this.App.Config, options, title)
        window.SetFont("s10", "Segoe UI"), window.MarginX := 12, window.MarginY := 12
        window.OnEvent("Close", (*) => window.Hide())
        window.OnEvent("Escape", (*) => window.Hide())
        this.Windows[name] := window
        return window
    }
    BindWindowKey(window, key, callback) {
        HotIfWinActive("ahk_id " window.Hwnd)
        Hotkey(key, callback, "On")
        HotIfWinActive()
        this.ExtraKeys.Push({Hwnd: window.Hwnd, Key: key})
    }
    ClearWindowKeys(hwnd) {
        index := this.ExtraKeys.Length
        while index >= 1 {
            item := this.ExtraKeys[index]
            if item.Hwnd = hwnd {
                HotIfWinActive("ahk_id " hwnd)
                try Hotkey(item.Key, "Off")
                this.ExtraKeys.RemoveAt(index)
            }
            index -= 1
        }
        HotIfWinActive()
    }
    ShowSettings(visible := true) {
        window := this.New("settings", "Clipjump Modern — Settings", ""), controls := Map(), types := Map(), choices := Map()
        groups := CJFeatureSettings.Groups(), pages := []
        for group in groups
            pages.Push(group[1])
        tab := window.AddTab3("x12 y12 w990 h520", pages)
        for page, group in groups {
            tab.UseTab(page)
            for index, field in group[2] {
                name := field[1], label := field[2], kind := field[3]
                double := group[2].Length > 10
                column := double && index > 7 ? 1 : 0, row := double ? Mod(index - 1, 7) : index - 1
                x := 28 + column * 480, y := 55 + row * 40
                value := this.App.Config.Get(name)
                if kind = "bool" {
                    control := window.AddCheckbox("x" x " y" y " w920", label)
                    control.Value := value
                } else {
                    window.AddText("x" x " y" y + 4 " w" (double ? 240 : 390), label)
                    options := "x" (x + (double ? 245 : 400)) " y" y " w" (double ? 205 : 500)
                    if kind = "shortcut" && !InStr(value, "#")
                        control := window.AddHotkey(options, value)
                    else if kind = "format" || kind = "language" || kind = "priority" {
                        ids := [], labels := [], chosen := 1
                        if kind = "format" {
                            for format in this.App.Plugins.Formats()
                                ids.Push(format.Id), labels.Push(this.App.Config.L(format.Name))
                        } else if kind = "language" {
                            Loop Files this.App.Root "\languages\*.txt", "F" {
                                language := SubStr(A_LoopFileName, 1, -4)
                                ids.Push(language), labels.Push(language)
                            }
                        } else {
                            ids := ["Low", "BelowNormal", "Normal", "AboveNormal", "High", "Realtime"]
                            for id in ids
                                labels.Push(this.App.Config.L(id))
                        }
                        for position, id in ids
                            if id = value
                                chosen := position
                        control := window.AddDropDownList(options " Choose" chosen, labels), choices[name] := ids
                    } else
                        control := window.AddEdit(options (kind = "number" ? " Number" : ""), value)
                }
                controls[name] := control, types[name] := kind
            }
        }
        tab.UseTab()
        state := {Gui: window, Controls: controls, Types: types, Choices: choices}
        this.Settings := state
        this.Button(window, "x20 y548 w110 Default", "Save", ObjBindMethod(this, "SaveFeatureSettings", state))
        this.Button(window, "x+10 yp w160", "Ignored windows…", ObjBindMethod(this, "ShowIgnored"))
        this.Button(window, "x+10 yp w160", "Check for updates", ObjBindMethod(this.App, "Action", "updates"))
        this.Button(window, "x+10 yp w160", "Configuration editor", ObjBindMethod(this, "ShowIni"))
        if visible
            window.Show("w1014 h590")
        return window
    }
    SaveFeatureSettings(state) {
        values := this.App.Config.Values.Clone()
        for name, control in state.Controls {
            kind := state.Types[name]
            if state.Choices.Has(name)
                values[name] := state.Choices[name][control.Value]
            else
                values[name] := kind = "bool" || kind = "number" ? Integer(control.Value) : control.Value
        }
        this.App.ApplySettings(values)
        state.Gui.Hide()
    }
    ShowHistory(history := true, visible := true) {
        wasNew := !this.History
        window := super.ShowHistory(history, false), state := this.History
        names := [this.App.Config.L("All history"), this.App.Config.L("All channels")]
        state.Scopes := [{History: true, Channel: 0}, {History: false, Channel: -1}], chosen := history ? 1 : 2
        for channel in this.App.Store.Channels() {
            names.Push(channel.name), state.Scopes.Push({History: false, Channel: channel.id})
            if !history && channel.id = this.App.Channel
                chosen := names.Length
        }
        state.Scope.Delete(), state.Scope.Add(names), state.Scope.Choose(chosen)
        state.SearchMode := false
        window.OriginalTitle := "Clipjump Modern — Clipboard History"
        if wasNew {
            this.BindWindowKey(window, "$Enter", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "paste")))
            this.BindWindowKey(window, "$^Enter", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "paste-keep")))
            this.BindWindowKey(window, "$MButton", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "paste")))
            this.BindWindowKey(window, "$^f", (*) => this.SearchControl())
            this.BindWindowKey(window, "$^n", (*) => this.NewClip())
            this.BindWindowKey(window, "$^+n", (*) => this.NewChannel())
            this.BindWindowKey(window, "$^g", (*) => state.Scope.Focus())
            this.BindWindowKey(window, "$^e", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "export")))
        }
        this.RefreshHistory()
        if visible {
            window.Show("w1060 h640"), state.Search.Focus()
        }
        return window
    }
    ShowSearchMode(visible := true) {
        window := this.ShowHistory(false, false), state := this.History
        state.SearchMode := true
        window.OriginalTitle := "Clipjump Modern — Search-Paste Mode"
        this.RefreshHistory()
        if visible
            window.Show("w1060 h640"), state.Search.Focus()
        return window
    }
    SearchControl() {
        if !this.History
            return
        if !this.History.SearchMode
            return this.History.Search.Focus()
        ids := this.Selected()
        if !ids.Length
            return
        snapshot := this.App.Store.Snapshot(ids[1])
        this.History.Gui.Hide()
        this.App.LastId := ids[1], this.App.LastSnapshot := snapshot, this.App.LastSequence := this.App.WriteClipboard(snapshot)
        this.App.BeginPaste(true)
    }
    ResizeHistory(window, minimized, width, height) {
        super.ResizeHistory(window, minimized, width, height)
        if minimized != -1 && this.History {
            this.History.Search.Move(70, 11, Max(160, width - 540))
            this.History.Partial.Move(width - 450, 15, 115)
        }
    }
    RefreshHistory(*) {
        if !this.History || !this.History.Scopes.Length
            return
        state := this.History, selection := Map()
        for id in this.Selected()
            selection[id] := true
        scope := state.Scopes[Max(1, state.Scope.Value)]
        state.Rows := this.App.Store.List(scope.Channel, scope.History, state.Search.Value, 100000, state.Partial.Value)
        state.List.Delete()
        for record in state.Rows {
            text := record.text != "" ? SubStr(StrReplace(StrReplace(record.text, "`r", ""), "`n", " | "), 1, 160) : "[" record.kind "]"
            state.List.Add(selection.Has(record.id) ? "Select" : "", (record.pinned ? "* " : "") text, this.App.Config.L(record.kind), record.created, record.tag, record.bytes)
        }
        if state.SearchMode && !state.List.GetNext() && state.Rows.Length
            state.List.Modify(1, "Select Focus")
        state.List.ModifyCol(1, 280), state.List.ModifyCol(2, 62), state.List.ModifyCol(3, 155), state.List.ModifyCol(4, 90), state.List.ModifyCol(5, 75)
        name := scope.History ? this.App.Config.L("History") : scope.Channel = -1 ? this.App.Config.L("All channels") : this.App.Store.Channel(scope.Channel).name
        state.Status.SetText(state.Rows.Length " " this.App.Config.L("clips") " — " name)
        this.HistoryPreview()
    }
    HistoryAction(action) {
        if action = "new"
            return this.NewClip()
        ids := this.Selected()
        if action = "pin" && ids.Length {
            scope := this.History.Scopes[this.History.Scope.Value]
            if scope.History || scope.Channel = -1 {
                channel := this.App.Channel, id := ids[1]
                this.App.Store.AddMembership(id, channel)
                row := this.App.Store.DB.Query("SELECT pinned FROM memberships WHERE channel_id=?1 AND clip_id=?2", [channel, id])[1]
                this.App.Store.Pin(id, channel, !row.pinned)
                return this.RefreshHistory()
            }
        }
        if action = "external-edit" {
            if ids.Length
                this.App.Edits.Open(ids[1])
            return
        }
        if action = "swap" {
            if !ids.Length || ids.Length > 2
                throw Error("Select one or two clips to swap.")
            scope := this.History.Scopes[this.History.Scope.Value]
            if ids.Length = 2 && !scope.History && scope.Channel >= 0 {
                this.App.Store.SwapClips(ids[1], ids[2], scope.Channel, scope.Channel)
                return this.RefreshHistory()
            }
            return this.ShowSwapClips(ids[1])
        }
        if action = "paste" || action = "paste-keep" {
            if !ids.Length
                return
            keep := action = "paste-keep" || !this.App.Config.Get("HistoryCloseOnPaste")
            this.History.Gui.Hide()
            this.App.PasteIds(ids, this.LastTarget)
            if keep
                this.History.Gui.Show(), this.History.Search.Focus()
            return
        }
        return super.HistoryAction(action)
    }
    ChannelResult(state, action) {
        row := state.List.GetNext(), id := row ? state.Rows[row].id : -1
        switch action {
            case "Use":
                if id >= 0
                    this.App.SetChannel(id)
                state.Gui.Hide()
                return
            case "Add": this.App.Store.AddChannel(state.Name.Value, state.Protected.Value, state.NoHistory.Value)
            case "Save":
                if id >= 0
                    this.App.Store.UpdateChannel(id, state.Name.Value, state.Protected.Value, state.NoHistory.Value)
            case "Delete":
                if id > 0 && MsgBox(this.App.Config.L("Delete this channel? Clips retained in History remain available."), "Clipjump Modern", "YesNo Icon?") = "Yes" {
                    if this.App.Channel = id
                        this.App.SetChannel(0)
                    this.App.Store.DeleteChannel(id)
                }
        }
        if this.History
            this.ShowHistory(false, false)
        this.ShowChannels()
    }
    NewChannel(*) {
        this.ShowChannels()
        this.ChannelState.Name.Focus()
    }
    HistoryPreview(*) {
        super.HistoryPreview()
        ids := this.Selected()
        if !ids.Length
            return
        names := ""
        for row in this.App.Store.DB.Query("SELECT c.name FROM channels c JOIN memberships m ON m.channel_id=c.id WHERE m.clip_id=?1 ORDER BY c.id", [ids[1]])
            names .= (names = "" ? "" : ", ") row.name
        if names != ""
            this.History.Preview.Value .= "`r`n" this.App.Config.L("Channels") ": " names
    }
    ShowChannels(visible := true) {
        window := super.ShowChannels(false)
        this.Button(window, "xm y+12 w180", "Browse all channels", ObjBindMethod(this, "ShowAllChannels"))
        this.Button(window, "x+10 yp w180", "Swap channel contents", ObjBindMethod(this, "ShowSwapChannels"))
        this.Button(window, "x+10 yp w180", "New clip", ObjBindMethod(this, "NewClip"))
        if visible
            window.Show()
        return window
    }
    ShowAllChannels(*) {
        this.ShowHistory(false, false)
        this.History.Scope.Choose(2), this.RefreshHistory(), this.History.Gui.Show("w1060 h640")
    }
    ShowSwapChannels(visible := true, *) {
        window := this.New("swap-channels", "Clipjump Modern — Swap channel contents", "")
        channels := this.App.Store.Channels(), names := []
        for channel in channels
            names.Push(channel.name)
        window.AddText("w500", "Choose two channels. Their clips and fixed positions will be exchanged.")
        first := window.AddDropDownList("w500 Choose1", names)
        second := window.AddDropDownList("w500 Choose" Min(2, names.Length), names)
        this.Button(window, "w120 Default", "Swap", (*) => (this.App.Store.SwapChannels(channels[first.Value].id, channels[second.Value].id), window.Hide(), this.RefreshHistory()))
        if visible
            window.Show()
    }
    ShowSwapClips(id, visible := true) {
        origins := this.App.Store.DB.Query("SELECT c.* FROM channels c JOIN memberships m ON m.channel_id=c.id WHERE m.clip_id=?1 ORDER BY c.id", [id])
        if !origins.Length
            throw Error("Add this clip to a channel before swapping it.")
        window := this.New("swap-clips", "Clipjump Modern — Swap clips", "")
        window.AddText("w700", "Source clip")
        window.AddEdit("w700 h70 ReadOnly", this.App.Store.Get(id).text)
        names := []
        for channel in origins
            names.Push(channel.name)
        window.AddText("w700", "Source channel")
        origin := window.AddDropDownList("w700 Choose1", names)
        channels := this.App.Store.Channels(), names := []
        for channel in channels
            names.Push(channel.name)
        window.AddText("w700", "Destination channel")
        destination := window.AddDropDownList("w700 Choose1", names)
        list := window.AddListView("w700 h220", ["Clip", "Type"])
        state := {Gui: window, Id: id, Origin: origin, Origins: origins, Destination: destination, Channels: channels, List: list, Rows: []}
        destination.OnEvent("Change", (*) => this.ReloadSwapClips(state))
        this.Button(window, "w120 Default", "Swap", ObjBindMethod(this, "SwapClipResult", state))
        this.ReloadSwapClips(state)
        if visible
            window.Show()
        return state
    }
    ReloadSwapClips(state) {
        state.List.Delete(), state.Rows := []
        for row in this.App.Store.List(state.Channels[state.Destination.Value].id, false, "", 100000) {
            if row.id = state.Id
                continue
            state.Rows.Push(row)
            state.List.Add("", SubStr(row.text, 1, 140), this.App.Config.L(row.kind))
        }
        state.List.ModifyCol(1, 570), state.List.ModifyCol(2, 90)
    }
    SwapClipResult(state) {
        selected := state.List.GetNext()
        if !selected
            throw Error("Choose a destination clip.")
        this.App.Store.SwapClips(state.Id, state.Rows[selected].id, state.Origins[state.Origin.Value].id, state.Channels[state.Destination.Value].id)
        state.Gui.Hide(), this.RefreshHistory()
    }
    NewClip(*) => this.ShowHeld(CJSnapshot.FromText(""), this.App.ExternalTarget())
    ShowHeld(snapshot, target := 0, visible := true) {
        window := this.New("hold", "Clipjump Modern — Hold / edit", "+AlwaysOnTop +Resize")
        window.AddText("w680", "Formatting is kept while the text is unchanged. Editing creates plain text.")
        edit := window.AddEdit("w680 h320 Multi", snapshot.Text)
        state := {Gui: window, Edit: edit, Original: snapshot, Id: 0, Target: target}
        this.Held := state
        this.Button(window, "w100", "Copy", ObjBindMethod(this, "HoldResult", state, "copy"))
        this.Button(window, "x+10 w100", "Paste", ObjBindMethod(this, "HoldResult", state, "paste"))
        this.Button(window, "x+10 w150", "Add to channel", ObjBindMethod(this, "HoldResult", state, "save"))
        this.Button(window, "x+10 w140", "Formats", (*) => this.HeldFormats(state))
        if visible
            window.Show()
        return window
    }
    HeldFormats(state, visible := true) {
        this.App.HeldSnapshot := state.Edit.Value = state.Original.Text ? state.Original : CJSnapshot.FromText(state.Edit.Value)
        this.ShowFormats(0, visible, "", this.App.HeldSnapshot)
    }
    UseFormat(state, paste) {
        format := state.Formats[state.Chooser.Value].Id
        super.UseFormat(state, paste)
        this.App.RememberFormat(format)
    }
    ShowEditing(key, state) {
        window := this.New("editing-" key, "Clipjump Modern — External editor", "")
        window.AddText("w650", "Save in your editor. Saved changes are reloaded automatically.")
        window.AddEdit("w650 ReadOnly", state.Path)
        status := window.AddText("w650", "Waiting for editor save.")
        this.Button(window, "w180 Default", "Reload saved changes", (*) => this.App.Guard(ObjBindMethod(this.App.Edits, "Commit", key)))
        this.Button(window, "x+10 yp w120", "Finish", (*) => (this.App.Edits.Finish(key), this.CloseEditing(key)))
        this.EditingWindows[key] := {Gui: window, Status: status}
        window.Show()
    }
    CloseEditing(key) {
        if this.EditingWindows.Has(key) {
            this.EditingWindows[key].Gui.Hide()
            this.EditingWindows.Delete(key)
        }
    }
    UpdateEditing(key, state) {
        if this.EditingWindows.Has(key)
            this.EditingWindows[key].Status.Text := state.LastError != "" ? this.App.Config.L("Could not reload saved changes.") " " state.LastError : this.App.Config.L(state.Changed ? "Saved changes reloaded." : "Waiting for editor save.")
    }
    ShowPreview(id, visible := true) {
        record := this.App.Store.Get(id), snapshot := this.App.Store.Snapshot(id)
        window := this.New("preview", "Clipjump Modern — Preview", "+Resize +MinSize480x300")
        query := window.AddEdit("x12 y12 w540")
        this.Button(window, "x+8 yp w120", "Find next", (*) => this.FindPreview())
        text := window.AddEdit("x12 y52 w710 h430 ReadOnly Multi", record.text)
        picture := window.AddPicture("x12 y52 w710 h430 Hidden")
        path := this.App.Config.Data "\preview.png", dimensions := false
        if snapshot.Kind = "image" && CJImage.Thumbnail(snapshot, path, true)
            dimensions := CJImage.Dimensions(path)
        this.PreviewState := {Gui: window, Query: query, Text: text, Picture: picture, Path: path, Dimensions: dimensions, Offset: 1}
        this.BindWindowKey(window, "$^f", (*) => query.Focus())
        this.BindWindowKey(window, "$F3", (*) => this.FindPreview())
        this.BindWindowKey(window, "$Enter", (*) => this.FindPreview())
        window.OnEvent("Size", (*) => this.ResizePreview())
        if visible
            window.Show("w740 h520")
        this.ResizePreview()
        return window
    }
    ResizePreview() {
        state := this.PreviewState
        state.Gui.GetClientPos(, , &width, &height)
        if width < 100 || height < 100
            width := 740, height := 520
        state.Query.Move(12, 12, Max(180, width - 160))
        state.Text.Move(12, 52, width - 24, height - 64)
        state.Picture.Move(12, 52, width - 24, height - 64)
        if state.Dimensions {
            scale := Min((width - 24) / state.Dimensions.Width, (height - 64) / state.Dimensions.Height)
            state.Picture.Value := "*w" Max(1, Floor(state.Dimensions.Width * scale)) " *h" Max(1, Floor(state.Dimensions.Height * scale)) " " state.Path
            state.Picture.Visible := true, state.Text.Visible := false
        }
    }
    static FindRange(text, query, offset := 1, partial := false) {
        if Trim(query) = ""
            return false
        terms := partial ? StrSplit(Trim(RegExReplace(query, "\s+", " ")), " ") : [query]
        best := false
        for term in terms {
            position := InStr(StrLower(text), StrLower(term), true, offset)
            if position && (!best || position < best.Position)
                best := {Position: position, Length: StrLen(term)}
        }
        if !best && offset > 1
            return this.FindRange(text, query, 1, partial)
        return best
    }
    FindPreview() {
        state := this.PreviewState
        found := CJUI.FindRange(state.Text.Value, state.Query.Value, state.Offset, this.App.Config.Get("PartialSearch"))
        if !found
            return false
        SendMessage(0xB1, found.Position - 1, found.Position - 1 + found.Length, state.Text.Hwnd)
        SendMessage(0xB7, 0, 0, state.Text.Hwnd)
        state.Offset := found.Position + found.Length
        state.Text.Focus()
        return true
    }
    ShowPasteHelp(visible := true) {
        window := this.New("paste-help", "Clipjump Modern — Paste-mode shortcuts", "+AlwaysOnTop")
        list := window.AddListView("w650 h420", ["Key", "Action"])
        for field in CJFeatureSettings.Groups()[5][2]
            list.Add("", this.App.Config.Get(field[1]), this.App.Config.L(field[2]))
        for pair in [["1–9", "Relative jump"], ["Enter", "Paste and continue"], ["Up / Down", "Change channel"], ["Shift", "Delete after pasting"]]
            list.Add("", pair[1], this.App.Config.L(pair[2]))
        list.ModifyCol(1, 140), list.ModifyCol(2, 480)
        if visible
            window.Show("NoActivate")
        return window
    }
    ShowOverlay(record, index, total, format) {
        super.ShowOverlay(record, index, total, this.App.Config.L(this.App.Plugins.Items[format].Name))
        mode := this.App.Mode, action := IsObject(mode) ? mode.Action : "paste"
        caption := Map("paste", "Paste", "cancel", "Cancel", "delete", "Delete", "move", "Move to…", "copy", "Copy", "delete-all", "Clear…")[action]
        preview := record.text != "" ? SubStr(RegExReplace(record.text, "\s+", " "), 1, 200) : "[" this.App.Config.L(record.kind) "]"
        this.Overlay.Label.Move(, , 460, 180)
        this.Overlay.Label.Value := "{" this.App.Store.Channel(this.App.Channel).name "}  " this.App.Config.L("Clip") " " index " / " total "  [" this.App.Config.L(caption) "]`n" this.App.Config.L(this.App.Plugins.Items[format].Name) "`n`n" preview "`n`n" this.App.Config.L("Release the modifier to confirm.") " " this.App.Config.Get("ModeKey") ": " this.App.Config.L("Switch mode")
        this.Overlay.Gui.Show("NoActivate AutoSize")
        xValue := this.App.Config.Get("PasteX"), yValue := this.App.Config.Get("PasteY")
        if xValue != "" || yValue != "" {
            this.Overlay.Gui.GetPos(&x, &y)
            this.Overlay.Gui.Show("NoActivate x" (xValue != "" ? Integer(xValue) : x) " y" (yValue != "" ? Integer(yValue) : y))
        }
    }
    Destroy() {
        for item in this.ExtraKeys {
            HotIfWinActive("ahk_id " item.Hwnd)
            try Hotkey(item.Key, "Off")
        }
        HotIfWinActive(), this.ExtraKeys := []
        super.Destroy()
    }
}
