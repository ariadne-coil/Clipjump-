#Requires AutoHotkey v2.0.31+
class CJConfig {
    __New(root, dataDirectory := "") {
        root := CJConfig.FullPath(root)
        this.Root := root
        this.File := root "\settings-v2.ini"
        this.CustomFile := root "\ClipjumpCustom-v2.ini"
        this.HotPasteFile := root "\HotPaste-v2.ini"
        this.Data := CJConfig.FullPath(dataDirectory != "" ? dataDirectory : root "\cache-v2")
        DirCreate(this.Data)
        this.Values := Map("Monitoring", 1, "Incognito", 0, "HistoryDays", 30, "MaximumChannelClips", 100,
            "Deduplicate", 0, "CopyMessage", 1, "PreservePosition", 0, "Channel", 0, "DefaultFormat", "none",
            "PasteHotkey", "^v", "HistoryHotkey", "^+h", "ActionHotkey", "^+a", "ChannelsHotkey", "^+o",
            "PlainHotkey", "^!v", "IgnoredProcesses", "", "IgnoredClasses", "", "Language", "english",
            "KeepSession", 1, "StoreImages", 1, "ClipThreshold", 1, "LimitAllChannels", 0, "ThumbnailQuality", 90,
            "RememberFormat", 1, "LastFormat", "", "StartSearch", 0, "PartialSearch", 0, "HistoryCloseOnPaste", 1,
            "IncognitoStopsCapture", 0, "ManualCaptureOnly", 0, "WinCopyCut", 0, "CopyBeep", 0, "BeepFrequency", 1500,
            "ShowPasteTip", 1, "ShowPastingTip", 0, "PasteX", "", "PasteY", "", "TextEditor", "notepad.exe",
            "ImageEditor", "mspaint.exe", "ProcessPriority", "Normal", "RAMFlush", 0, "StartWithWindows", 0,
            "PitSwapHotkey", "", "OneTimeHotkey", "", "SystemCopyHotkey", "", "SystemCutHotkey", "",
            "HoldHotkey", "", "CopyFilesHotkey", "", "CopyFolderHotkey", "", "CopyDataHotkey", "", "PluginHotkey", "",
            "NextKey", "v", "PreviousKey", "c", "ModeKey", "x", "FormatKey", "z", "PlainKey", "p",
            "SearchKey", "f", "ClipboardKey", "s", "FirstKey", "a", "FrontKey", "q", "PinKey", "Space",
            "TagKey", "t", "EditKey", "h", "ExportKey", "e", "HelpKey", "F1", "FeatureSchema", 2)
        for name, fallback in this.Values {
            value := IniRead(this.File, "General", name, fallback)
            if Type(fallback) = "Integer"
                value := RegExMatch(value, "^-?\d+$") ? Integer(value) : fallback
            this.Values[name] := value
        }
        this.Values["HistoryDays"] := Max(0, Min(36500, this.Values["HistoryDays"]))
        this.Values["MaximumChannelClips"] := Max(0, Min(100000, this.Values["MaximumChannelClips"]))
        for name, range in Map("ClipThreshold", [1, 100000], "ThumbnailQuality", [1, 100], "BeepFrequency", [37, 32767])
            this.Values[name] := Max(range[1], Min(range[2], this.Values[name]))
        if !InStr("|Low|BelowNormal|Normal|AboveNormal|High|Realtime|", "|" this.Values["ProcessPriority"] "|")
            this.Values["ProcessPriority"] := "Normal"
        ; Preserve the stronger private mode selected in beta.1 during upgrade.
        if FileExist(this.File) && IniRead(this.File, "General", "FeatureSchema", 0) < 2 && this.Get("Incognito")
            this.Values["IncognitoStopsCapture"] := 1
        this.Values["FeatureSchema"] := 2
        this.Translations := Map()
        this.LoadLanguage()
    }

    Get(name) => this.Values[name]
    static FullPath(path) {
        pathBuffer := Buffer(65536)
        length := DllCall("GetFullPathNameW", "Str", path, "UInt", 32768, "Ptr", pathBuffer, "Ptr", 0)
        if !length || length >= 32768
            throw Error("Invalid data directory.")
        return RTrim(StrGet(pathBuffer), "\")
    }
    Set(name, value, persist := true) {
        this.Values[name] := value
        if persist
            IniWrite(value, this.File, "General", name)
    }
    Save() {
        for name, value in this.Values
            IniWrite(value, this.File, "General", name)
    }

    LoadLanguage() {
        this.Translations := Map()
        language := this.Get("Language")
        if !RegExMatch(language, "^[\p{L}\p{N}_-]+$")
            language := "english"
        base := this.HasOwnProp("LanguageRoot") ? this.LanguageRoot : this.Root
        path := base "\languages\" language ".txt"
        if !FileExist(path)
            return
        for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
            line := Trim(line)
            if line = "" || SubStr(line, 1, 1) = ";" || !InStr(line, "=")
                continue
            key := Trim(SubStr(line, 1, InStr(line, "=") - 1))
            this.Translations[key] := Trim(SubStr(line, InStr(line, "=") + 1))
        }
        this.Labels := CJLabels.Load(base, language, this.Translations)
    }

    T(key, fallback) => this.Translations.Has(key) ? this.Translations[key] : fallback
    L(text) => this.HasOwnProp("Labels") ? CJLabels.Translate(this.Labels, text) : text

    Ignored(process, className := "") {
        for name in StrSplit(StrReplace(this.Get("IgnoredProcesses"), "`n", "|"), "|", " `t`r")
            if name != "" && StrLower(name) = StrLower(process)
                return true
        for name in StrSplit(StrReplace(this.Get("IgnoredClasses"), "`n", "|"), "|", " `t`r")
            if name != "" && StrLower(name) = StrLower(className)
                return true
        return false
    }
}

CJNewId() {
    guid := Buffer(16), text := Buffer(78)
    if DllCall("ole32\CoCreateGuid", "Ptr", guid) != 0
        throw Error("Unable to create a clip identifier.")
    DllCall("ole32\StringFromGUID2", "Ptr", guid, "Ptr", text, "Int", 39)
    return StrLower(RegExReplace(StrGet(text), "[{}-]"))
}

CJNow() => FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
