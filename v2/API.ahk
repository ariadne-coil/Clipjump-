#Requires AutoHotkey v2.0.31+
class CJAPIServer {
    static Receive(app, sender, structure) {
        try {
            bytes := NumGet(structure, A_PtrSize, "UInt"), pointer := NumGet(structure, 2 * A_PtrSize, "Ptr")
            if !pointer || bytes < 2 || bytes > 1048576 || Mod(bytes, 2)
                return 0
            message := StrGet(pointer, bytes // 2, "UTF-16")
            if SubStr(message, 1, 4) = "CJ2:" {
                fields := StrSplit(message, "`r")
                token := SubStr(fields[1], 5)
                pid := 0
                DllCall("GetWindowThreadProcessId", "Ptr", sender, "UInt*", &pid)
                if !pid || !RegExMatch(token, "^[a-f0-9]{8,64}$") || fields.Length < 2 || fields.Length > 20
                    return 0
                path := A_Temp "\ClipjumpV2-" pid "-" token ".txt"
                parameters := []
                loop fields.Length - 2
                    parameters.Push(this.Decode(fields[A_Index + 2]))
                try result := "OK`n" String(this.Invoke(app, fields[2], parameters))
                catch as err
                    result := "ERROR`n" err.Message
                file := FileOpen(path, "w", "UTF-8-RAW")
                file.Write(result), file.Close()
                return 1
            }
            if SubStr(message, 1, 4) = "API:" {
                fields := StrSplit(SubStr(message, 5), "`r"), parameters := []
                loop fields.Length - 1
                    parameters.Push(fields[A_Index + 1])
                try result := String(this.Invoke(app, fields[1], parameters))
                catch as err
                    result := "ERROR: " err.Message
                file := FileOpen(A_Temp "\cjcb.txt", "w", "UTF-8-RAW")
                file.Write(result), file.Close()
                file := FileOpen(A_Temp "\clipjumpcom.txt", "w", "UTF-8-RAW")
                file.Write("1"), file.Close()
                return 1
            }
        }
        return 0
    }

    static Encode(text) {
        text := StrReplace(text, "\", "\\")
        text := StrReplace(text, "`r", "\r")
        return StrReplace(text, "`n", "\n")
    }
    static Decode(text) {
        result := "", index := 1
        while index <= StrLen(text) {
            character := SubStr(text, index, 1)
            if character = "\" && index < StrLen(text) {
                index += 1
                following := SubStr(text, index, 1)
                result .= following = "r" ? "`r" : following = "n" ? "`n" : following
            } else
                result .= character
            index += 1
        }
        return result
    }
    static Argument(parameters, index, fallback := "") => parameters.Length >= index ? parameters[index] : fallback
    static Defer(app, action) {
        SetTimer(ObjBindMethod(app, "MenuAction", action), -10)
        return 1
    }
    static Indexed(app, parameters) {
        channel := app.Store.ChannelId(this.Argument(parameters, 1, app.Channel))
        index := Integer(this.Argument(parameters, 2, 1)), rows := app.Store.List(channel)
        if index < 1 || index > rows.Length
            throw Error("Clip index is out of range.")
        return rows[index]
    }
    static Invoke(app, method, parameters) {
        method := StrLower(method)
        switch method {
            case "getvar":
                name := StrLower(this.Argument(parameters, 1))
                switch name {
                    case "version": return CJApp.Version
                    case "progname": return "Clipjump Modern"
                    case "cn.ng", "channel": return app.Channel
                    case "caller", "caller_status", "clipjump_status": return app.Config.Get("Monitoring") && !app.Config.Get("Incognito") && !app.BlockCount
                    case "ini_monitorclipboard": return app.Config.Get("Monitoring")
                    case "noincognito": return !app.Config.Get("Incognito")
                    case "product_page": return CJApp.ProjectPage
                    case "ini_daystostore": return app.Config.Get("HistoryDays")
                    default:
                        if SubStr(name, 1, 4) = "txt."
                            return app.Config.T(SubStr(this.Argument(parameters, 1), 5), SubStr(this.Argument(parameters, 1), 5))
                        throw Error("This v1 global is not exposed by the v2 API.")
                }
            case "getclipat": return this.Indexed(app, parameters).text
            case "getcliploc": return app.Store.Path(this.Indexed(app, parameters))
            case "getchstrength": return app.Store.List(app.Store.ChannelId(this.Argument(parameters, 1, app.Channel)), false, "", 100000).Length
            case "getchannel": return app.Channel
            case "changechannel": app.SetChannel(app.Store.ChannelId(this.Argument(parameters, 1, 0)))
            case "paste": return this.Defer(app, "paste:" this.Argument(parameters, 1, app.Channel) "," this.Argument(parameters, 2, 1))
            case "pastetext": return this.Defer(app, "text:" this.Argument(parameters, 1))
            case "incognitomode": app.ToggleSetting("Incognito", this.Argument(parameters, 1))
            case "disable": app.ToggleSetting("Monitoring", this.Argument(parameters, 1, "1") = "1" ? "off" : "on")
            case "blockmonitoring": app.BlockCount := this.Argument(parameters, 1, "1") = "1" ? 1 : 0
            case "emptychannel": app.Store.Clear(app.Store.ChannelId(this.Argument(parameters, 1, app.Channel)))
            case "setvar":
                name := StrLower(this.Argument(parameters, 1)), value := this.Argument(parameters, 2)
                if name = "caller" || name = "ini_monitorclipboard"
                    app.ToggleSetting("Monitoring", value)
                else
                    throw Error("This v1 global cannot be assigned through the v2 API.")
            case "runplugin":
                id := RegExReplace(this.Argument(parameters, 1), "i)\.ahk$", "")
                if app.Plugins.Items.Has(id) && app.Plugins.Items[id].Kind = "format"
                    return app.Plugins.Transform(id, this.Argument(parameters, 2, app.CurrentText()), this.Argument(parameters, 3))
                return this.Defer(app, "plugin:" id)
            case "runfunction":
                action := this.Argument(parameters, 1)
                aliases := Map("gui_History()", "history", "channelOrganizer()", "channels", "gui_Settings()", "settings", "pluginManagerGUI()", "plugins")
                if aliases.Has(action)
                    return this.Defer(app, aliases[action])
                throw Error("Use native v2 callbacks or registered actions instead of evaluated v1 function strings.")
            case "action": return this.Defer(app, this.Argument(parameters, 1))
            default: throw Error("Unsupported Clipjump API operation: " method)
        }
        app.UI.RefreshHistory()
        return 1
    }
}
