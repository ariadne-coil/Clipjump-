#Requires AutoHotkey v2.0.31+
class CJUIBase {
    __New(app) {
        this.App := app, this.Windows := Map(), this.History := false, this.Overlay := false
        this.LastTarget := 0
    }

    New(name, title, options := "+Resize") {
        if this.Windows.Has(name) {
            this.Windows[name].Destroy()
            this.Windows.Delete(name)
        }
        window := Gui(options, title)
        window.SetFont("s10", "Segoe UI")
        window.MarginX := 12, window.MarginY := 12
        window.OnEvent("Close", (*) => window.Hide())
        window.OnEvent("Escape", (*) => window.Hide())
        this.Windows[name] := window
        return window
    }

    Button(window, options, text, callback) {
        button := window.AddButton(options, text)
        button.OnEvent("Click", (*) => this.App.Guard(callback))
        return button
    }

    ShowHistory(history := true, visible := true) {
        this.LastTarget := this.App.ExternalTarget()
        if !this.History {
            window := this.New("history", "Clipjump Modern — " this.App.Config.T("HST__name", "Clipboard History"), "+Resize +MinSize820x480")
            window.AddText("x12 y15 w52", "Search")
            search := window.AddEdit("x70 y11 w440")
            partial := window.AddCheckbox("x520 y15 w120", "Partial")
            partial.Value := this.App.Config.Get("PartialSearch")
            scope := window.AddDropDownList("x650 y11 w338")
            commands := [["Paste", "paste"], ["Copy", "copy"], ["Preview", "preview"], ["Hold / edit", "edit"], ["Formats", "formats"], ["Export", "export"], ["Import", "import"], ["New clip", "new"], ["External editor", "external-edit"]]
            for index, pair in commands
                this.Button(window, "x" (12 + (index - 1) * 94) " y44 w88 h28", pair[1], ObjBindMethod(this, "HistoryAction", pair[2]))
            commands := [["Move to…", "move"], ["Copy to…", "copy-to"], ["Pin", "pin"], ["Tag", "tag"], ["Delete", "delete"], ["Clear…", "clear"], ["Settings", "settings"], ["Swap clips", "swap"]]
            for index, pair in commands
                this.Button(window, "x" (12 + (index - 1) * 94) " y78 w88 h28", pair[1], ObjBindMethod(this, "HistoryAction", pair[2]))
            list := window.AddListView("x12 y116 w620 h440 +LV0x10000", ["Clip", "Type", "Date", "Tag", "Size"])
            preview := window.AddEdit("x646 y116 w342 h225 +ReadOnly +Multi -Wrap")
            picture := window.AddPicture("x646 y350 w342 h200 Hidden")
            status := window.AddStatusBar()
            this.History := {Gui: window, Search: search, Partial: partial, Scope: scope, List: list, Preview: preview, Picture: picture, Status: status, Rows: [], Scopes: [], SearchMode: false}
            partial.OnEvent("Click", (*) => (this.App.Config.Set("PartialSearch", partial.Value), this.RefreshHistory()))
            search.OnEvent("Change", (*) => this.RefreshHistory())
            scope.OnEvent("Change", (*) => this.RefreshHistory())
            list.OnEvent("DoubleClick", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "paste")))
            list.OnEvent("ItemSelect", (*) => this.HistoryPreview())
            window.OnEvent("Size", ObjBindMethod(this, "ResizeHistory"))
            HotIfWinActive("ahk_id " window.Hwnd)
            Hotkey("$Space", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "paste")))
            Hotkey("$^c", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "copy")))
            Hotkey("$Delete", (*) => this.App.Guard(ObjBindMethod(this, "HistoryAction", "delete")))
            Hotkey("$^f", (*) => search.Focus())
            Hotkey("$F5", (*) => this.RefreshHistory())
            HotIfWinActive()
        }
        state := this.History, state.Scopes := [{History: true, Channel: 0}]
        names := ["All history"], chosen := 1
        for channel in this.App.Store.Channels() {
            names.Push(channel.name)
            state.Scopes.Push({History: false, Channel: channel.id})
            if !history && channel.id = this.App.Channel
                chosen := names.Length
        }
        state.Scope.Delete(), state.Scope.Add(names), state.Scope.Choose(chosen)
        this.RefreshHistory()
        if visible {
            state.Gui.Show("w1060 h640")
            state.Search.Focus()
        }
        return state.Gui
    }

    ResizeHistory(window, minimized, width, height) {
        if minimized = -1 || !this.History
            return
        state := this.History, split := Max(430, Floor(width * 0.62))
        state.Search.Move(70, 11, Max(160, width - 410))
        state.Scope.Move(width - 320, 11, 308)
        state.List.Move(12, 116, split - 24, Max(180, height - 152))
        state.Preview.Move(split, 116, width - split - 12, Max(100, Floor((height - 170) * 0.5)))
        state.Picture.Move(split, 130 + Floor((height - 170) * 0.5), width - split - 12, Max(80, Floor((height - 190) * 0.5)))
    }

    RefreshHistory(*) {
        if !this.History || !this.History.Scopes.Length
            return
        state := this.History, selection := Map()
        for id in this.Selected()
            selection[id] := true
        scope := state.Scopes[Max(1, state.Scope.Value)]
        state.Rows := this.App.Store.List(scope.Channel, scope.History, state.Search.Value)
        state.List.Delete()
        for record in state.Rows {
            text := record.text != "" ? SubStr(StrReplace(StrReplace(record.text, "`r", ""), "`n", " | "), 1, 160) : "[" record.kind "]"
            row := state.List.Add(selection.Has(record.id) ? "Select" : "", (record.pinned ? "* " : "") text, record.kind, record.created, record.tag, record.bytes)
        }
        state.List.ModifyCol(1, 280), state.List.ModifyCol(2, 62), state.List.ModifyCol(3, 155), state.List.ModifyCol(4, 90), state.List.ModifyCol(5, 75)
        state.Status.SetText(state.Rows.Length " clips — " (scope.History ? "History" : this.App.Store.Channel(scope.Channel).name))
        this.HistoryPreview()
    }

    Selected() {
        ids := []
        if !this.History
            return ids
        row := 0
        while row := this.History.List.GetNext(row)
            if row <= this.History.Rows.Length
                ids.Push(this.History.Rows[row].id)
        return ids
    }

    HistoryPreview(*) {
        ids := this.Selected(), state := this.History
        if !IsObject(state)
            return
        state.Picture.Visible := false
        if !ids.Length {
            state.Preview.Value := this.App.Config.L("Select a clip to preview it.")
            return
        }
        try {
            record := this.App.Store.Get(ids[1]), snapshot := this.App.Store.Snapshot(record), formats := ""
            for entry in snapshot.Entries
                formats .= (formats = "" ? "" : ", ") (entry.Name != "" ? entry.Name : CJUI.StandardName(entry.Id))
            state.Preview.Value := record.text "`r`n`r`n" this.App.Config.L("Stored formats:") " " formats
            image := this.App.Store.Thumbnail(record)
            if FileExist(image) {
                state.Picture.Value := image
                state.Picture.Visible := true
            }
        } catch as err
            state.Preview.Value := this.App.Config.L("This archive cannot be read.") " " err.Message
    }

    static StandardName(id) {
        names := Map(1, "Text", 7, "OEM text", 8, "DIB", 13, "Unicode text", 15, "Files", 16, "Locale", 17, "DIBV5", 3, "Metafile", 14, "Enhanced metafile")
        return names.Has(id) ? names[id] : "Format " id
    }

    HistoryAction(action) {
        if action = "settings"
            return this.ShowSettings()
        if action = "import"
            return this.ImportArchive()
        ids := this.Selected(), state := this.History
        scope := state.Scopes[Max(1, state.Scope.Value)]
        if action = "clear" {
            if MsgBox("Clear the clips in this view?", "Clipjump Modern", "YesNo Icon?") = "Yes"
                this.App.Store.Clear(scope.Channel, scope.History)
            this.RefreshHistory()
            return
        }
        if !ids.Length
            return
        id := ids[1]
        switch action {
            case "paste":
                state.Gui.Hide()
                this.App.PasteIds(ids, this.LastTarget)
            case "copy": this.App.CopyClip(id)
            case "preview": this.ShowPreview(id)
            case "edit": this.ShowHold(id)
            case "formats": this.ShowFormats(id)
            case "export": this.ExportArchive(id)
            case "move", "copy-to": this.ShowMove(ids, scope.Channel, action = "copy-to")
            case "pin":
                if scope.History {
                    this.App.Store.AddMembership(id, this.App.Channel)
                    channel := this.App.Channel
                } else
                    channel := scope.Channel
                rows := this.App.Store.DB.Query("SELECT pinned FROM memberships WHERE channel_id=?1 AND clip_id=?2", [channel, id])
                this.App.Store.Pin(id, channel, !rows[1].pinned)
            case "tag":
                response := InputBox("Tag this clip", "Clipjump Modern", "w360 h140", this.App.Store.Get(id).tag)
                if response.Result = "OK"
                    this.App.Store.Tag(id, response.Value)
            case "delete":
                for selectedId in ids
                    this.App.Store.Remove(selectedId, scope.Channel, scope.History)
        }
        this.RefreshHistory()
    }

    ShowPreview(id, visible := true) {
        record := this.App.Store.Get(id), window := this.New("preview", "Clipjump Modern — Preview", "+Resize +MinSize480x300")
        text := window.AddEdit("w690 h190 ReadOnly Multi", record.text)
        snapshot := this.App.Store.Snapshot(id), formats := ""
        for entry in snapshot.Entries
            formats .= (formats = "" ? "" : ", ") (entry.Name != "" ? entry.Name : CJUI.StandardName(entry.Id))
        window.AddText("w690", "Formats: " formats)
        thumbnail := this.App.Store.Thumbnail(record)
        if FileExist(thumbnail)
            window.AddPicture("w500 h240", thumbnail)
        this.Button(window, "w100", "Copy", ObjBindMethod(this.App, "CopyClip", id))
        this.Button(window, "x+10 w100", "Paste", ObjBindMethod(this.App, "PasteIds", [id], this.LastTarget))
        if visible
            window.Show()
        return window
    }

    ShowHold(id := 0, visible := true) {
        this.LastTarget := this.App.ExternalTarget()
        snapshot := id ? this.App.Store.Snapshot(id) : this.App.LastSnapshot
        if !IsObject(snapshot)
            return
        window := this.New("hold", "Clipjump Modern — Hold / edit", "+AlwaysOnTop +Resize")
        window.AddText("w680", "Formatting is kept while the text is unchanged. Editing creates plain text.")
        edit := window.AddEdit("w680 h320 Multi", snapshot.Text)
        state := {Gui: window, Edit: edit, Original: snapshot, Id: id, Target: this.LastTarget}
        this.Button(window, "w100", "Copy", ObjBindMethod(this, "HoldResult", state, "copy"))
        this.Button(window, "x+10 w100", "Paste", ObjBindMethod(this, "HoldResult", state, "paste"))
        this.Button(window, "x+10 w140", id ? "Save changes" : "Add to channel", ObjBindMethod(this, "HoldResult", state, "save"))
        if visible
            window.Show()
        return window
    }

    HoldResult(state, action) {
        snapshot := state.Edit.Value = state.Original.Text ? state.Original : CJSnapshot.FromText(state.Edit.Value)
        switch action {
            case "save":
                if state.Id
                    this.App.Store.Replace(state.Id, snapshot)
                else
                    this.App.AddSnapshot(snapshot)
                this.RefreshHistory()
                state.Gui.Hide()
            case "copy": this.App.WriteClipboard(snapshot)
            case "paste":
                state.Gui.Hide()
                this.App.PasteSnapshot(snapshot, state.Target)
        }
    }

    ShowMove(ids, origin, copy := false, visible := true) {
        window := this.New("move", copy ? "Copy clips to channel" : "Move clips to channel", "")
        channels := this.App.Store.Channels(), names := []
        for channel in channels
            names.Push(channel.name)
        chooser := window.AddDropDownList("w340 Choose1", names)
        this.Button(window, "w100 Default", "OK", ObjBindMethod(this, "MoveResult", window, chooser, channels, ids, origin, copy))
        if visible
            window.Show()
        return window
    }
    MoveResult(window, chooser, channels, ids, origin, copy) {
        for id in ids
            this.App.Store.Move(id, origin, channels[chooser.Value].id, copy)
        window.Hide()
        this.RefreshHistory()
    }

    ShowChannels(visible := true) {
        window := this.New("channels", "Clipjump Modern — Channels", "+Resize")
        list := window.AddListView("w630 h270", ["Channel", "Clips", "Protected", "History"])
        rows := this.App.Store.Channels()
        for channel in rows
            list.Add("", channel.name, channel.count, channel.protected ? "Yes" : "No", channel.no_history ? "Excluded" : "Included")
        name := window.AddEdit("w630")
        protect := window.AddCheckbox("w300", "Confirm before capturing into this channel")
        noHistory := window.AddCheckbox("w300", "Exclude new clips from global history")
        state := {Gui: window, List: list, Name: name, Protected: protect, NoHistory: noHistory, Rows: rows}
        this.ChannelState := state
        list.OnEvent("ItemSelect", ObjBindMethod(this, "ChannelSelection", state))
        for index, action in ["Use", "Add", "Save", "Delete"]
            this.Button(window, (index = 1 ? "xm y+12" : "x+10 yp") " w100 h28", action, ObjBindMethod(this, "ChannelResult", state, action))
        if visible
            window.Show()
        return window
    }
    ChannelSelection(state, control, row, selected) {
        if !selected || row < 1 || row > state.Rows.Length
            return
        channel := state.Rows[row]
        state.Name.Value := channel.name
        state.Protected.Value := channel.protected
        state.NoHistory.Value := channel.no_history
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
                if id > 0 && MsgBox("Delete this channel? Clips retained in History remain available.", "Clipjump Modern", "YesNo Icon?") = "Yes" {
                    if this.App.Channel = id
                        this.App.SetChannel(0)
                    this.App.Store.DeleteChannel(id)
                }
        }
        this.ShowChannels()
        this.RefreshHistory()
    }

    ShowSettings(visible := true) {
        window := this.New("settings", "Clipjump Modern — Settings", ""), controls := Map()
        for name, label in Map("Monitoring", "Capture clipboard changes", "Incognito", "Private mode: stop capture", "Deduplicate", "Skip consecutive identical clips", "CopyMessage", "Show capture confirmation", "PreservePosition", "Remember paste-mode position") {
            control := window.AddCheckbox("w580", label)
            control.Value := this.App.Config.Get(name)
            controls[name] := control
        }
        for name, label in Map("HistoryDays", "History days (0 disables new history)", "MaximumChannelClips", "Maximum unpinned clips per channel") {
            window.AddText("w360", label)
            controls[name] := window.AddEdit("x+10 yp-3 w100 Number", this.App.Config.Get(name))
            window.AddText("xm w1 h1")
        }
        for name, label in Map("PasteHotkey", "Paste mode", "HistoryHotkey", "History", "ActionHotkey", "Action menu", "ChannelsHotkey", "Channels", "PlainHotkey", "Paste plain text") {
            window.AddText("xm w220", label)
            controls[name] := window.AddHotkey("x+10 yp-3 w240", this.App.Config.Get(name))
        }
        window.AddText("xm w220", "Default paste format")
        formats := this.App.Plugins.Formats(), names := [], chosen := 1
        for index, format in formats {
            names.Push(this.App.Config.L(format.Name))
            if format.Id = this.App.Config.Get("DefaultFormat")
                chosen := index
        }
        controls["DefaultFormat"] := window.AddDropDownList("x+10 yp-3 w300 Choose" chosen, names)
        window.AddText("xm w220", "Language")
        languages := [], chosenLanguage := 1
        Loop Files this.App.Root "\languages\*.txt", "F" {
            language := SubStr(A_LoopFileName, 1, -4)
            languages.Push(language)
            if StrLower(language) = StrLower(this.App.Config.Get("Language"))
                chosenLanguage := languages.Length
        }
        if !languages.Length
            languages := ["english"]
        controls["Language"] := window.AddDropDownList("x+10 yp-3 w300 Choose" chosenLanguage, languages)
        state := {Gui: window, Controls: controls, Formats: formats, Languages: languages}
        this.Button(window, "xm w100 Default", "Save", ObjBindMethod(this, "SaveSettings", state))
        this.Button(window, "x+10 w160", "Ignored windows…", ObjBindMethod(this, "ShowIgnored"))
        this.Button(window, "x+10 w160", "Import v1 data…", ObjBindMethod(this, "ShowLegacyImport"))
        if visible
            window.Show()
        return window
    }
    SaveSettings(state) {
        values := this.App.Config.Values.Clone()
        for name, control in state.Controls {
            if name = "DefaultFormat"
                values[name] := state.Formats[control.Value].Id
            else if name = "Language"
                values[name] := state.Languages[control.Value]
            else if Type(values[name]) = "Integer"
                values[name] := Integer(control.Value)
            else
                values[name] := control.Value
        }
        this.App.ApplySettings(values)
        state.Gui.Hide()
    }

    ShowIgnored(visible := true) {
        window := this.New("ignored", "Clipjump Modern — Ignored windows", "")
        window.AddText("w580", "Process names, one per line (for example EXCEL.EXE)")
        processes := window.AddEdit("w580 h120 Multi", StrReplace(this.App.Config.Get("IgnoredProcesses"), "|", "`r`n"))
        window.AddText("w580", "Window classes, one per line")
        classes := window.AddEdit("w580 h120 Multi", StrReplace(this.App.Config.Get("IgnoredClasses"), "|", "`r`n"))
        this.Button(window, "w100 Default", "Save", ObjBindMethod(this, "SaveIgnored", window, processes, classes))
        if visible
            window.Show()
        return window
    }
    SaveIgnored(window, processes, classes) {
        this.App.Config.Set("IgnoredProcesses", StrReplace(StrReplace(processes.Value, "`r", ""), "`n", "|"))
        this.App.Config.Set("IgnoredClasses", StrReplace(StrReplace(classes.Value, "`r", ""), "`n", "|"))
        window.Hide()
    }

    ShowPlugins(visible := true) {
        window := this.New("plugins", "Clipjump Modern — Plugins", "+Resize")
        list := window.AddListView("w690 h360", ["Plugin", "Type", "Identifier"]), items := []
        for id, plugin in this.App.Plugins.Items {
            items.Push(plugin)
            list.Add("", this.App.Config.L(plugin.Name), this.App.Config.L(plugin.Kind), id)
        }
        this.Button(window, "w100 Default", "Run", ObjBindMethod(this, "RunSelectedPlugin", list, items))
        this.Button(window, "x+10 w150", "Custom shortcuts…", ObjBindMethod(this, "ShowIni", "custom"))
        if visible
            window.Show()
        return window
    }
    RunSelectedPlugin(list, items) {
        row := list.GetNext()
        if !row
            return
        plugin := items[row]
        if plugin.Kind = "format"
            this.ShowFormats(0, true, plugin.Id)
        else
            this.App.Plugins.Run(plugin.Id)
    }

    ShowFormats(id := 0, visible := true, selected := "", sourceSnapshot := false) {
        this.LastTarget := this.App.ExternalTarget()
        snapshot := IsObject(sourceSnapshot) ? sourceSnapshot : id ? this.App.Store.Snapshot(id) : this.App.LastSnapshot
        if !IsObject(snapshot)
            snapshot := CJSnapshot.FromText("")
        window := this.New("formats", "Clipjump Modern — Common Formats", "+Resize")
        formats := this.App.Plugins.Formats(), names := [], chosen := 1
        for index, format in formats {
            names.Push(this.App.Config.L(format.Name))
            if format.Id = selected
                chosen := index
        }
        chooser := window.AddDropDownList("w690 Choose" chosen, names)
        window.AddText("w690", "Source text")
        source := window.AddEdit("w690 h150 Multi", snapshot.Text)
        window.AddText("w690", "Parameter (regex: pattern on line 1, replacement on line 2)")
        parameter := window.AddEdit("w690 h55 Multi")
        window.AddText("w690", "Result")
        result := window.AddEdit("w690 h170 ReadOnly Multi")
        state := {Gui: window, Chooser: chooser, Formats: formats, Source: source, Parameter: parameter, Result: result, Snapshot: snapshot, Target: this.LastTarget}
        for control in [chooser, source, parameter]
            control.OnEvent("Change", (*) => this.FormatPreview(state))
        this.Button(window, "w100 Default", "Copy result", ObjBindMethod(this, "UseFormat", state, false))
        this.Button(window, "x+10 w100", "Paste result", ObjBindMethod(this, "UseFormat", state, true))
        this.FormatPreview(state)
        if visible
            window.Show()
        return window
    }
    FormatPreview(state) {
        try state.Result.Value := this.App.Plugins.Transform(state.Formats[state.Chooser.Value].Id, state.Source.Value, state.Parameter.Value)
        catch as err
            state.Result.Value := this.App.Config.L("Format error:") " " err.Message
    }
    UseFormat(state, paste) {
        format := state.Formats[state.Chooser.Value].Id
        text := this.App.Plugins.Transform(format, state.Source.Value, state.Parameter.Value)
        snapshot := format = "none" && state.Source.Value = state.Snapshot.Text ? state.Snapshot : CJSnapshot.FromText(text)
        if paste {
            state.Gui.Hide()
            this.App.PasteSnapshot(snapshot, state.Target)
        } else
            this.App.WriteClipboard(snapshot)
    }

    ShowIni(which := "settings", visible := true) {
        file := which = "hotpaste" ? this.App.Config.HotPasteFile : which = "custom" ? this.App.Config.CustomFile : this.App.Config.File
        if !FileExist(file) {
            template := which = "hotpaste" ? "[Text]`r`ncj_site=https://github.com/ariadne-coil/Clipjump-`r`n`r`n[Clips]`r`n; first=0,1`r`n" : which = "custom" ? "[Hotkeys]`r`n; ^!h=history`r`n`r`n[AutoRun]`r`n; 1=monitor:on`r`n" : "[General]`r`n"
            FileAppend(template, file, "UTF-16")
        }
        window := this.New("ini", "Clipjump Modern — " (which = "hotpaste" ? "Hotstring-Paste" : "Configuration editor"), "+Resize")
        edit := window.AddEdit("w740 h460 Multi -Wrap", FileRead(file))
        this.Button(window, "w150 Default", "Save and reload", ObjBindMethod(this, "SaveIni", window, edit, file))
        if visible
            window.Show()
        return window
    }
    SaveIni(window, edit, file) {
        temporary := file ".pending"
        stream := FileOpen(temporary, "w", "UTF-16")
        stream.Write(edit.Value), stream.Close()
        FileMove(temporary, file, 1)
        window.Hide()
        this.App.ReloadConfiguration()
    }

    ShowLegacyImport(visible := true) {
        window := this.New("legacy", "Clipjump Modern — Import v1 data", "")
        window.AddText("w650", "Choose the old Clipjump folder. Its files will be read without modification.")
        window.AddText("w650", "Standard text, images and file lists can be recovered across architectures. Registered formatting can only be recovered reliably in the original Windows session.")
        registered := window.AddCheckbox("w650", "Recover registered formats from this same Windows session")
        this.Button(window, "w180 Default", "Choose folder and import", ObjBindMethod(this, "ImportLegacyResult", window, registered))
        if visible
            window.Show()
        return window
    }
    ImportLegacyResult(window, registered) {
        directory := DirSelect(this.App.Root, 0, "Select the old Clipjump folder")
        if directory = ""
            return
        report := this.App.ImportLegacy(directory, registered.Value)
        MsgBox("Imported: " report.Imported "`nAlready imported: " report.Skipped "`nCould not recover: " report.Failed, "Clipjump Modern")
        window.Hide()
        this.RefreshHistory()
    }

    ExportArchive(id) {
        path := FileSelect("S16", "clip.cjc", "Export rich clip", "Clipjump archives (*.cjc)")
        if path != ""
            this.App.Store.Snapshot(id).Save(path)
    }
    ImportArchive() {
        path := FileSelect(1, , "Import rich clip", "Clipjump archives (*.cjc; *.avc)")
        if path = ""
            return
        SplitPath(path, , , &extension)
        snapshot := StrLower(extension) = "avc" ? CJLegacyImport.Snapshot(path) : CJSnapshot.Load(path)
        this.App.AddSnapshot(snapshot)
        this.RefreshHistory()
    }

    ShowTranslations(visible := true) {
        path := FileSelect(1, this.App.Root "\languages", "Inspect a translation", "Translation files (*.txt)")
        if path = ""
            return
        keys := Map(), duplicates := ""
        for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
            line := Trim(line)
            if line = "" || SubStr(line, 1, 1) = ";" || !InStr(line, "=")
                continue
            key := Trim(SubStr(line, 1, InStr(line, "=") - 1))
            if keys.Has(key)
                duplicates .= key "`r`n"
            keys[key] := true
        }
        window := this.New("translations", "Clipjump Modern — Translation File Cleaner", "+Resize")
        window.AddEdit("w650 h380 ReadOnly Multi", this.App.Config.L("Duplicate keys:") "`r`n" (duplicates != "" ? duplicates : this.App.Config.L("None")) "`r`n`r`n" this.App.Config.L("Unique keys:") " " keys.Count "`r`n" this.App.Config.L("The source file was not changed."))
        if visible
            window.Show()
        return window
    }

    ShowOverlay(record, index, total, format) {
        if !this.Overlay {
            window := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x20", "Clipjump Paste Mode")
            window.SetFont("s10", "Segoe UI")
            window.BackColor := "F5F6FA"
            label := window.AddText("w460 h120", "")
            this.Overlay := {Gui: window, Label: label}
        }
        this.Overlay.Label.Value := "{" this.App.Store.Channel(this.App.Channel).name "}  Clip " index " of " total "  [" format "]`n`n" SubStr(record.text != "" ? record.text : "[" record.kind "]", 1, 240) "`n`nV/C browse   Z format   X cancel   F search"
        MouseGetPos(&x, &y)
        this.Overlay.Gui.Show("NoActivate AutoSize x" Max(0, Min(A_ScreenWidth - 500, x + 18)) " y" Max(0, Min(A_ScreenHeight - 200, y + 18)))
    }
    HideOverlay() {
        if this.Overlay
            this.Overlay.Gui.Hide()
    }
    Destroy() {
        if this.History {
            HotIfWinActive("ahk_id " this.History.Gui.Hwnd)
            for key in ["$Space", "$^c", "$Delete", "$^f", "$F5"]
                try Hotkey(key, "Off")
            HotIfWinActive()
        }
        for name, window in this.Windows
            try window.Destroy()
        this.Windows.Clear(), this.History := false
        if this.Overlay
            this.Overlay.Gui.Destroy()
        this.Overlay := false
    }
}
