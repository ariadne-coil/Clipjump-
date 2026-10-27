#Requires AutoHotkey v2.0.31+
class CJExplorer {
    static Resolve(hwnd) {
        if !hwnd
            return false
        shell := ComObject("Shell.Application")
        for window in shell.Windows {
            try {
                if window.HWND != hwnd
                    continue
                paths := []
                for item in window.Document.SelectedItems
                    paths.Push(item.Path)
                return {Paths: paths, Folder: window.Document.Folder.Self.Path}
            }
        }
        try className := WinGetClass("ahk_id " hwnd)
        catch
            return false
        if className = "Progman" || className = "WorkerW" {
            ; Desktop is a normal Shell folder, not a file-picker fallback.
            paths := []
            try {
                desktop := shell.Windows.FindWindowSW(0, 0, 8, 0, 1)
                for item in desktop.Document.SelectedItems
                    paths.Push(item.Path)
            }
            return {Paths: paths, Folder: A_Desktop}
        }
        return false
    }
    static Paths(snapshot) {
        paths := []
        for line in StrSplit(snapshot.Text, "`n", "`r") {
            path := Trim(line, ' `t"')
            if RegExMatch(path, "i)^(?:[a-z]:\\|\\\\)") && FileExist(path)
                paths.Push(path)
        }
        return paths
    }
    static Read(path) {
        if InStr(FileExist(path), "D")
            throw Error("Select a file to copy its contents.")
        if FileGetSize(path) > 67108864
            throw Error("File data exceeds the 64 MiB limit.")
        SplitPath(path, , , &extension)
        if RegExMatch(extension, "i)^(png|jpe?g|bmp|gif|tiff?)$")
            return CJImage.FromFile(path)
        if StrLower(extension) = "cjc"
            return CJSnapshot.Load(path)
        return CJSnapshot.FromText(FileRead(path))
    }
}

class CJSystem {
    static StartupPath(directory := "") => (directory != "" ? directory : A_Startup) "\Clipjump Modern v2.lnk"
    static Startup(root, enabled, compiled := false, runtime := "", directory := "") {
        link := this.StartupPath(directory)
        if enabled {
            target := compiled ? root "\Clipjump.exe" : runtime
            arguments := compiled ? "" : '"' root '\Clipjump.ahk"'
            if !FileExist(target)
                throw Error("The application executable cannot be found.")
            FileCreateShortcut(target, link, root, arguments, "Clipjump Modern", root "\icons\icon.ico")
        } else if FileExist(link)
            FileDelete(link)
        return link
    }
    static TrimMemory() => DllCall("SetProcessWorkingSetSize", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "UPtr", -1, "UPtr", -1)
}

class CJUpdates {
    __New(callback, root, directory, runtime := "") {
        this.Callback := callback, this.Root := root, this.Directory := directory
        this.Runtime := runtime != "" ? runtime : A_AhkPath
        this.Worker := A_IsCompiled ? root "\ClipjumpCapture.exe" : root "\v2\CaptureWorker.ahk"
        this.Deadline := 8000
        this.Handle := 0, this.Output := "", this.Timer := ObjBindMethod(this, "Poll")
        DirCreate(directory)
    }
    Check() {
        this.Cancel()
        this.Output := this.Directory "\" CJNewId() ".json"
        worker := this.Worker, compiled := RegExMatch(worker, "i)\.exe$")
        program := compiled ? worker : this.Runtime
        command := compiled ? '"' worker '" --updates "' this.Output '"' : '"' program '" /ErrorStdOut "' worker '" --updates "' this.Output '"'
        startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0), info := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("UInt", startup.Size, startup)
        arguments := Buffer((StrLen(command) + 1) * 2)
        StrPut(command, arguments)
        if !DllCall("CreateProcessW", "Str", program, "Ptr", arguments, "Ptr", 0, "Ptr", 0, "Int", 0, "UInt", 0x08000000, "Ptr", 0, "Str", this.Directory, "Ptr", startup, "Ptr", info)
            throw Error("The update worker could not be started.")
        this.Handle := NumGet(info, 0, "Ptr")
        DllCall("CloseHandle", "Ptr", NumGet(info, A_PtrSize, "Ptr"))
        this.Started := A_TickCount
        SetTimer(this.Timer, 75)
    }
    Poll() {
        if !this.Handle
            return
        finished := DllCall("WaitForSingleObject", "Ptr", this.Handle, "UInt", 0) = 0
        if !finished && A_TickCount - this.Started < this.Deadline
            return
        try {
            code := 1
            DllCall("GetExitCodeProcess", "Ptr", this.Handle, "UInt*", &code)
            if !finished || code || !FileExist(this.Output)
                throw Error("The update service could not be reached before the deadline.")
            if FileGetSize(this.Output) > 1048576
                throw Error("The release response is too large.")
            result := CJUpdates.Latest(FileRead(this.Output, "UTF-8"))
        } catch as err
            result := {Error: err.Message}
        this.Cancel()
        this.Callback.Call(result)
    }
    Cancel() {
        SetTimer(this.Timer, 0)
        if this.Handle {
            if DllCall("WaitForSingleObject", "Ptr", this.Handle, "UInt", 0) = 0x102 {
                DllCall("TerminateProcess", "Ptr", this.Handle, "UInt", 1)
                DllCall("WaitForSingleObject", "Ptr", this.Handle, "UInt", 500)
            }
            DllCall("CloseHandle", "Ptr", this.Handle)
            this.Handle := 0
        }
        if this.Output
            try FileDelete(this.Output)
    }
    static Latest(text) {
        if StrLen(text) > 1048576
            throw Error("The release response is too large.")
        ; GitHub generates these JSON properties. Never evaluate response code.
        position := 1, best := false
        while RegExMatch(text, '(?<!\\)"tag_name"\s*:\s*"(v?(\d+\.\d+\.\d+(?:-[a-z]+\.\d+)?))"', &match, position) {
            if !best || this.Compare(match[2], best.Version) > 0
                best := {Version: match[2], URL: CJApp.ProjectPage "/releases/tag/" match[1]}
            position := match.Pos + match.Len
        }
        if !best
            throw Error("No published releases could be found.")
        return best
    }
    static Compare(first, second) {
        if !RegExMatch(first, "i)^v?(\d+)\.(\d+)\.(\d+)(?:-([a-z]+)\.(\d+))?$", &a) || !RegExMatch(second, "i)^v?(\d+)\.(\d+)\.(\d+)(?:-([a-z]+)\.(\d+))?$", &b)
            throw Error("Invalid release version.")
        loop 3
            if Integer(a[A_Index]) != Integer(b[A_Index])
                return Integer(a[A_Index]) > Integer(b[A_Index]) ? 1 : -1
        if a[4] = "" || b[4] = ""
            return a[4] = b[4] ? 0 : a[4] = "" ? 1 : -1
        if a[4] != b[4]
            return StrCompare(a[4], b[4], false)
        return Integer(a[5]) = Integer(b[5]) ? 0 : Integer(a[5]) > Integer(b[5]) ? 1 : -1
    }
}

class CJEdits {
    __New(app) {
        this.App := app, this.Sessions := Map()
        this.Directory := app.Config.Data "\edits"
        DirCreate(this.Directory)
    }
    Open(id, launch := true) {
        snapshot := this.App.Store.Snapshot(id), image := snapshot.Kind = "image"
        key := CJNewId(), path := this.Directory "\" key (image ? ".png" : ".txt")
        if image {
            if !CJImage.Thumbnail(snapshot, path, true)
                throw Error("This clip has no editable image.")
        } else
            FileAppend(snapshot.Text, path, "UTF-8")
        state := {Id: id, Path: path, Image: image, Original: FileRead(path, "RAW"), Changed: false, PID: 0, Started: A_TickCount, LastError: ""}
        this.Sessions[key] := state
        if launch {
            editor := this.App.Config.Get(image ? "ImageEditor" : "TextEditor")
            if !FileExist(editor) && !RegExMatch(editor, "i)^[\w.-]+\.exe$")
                throw Error("Choose an editor executable in Settings.")
            Run('"' editor '" "' path '"', , , &pid)
            state.PID := pid
            this.App.UI.ShowEditing(key, state)
        }
        return key
    }
    Commit(key) {
        state := this.Sessions[key]
        if FileGetSize(state.Path) > 67108864
            throw Error("Edited file exceeds the 64 MiB limit.")
        raw := FileRead(state.Path, "RAW")
        if raw.Size = state.Original.Size && (!raw.Size || !DllCall("msvcrt\memcmp", "Ptr", raw, "Ptr", state.Original, "UPtr", raw.Size, "Cdecl Int"))
            return false
        snapshot := state.Image ? CJImage.FromFile(state.Path) : CJSnapshot.FromText(FileRead(state.Path))
        this.App.Store.Replace(state.Id, snapshot)
        state.Original := raw, state.Changed := true, state.LastError := ""
        if this.App.LastId = state.Id
            this.App.LastSequence := 0
        this.App.UI.RefreshHistory()
        return true
    }
    Finish(key, save := true) {
        if !this.Sessions.Has(key)
            return
        if save
            this.Commit(key)
        try FileDelete(this.Sessions[key].Path)
        this.Sessions.Delete(key)
    }
    Poll() {
        for key, state in this.Sessions {
            try this.Commit(key)
            catch as err
                state.LastError := err.Message
            this.App.UI.UpdateEditing(key, state)
            ; Editors can hand a tab to another process. Finishing is explicit;
            ; launcher PID exit must not discard a document still being edited.
        }
    }
}
