#Requires AutoHotkey v2.0.31+
class CJLabels {
    static Normalize(text) => Trim(StrReplace(StrReplace(text, "&", ""), "`t", " "))
    static Read(path) {
        result := Map(), result.CaseSense := false
        if !FileExist(path)
            return result
        for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
            split := InStr(line, "=")
            if !split || SubStr(Trim(line), 1, 1) = ";"
                continue
            key := StrReplace(Trim(SubStr(line, 1, split - 1)), "\e", "="), value := Trim(SubStr(line, split + 1))
            if key != ""
                result[key] := StrReplace(value, "\n", "`n")
        }
        return result
    }
    static Load(root, language, translations) {
        result := Map(), result.CaseSense := false
        english := this.Read(root "\languages\english.txt")
        for key, value in english
            if translations.Has(key) && value != ""
                result[this.Normalize(value)] := this.Normalize(translations[key])
        overlay := this.Read(root "\languages-v2\" language ".txt")
        for key, value in overlay
            result[this.Normalize(key)] := value
        return result
    }
    static Translate(labels, text) {
        key := this.Normalize(text)
        if labels.Has(key)
            return labels[key]
        if InStr(text, "Clipjump Modern — ") = 1
            return "Clipjump Modern — " this.Translate(labels, SubStr(text, 19))
        return text
    }
}

; Translate application labels only. Clipboard contents and user names are edits
; or explicit data controls and are never sent through this wrapper.
class CJWindow {
    __New(config, options, title) {
        this.DefineProp("Native", {Value: Gui(options, config.L(title))})
        this.DefineProp("Config", {Value: config})
        this.DefineProp("Labels", {Value: []})
        this.DefineProp("OriginalTitle", {Value: title})
    }
    __Get(name, parameters) => parameters.Length ? this.Native.%name%[parameters*] : this.Native.%name%
    __Set(name, parameters, value) => this.Native.%name% := value
    __Call(name, parameters) {
        original := ""
        if RegExMatch(name, "i)^Add(Text|Button|Checkbox|GroupBox)$") && parameters.Length >= 2
            original := parameters[2], parameters[2] := this.Config.L(parameters[2])
        if (name = "AddListView" || name = "AddTab3") && parameters.Length >= 2 {
            translated := []
            for value in parameters[2]
                translated.Push(this.Config.L(value))
            parameters[2] := translated
        }
        if name = "Show"
            this.RefreshLabels()
        result := this.Native.%name%(parameters*)
        if original != ""
            this.Labels.Push({Control: result, Text: original})
        return result
    }
    RefreshLabels() {
        this.Native.Title := this.Config.L(this.OriginalTitle)
        for item in this.Labels
            try item.Control.Text := this.Config.L(item.Text)
    }
}
