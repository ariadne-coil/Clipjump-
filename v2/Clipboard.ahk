#Requires AutoHotkey v2.0.31+
; Stable clipboard archives: format names survive Windows session ID changes.
class CJClipboard {
    static Sequence() => DllCall("GetClipboardSequenceNumber", "UInt")

    static Source() {
        owner := DllCall("GetClipboardOwner", "Ptr"), pid := 0, processName := "", className := ""
        DllCall("GetWindowThreadProcessId", "Ptr", owner, "UInt*", &pid)
        if pid {
            handle := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
            if handle {
                path := Buffer(65536), count := 32768
                if DllCall("QueryFullProcessImageNameW", "Ptr", handle, "UInt", 0, "Ptr", path, "UInt*", &count) {
                    full := StrGet(path, count)
                    SplitPath(full, &processName)
                }
                DllCall("CloseHandle", "Ptr", handle)
            }
        }
        name := Buffer(1024)
        if DllCall("GetClassNameW", "Ptr", owner, "Ptr", name, "Int", 512)
            className := StrGet(name)
        return {Pid: pid, Process: processName, Class: className}
    }

    static Open(timeout := 250) {
        started := A_TickCount
        loop {
            if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
                return true
            if A_TickCount - started >= timeout
                return false
            Sleep(10)
        }
    }

    static FormatName(id) {
        if id < 0xC000
            return ""
        data := Buffer(2048)
        length := DllCall("GetClipboardFormatNameW", "UInt", id, "Ptr", data, "Int", 1024)
        return length ? StrGet(data, length) : ""
    }

    static OfficeFormat(id, name := "") {
        if id < 0xC000
            return id = 1 || id = 7 || id = 8 || id = 13 || id = 15 || id = 16 || id = 17
        return RegExMatch(name, "i)^(HTML Format|Rich Text Format|Rich Text Format Without Objects|PNG|image/png|image/svg\+xml|CSV)$") != 0
    }

    static VolatileFormat(name) {
        return RegExMatch(name, "i)^(DataObject|Ole Private Data|Object Descriptor|Link|Link Source.*|OwnerLink|ObjectLink|Native|Embed Source)$") != 0
    }

    static Capture(expectedSequence := 0) {
        sequence := this.Sequence()
        if expectedSequence && sequence != expectedSequence
            throw Error("stale")
        source := this.Source()
        office := RegExMatch(source.Process, "i)^(EXCEL|WINWORD|POWERPNT|OUTLOOK|ONENOTE|MSACCESS)\.EXE$")
        if office
            snapshot := this.CaptureOffice()
        else {
            if !this.Open()
                throw Error("busy")
            DllCall("CloseClipboard")
            snapshot := CJSnapshot.FromNative(ClipboardAll())
        }
        if this.Sequence() != sequence
            throw Error("stale")
        if !snapshot.Entries.Length
            throw Error("No transferable clipboard format is available.")
        return snapshot
    }

    static CaptureOffice() {
        if !this.Open()
            throw Error("busy")
        snapshot := CJSnapshot(), format := 0, total := 0
        try {
            while format := DllCall("EnumClipboardFormats", "UInt", format, "UInt") {
                name := this.FormatName(format)
                if !this.OfficeFormat(format, name)
                    continue
                handle := DllCall("GetClipboardData", "UInt", format, "Ptr")
                bytes := DllCall("GlobalSize", "Ptr", handle, "UPtr")
                if !handle || !bytes || total + bytes > 67108864
                    throw Error("Office clipboard data is unavailable or exceeds 64 MiB.")
                ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
                if !ptr
                    throw Error("Office clipboard data cannot be locked.")
                try {
                    data := Buffer(bytes)
                    DllCall("RtlMoveMemory", "Ptr", data, "Ptr", ptr, "UPtr", bytes)
                    snapshot.Entries.Push({Id: format, Name: name, Data: data})
                } finally DllCall("GlobalUnlock", "Ptr", handle)
                total += bytes
            }
        } finally DllCall("CloseClipboard")
        return snapshot
    }
}

class CJSnapshot {
    static Magic := 0x42324A43 ; CJ2B
    static MaximumBytes := 134217728
    __New() {
        this.Entries := []
    }

    static Copy(source, offset, length) {
        result := Buffer(length)
        if length
            DllCall("RtlMoveMemory", "Ptr", result, "Ptr", source.Ptr + offset, "UPtr", length)
        return result
    }

    static FromNative(raw) {
        snapshot := CJSnapshot(), offset := 0, terminated := false
        if raw.Size > this.MaximumBytes
            throw Error("Clipboard snapshot exceeds 128 MiB.")
        while offset + 4 <= raw.Size {
            id := NumGet(raw, offset, "UInt"), offset += 4
            if !id {
                terminated := true
                break
            }
            if offset + 4 > raw.Size
                throw Error("Truncated clipboard record.")
            bytes := NumGet(raw, offset, "UInt"), offset += 4
            if bytes > raw.Size - offset
                throw Error("Invalid clipboard record size.")
            name := CJClipboard.FormatName(id)
            if !CJClipboard.VolatileFormat(name) && (id < 0xC000 || name != "")
                snapshot.Entries.Push({Id: id, Name: name, Data: this.Copy(raw, offset, bytes)})
            offset += bytes
            if snapshot.Entries.Length > 1024
                throw Error("Too many clipboard formats.")
        }
        if !terminated || offset != raw.Size
            throw Error("Clipboard snapshot has an invalid terminator.")
        return snapshot
    }

    static FromText(text) {
        snapshot := CJSnapshot(), data := Buffer((StrLen(text) + 1) * 2)
        StrPut(text, data, "UTF-16")
        snapshot.Entries.Push({Id: 13, Name: "", Data: data})
        return snapshot
    }

    Find(idOrName) {
        for entry in this.Entries
            if (Type(idOrName) = "Integer" && entry.Id = idOrName) || (Type(idOrName) = "String" && StrLower(entry.Name) = StrLower(idOrName))
                return entry.Data
        return false
    }

    Text {
        get {
            if data := this.Find(13)
                return data.Size >= 2 ? StrGet(data, data.Size // 2, "UTF-16") : ""
            if data := this.Find(1)
                return data.Size ? StrGet(data, data.Size, "CP0") : ""
            if data := this.Find(15) {
                if data.Size < 20
                    return ""
                offset := NumGet(data, 0, "UInt"), wide := NumGet(data, 16, "UInt"), result := ""
                step := wide ? 2 : 1
                if offset < 20 || offset >= data.Size
                    return ""
                while offset + step <= data.Size {
                    name := StrGet(data.Ptr + offset, (data.Size - offset) // step, wide ? "UTF-16" : "CP0")
                    if name = ""
                        break
                    result .= (result = "" ? "" : "`r`n") name
                    offset += (StrPut(name, wide ? "UTF-16" : "CP0")) * step
                }
                return result
            }
            return ""
        }
    }

    Kind => this.Find(15) ? "files" : this.Text != "" ? "text" : this.Find(8) || this.Find(17) || this.Find("PNG") || this.Find("image/png") ? "image" : "binary"
    Size {
        get {
            bytes := 0
            for entry in this.Entries
                bytes += entry.Data.Size
            return bytes
        }
    }

    Native() {
        length := 4
        for entry in this.Entries
            length += 8 + entry.Data.Size
        raw := Buffer(length, 0), offset := 0
        for entry in this.Entries {
            id := entry.Name != "" ? DllCall("RegisterClipboardFormatW", "Str", entry.Name, "UInt") : entry.Id
            if !id
                throw Error("Cannot register a clipboard format.")
            NumPut("UInt", id, raw, offset)
            NumPut("UInt", entry.Data.Size, raw, offset + 4)
            if entry.Data.Size
                DllCall("RtlMoveMemory", "Ptr", raw.Ptr + offset + 8, "Ptr", entry.Data, "UPtr", entry.Data.Size)
            offset += 8 + entry.Data.Size
        }
        return ClipboardAll(raw)
    }

    Save(path) {
        temporary := path ".pending"
        file := FileOpen(temporary, "w", "UTF-8-RAW")
        if !file
            throw Error("Cannot create clipboard archive.")
        try {
            file.WriteUInt(CJSnapshot.Magic), file.WriteUInt(1), file.WriteUInt(this.Entries.Length)
            for entry in this.Entries {
                name := CJDatabase.Utf8(entry.Name)
                file.WriteUInt(entry.Id), file.WriteUInt(name.Size - 1), file.WriteUInt(entry.Data.Size)
                if name.Size > 1
                    if file.RawWrite(name, name.Size - 1) != name.Size - 1
                        throw Error("Incomplete clipboard format name write.")
                if entry.Data.Size
                    if file.RawWrite(entry.Data) != entry.Data.Size
                        throw Error("Incomplete clipboard archive write.")
            }
            file.Close()
            FileMove(temporary, path, 1)
        } catch as err {
            file.Close()
            try FileDelete(temporary)
            throw err
        }
        return path
    }

    static Load(path) {
        file := FileOpen(path, "r")
        if !file || file.Length < 12 || file.Length > this.MaximumBytes
            throw Error("Invalid clipboard archive size.")
        try {
            if file.ReadUInt() != this.Magic || file.ReadUInt() != 1
                throw Error("Unsupported clipboard archive version.")
            count := file.ReadUInt()
            if !count || count > 1024
                throw Error("Invalid clipboard format count.")
            snapshot := CJSnapshot()
            loop count {
                if file.Length - file.Pos < 12
                    throw Error("Truncated clipboard archive.")
                id := file.ReadUInt(), nameBytes := file.ReadUInt(), bytes := file.ReadUInt()
                if nameBytes > 1024 || nameBytes + bytes > file.Length - file.Pos
                    throw Error("Invalid clipboard archive record.")
                nameData := Buffer(nameBytes + 1, 0), data := Buffer(bytes)
                if nameBytes
                    file.RawRead(nameData, nameBytes)
                if bytes
                    file.RawRead(data)
                name := nameBytes ? StrGet(nameData, nameBytes, "UTF-8") : ""
                if !id || (id >= 0xC000 && name = "")
                    throw Error("A registered clipboard format has no stable name.")
                snapshot.Entries.Push({Id: id, Name: name, Data: data})
            }
            if file.Pos != file.Length
                throw Error("Clipboard archive has trailing data.")
            return snapshot
        } finally file.Close()
    }

    Equals(other) {
        if !IsObject(other) || this.Entries.Length != other.Entries.Length
            return false
        for index, entry in this.Entries {
            peer := other.Entries[index]
            if entry.Name != peer.Name || (entry.Name = "" && entry.Id != peer.Id) || entry.Data.Size != peer.Data.Size
                return false
            if entry.Data.Size && DllCall("msvcrt\memcmp", "Ptr", entry.Data, "Ptr", peer.Data, "UPtr", entry.Data.Size, "Cdecl Int")
                return false
        }
        return true
    }
}

class CJCaptureJob {
    __New(directory, runtime, worker, settle := 0, deadline := 3000) {
        this.Directory := directory, this.Runtime := runtime, this.Worker := worker
        this.Settle := settle, this.Deadline := deadline, this.Pending := false
        this.ProcessHandle := 0, this.Prefix := "", this.Counter := 0
        DirCreate(directory)
    }

    Queue(channel, kind := 1) {
        this.Cancel()
        this.Channel := channel, this.Kind := kind, this.Sequence := CJClipboard.Sequence()
        this.QueuedAt := A_TickCount, this.Pending := true
        ; Launch the isolated reader immediately. Clipboard contention and
        ; delayed rendering are still retried and bounded inside the worker.
        this.Poll()
    }

    Poll() {
        if !this.Pending
            return "idle"
        if CJClipboard.Sequence() != this.Sequence {
            this.Cancel()
            return "stale"
        }
        if !this.ProcessHandle {
            if A_TickCount - this.QueuedAt < this.Settle
                return "waiting"
            this.Counter += 1
            this.Prefix := this.Directory "\" DllCall("GetCurrentProcessId") "-" this.Counter
            compiled := RegExMatch(this.Worker, "i)\.exe$")
            program := compiled ? this.Worker : this.Runtime
            command := compiled ? '"' program '" "' this.Prefix '" ' this.Sequence : '"' program '" /ErrorStdOut "' this.Worker '" "' this.Prefix '" ' this.Sequence
            ; Keep a kernel handle, so cancellation cannot kill a reused PID.
            startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0), info := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", startup.Size, startup, 0)
            commandData := Buffer((StrLen(command) + 1) * 2)
            StrPut(command, commandData)
            if !DllCall("CreateProcessW", "Str", program, "Ptr", commandData, "Ptr", 0, "Ptr", 0, "Int", 0, "UInt", 0x08000000, "Ptr", 0, "Str", this.Directory, "Ptr", startup, "Ptr", info) {
                this.Cancel()
                return "error"
            }
            this.ProcessHandle := NumGet(info, 0, "Ptr")
            DllCall("CloseHandle", "Ptr", NumGet(info, A_PtrSize, "Ptr"))
            this.StartedAt := A_TickCount
            return "waiting"
        }
        if FileExist(this.Prefix ".ready")
            return "ready"
        if A_TickCount - this.StartedAt >= this.Deadline {
            this.Cancel()
            return "timeout"
        }
        if DllCall("WaitForSingleObject", "Ptr", this.ProcessHandle, "UInt", 0) = 0 || FileExist(this.Prefix ".error") {
            this.Cancel()
            return "error"
        }
        return "waiting"
    }

    Cancel() {
        if this.ProcessHandle {
            if DllCall("WaitForSingleObject", "Ptr", this.ProcessHandle, "UInt", 0) = 0x102 {
                DllCall("TerminateProcess", "Ptr", this.ProcessHandle, "UInt", 1)
                DllCall("WaitForSingleObject", "Ptr", this.ProcessHandle, "UInt", 500)
            }
            DllCall("CloseHandle", "Ptr", this.ProcessHandle)
            this.ProcessHandle := 0
        }
        if this.Prefix
            for suffix in [".cjc", ".cjc.pending", ".ready", ".error"]
                try FileDelete(this.Prefix suffix)
        this.Pending := false
    }

    __Delete() {
        try this.Cancel()
    }
}
