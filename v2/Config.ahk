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
            "PlainHotkey", "^!v", "IgnoredProcesses", "", "IgnoredClasses", "", "Language", "english")
        for name, fallback in this.Values {
            value := IniRead(this.File, "General", name, fallback)
            if Type(fallback) = "Integer"
                value := RegExMatch(value, "^-?\d+$") ? Integer(value) : fallback
            this.Values[name] := value
        }
        this.Values["HistoryDays"] := Max(0, Min(36500, this.Values["HistoryDays"]))
        this.Values["MaximumChannelClips"] := Max(1, Min(100000, this.Values["MaximumChannelClips"]))
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
        if !RegExMatch(language, "^[\w-]+$")
            language := "english"
        path := this.Root "\languages\" language ".txt"
        if !FileExist(path)
            return
        for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
            line := Trim(line)
            if line = "" || SubStr(line, 1, 1) = ";" || !InStr(line, "=")
                continue
            key := Trim(SubStr(line, 1, InStr(line, "=") - 1))
            this.Translations[key] := Trim(SubStr(line, InStr(line, "=") + 1))
        }
    }

    T(key, fallback) => this.Translations.Has(key) ? this.Translations[key] : fallback

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
