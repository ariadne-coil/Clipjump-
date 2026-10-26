#Requires AutoHotkey v2.0.31+
; Native v2 equivalents of the bundled Clipjump format and maintenance plugins.
class CJPlugins {
    __New(app) {
        this.App := app, this.Items := Map()
        this.Register("none", "Keep original formatting", (text, parameter := "") => text)
        this.Register("plain", "Trim formatting", (text, parameter := "") => RTrim(text, "`r`n"))
        this.Register("trim", "Trim white space", (text, parameter := "") => Trim(text, " `t`r`n"))
        this.Register("upper", "UPPERCASE", (text, parameter := "") => StrUpper(text))
        this.Register("lower", "lowercase", (text, parameter := "") => StrLower(text))
        this.Register("sentence", "Sentence case", ObjBindMethod(CJPlugins, "Sentence"))
        this.Register("numbered", "Numbered list", ObjBindMethod(CJPlugins, "Numbered"))
        this.Register("html-list", "HTML list", (text, parameter := "") => RegExReplace(Trim(text, " `t`r`n"), "m)^", "<li>"))
        this.Register("bbcode-list", "BBCode list", (text, parameter := "") => RegExReplace(Trim(text, " `t`r`n"), "m)^", "[*]"))
        this.Register("escape-html", "Escape HTML", ObjBindMethod(CJPlugins, "EscapeHTML"))
        this.Register("unhtml", "HTML to plain text", ObjBindMethod(CJPlugins, "UnHTML"))
        this.Register("regex", "Regular expression replacement", ObjBindMethod(CJPlugins, "Regex"))
        commands := [
            ["commonformats", "Common Formats", "formats"],
            ["noformatting_paste", "NoFormatting Paste", "plain"],
            ["hotPaste", "Hotstring-Paste", "hotpaste"],
            ["updateClipjumpClipboard", "Sync Clipjump Clipboard", "sync"],
            ["deleteFileFolder", "Delete file/folder clips", "delete-files"],
            ["external.ignoreWmanager", "Ignored Windows Manager", "ignore"],
            ["external.historyPathClean", "History file paths cleaner", "history-paths"],
            ["external.inieditor", "INI Editor", "ini"],
            ["external.translationFileCleaner", "Translation File Cleaner", "translations"]]
        for command in commands
            this.Register(command[1], command[2], ObjBindMethod(app, "Action", command[3]), "command")
        global CJ_UserPluginLoader
        if IsSet(CJ_UserPluginLoader) && IsObject(CJ_UserPluginLoader)
            CJ_UserPluginLoader.Call(this)
    }

    Register(id, name, callback, kind := "format") {
        if !RegExMatch(id, "^[\w.-]+$") || !HasMethod(callback, "Call") || (kind != "format" && kind != "command")
            throw Error("Invalid v2 plugin registration.")
        this.Items[id] := {Id: id, Name: name, Callback: callback, Kind: kind}
    }
    Formats() {
        formats := []
        for id, plugin in this.Items
            if plugin.Kind = "format"
                formats.Push(plugin)
        return formats
    }
    Transform(id, text, parameter := "") {
        if !this.Items.Has(id) || this.Items[id].Kind != "format"
            throw Error("Unknown paste format: " id)
        return this.Items[id].Callback.Call(text, parameter)
    }
    Run(id, parameters*) {
        id := RegExReplace(id, "i)\.ahk$", "")
        aliases := Map("pformat.commonformats", "commonformats", "pformat.noformatting", "plain", "pformat.sentencecase", "sentence")
        if aliases.Has(id)
            id := aliases[id]
        if !this.Items.Has(id)
            throw Error("This plugin requires a native AHK v2 port: " id)
        plugin := this.Items[id]
        if plugin.Kind = "format"
            return this.Transform(id, parameters.Length ? parameters[1] : this.App.CurrentText(), parameters.Length > 1 ? parameters[2] : "")
        return plugin.Callback.Call(parameters*)
    }

    static Sentence(text, parameter := "") {
        result := "", capitalize := true
        for character in StrSplit(StrLower(text)) {
            if capitalize && RegExMatch(character, "[\p{L}]") {
                result .= StrUpper(character)
                capitalize := false
            } else
                result .= character
            if InStr(".!?`r`n", character)
                capitalize := true
        }
        return result
    }
    static Numbered(text, parameter := "") {
        result := ""
        for index, line in StrSplit(Trim(text, " `t`r`n"), "`n", "`r")
            result .= (index > 1 ? "`r`n" : "") index ". " line
        return result
    }
    static EscapeHTML(text, parameter := "") {
        text := StrReplace(text, "&", "&amp;")
        text := StrReplace(text, "<", "&lt;")
        text := StrReplace(text, ">", "&gt;")
        text := StrReplace(text, '"', "&quot;")
        return StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "<br>")
    }
    static UnHTML(text, parameter := "") {
        ; Parse text only. Never load pasted markup into an executable browser.
        text := RegExReplace(text, "is)<(script|style)\b[^>]*>.*?</\1\s*>", "")
        text := RegExReplace(text, "i)<br\s*/?>|</(?:p|div|li|tr)\s*>", "`n")
        text := RegExReplace(text, "s)<[^>]*>", "")
        entities := Map("amp", "&", "lt", "<", "gt", ">", "quot", '"', "apos", "'", "nbsp", " ")
        position := 1
        while RegExMatch(text, "i)&(#x[\da-f]+|#\d+|\w+);", &match, position) {
            token := match[1], value := match[0]
            try {
                if SubStr(token, 1, 2) = "#x"
                    value := Chr(Integer("0x" SubStr(token, 3)))
                else if SubStr(token, 1, 1) = "#"
                    value := Chr(Integer(SubStr(token, 2)))
                else if entities.Has(token)
                    value := entities[token]
            }
            text := SubStr(text, 1, match.Pos - 1) value SubStr(text, match.Pos + match.Len)
            position := match.Pos + StrLen(value)
        }
        return Trim(text, " `t`r`n")
    }
    static Regex(text, parameter := "") {
        lines := StrSplit(parameter, "`n", "`r", 2)
        if !lines.Length
            return text
        return RegExReplace(text, lines[1], lines.Length > 1 ? lines[2] : "")
    }
}
