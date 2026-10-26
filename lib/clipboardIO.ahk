; Clipboard transport for Clipjump Modern. Apache-2.0.
; Keep binary ClipboardAll variables ByRef: converting them to text loses formats.
CJ_ClipboardSequence() {
    return DllCall("GetClipboardSequenceNumber", "UInt")
}

CJ_ClipboardSourceProcess() {
    owner := DllCall("GetClipboardOwner", "Ptr"), pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", owner, "UIntP", pid)
    if !pid
        return ""
    process := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
    if !process
        return ""
    characters := 32768
    VarSetCapacity(path, characters * 2, 0)
    ok := DllCall("QueryFullProcessImageName", "Ptr", process, "UInt", 0, "Str", path, "UIntP", characters)
    DllCall("CloseHandle", "Ptr", process)
    if !ok
        return ""
    SplitPath, path, name
    return name
}

CJ_ClipboardWait(timeoutMs := 250) {
    started := DllCall("GetTickCount64", "UInt64")
    loop {
        if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
            DllCall("CloseClipboard")
            return true
        }
        if (DllCall("GetTickCount64", "UInt64") - started >= timeoutMs)
            return false
        Sleep, 10
    }
}

CJ_ReadClipboard(ByRef data, ByRef text, expectedSequence := 0, temporaryPrefix := "") {
    data := "", text := ""
    if !CJ_ClipboardWait()
        return false
    sequence := CJ_ClipboardSequence()
    if (expectedSequence && sequence != expectedSequence)
        return false
    try {
        ; Office normally owns the clipboard through a hidden OLE window.
        ; Resolve its PID directly: WinGet can miss it with hidden windows off.
        sourceProcess := CJ_ClipboardSourceProcess()
        if RegExMatch(sourceProcess, "i)^(EXCEL|WINWORD|POWERPNT|OUTLOOK|ONENOTE|MSACCESS)\.EXE$") {
            if !CJ_ReadOfficeClipboard(data, temporaryPrefix = "" ? "" : temporaryPrefix ".office.avc")
                return false
        } else {
            data := ClipboardAll
        }
        text := CJ_SnapshotText(data)
    } catch {
        data := "", text := ""
        return false
    }
    ; Delayed rendering can advance the sequence. Retry after it has settled;
    ; never pair a snapshot with text from another copy operation.
    return (CJ_ClipboardSequence() = sequence && CJ_BinarySize(data) > 4)
}

; Request Office's transferable memory formats without asking it to render
; printer/metafile or live OLE object formats. In particular, Excel's metafile
; rendering is a documented source of ClipboardAll / printer dialogs.
; BIFF and spreadsheet XML are omitted because archived formula payloads
; can trigger Excel's cross-instance formula warning; HTML preserves display.
CJ_ReadOfficeClipboard(ByRef data, path := "") {
    data := ""
    if (path = "")
        path := A_Temp "\Clipjump-office-" DllCall("GetCurrentProcessId") ".avc"
    file := FileOpen(path, "w", "UTF-8-RAW")
    if !IsObject(file)
        return false
    if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
        file.Close()
        FileDelete, % path
        return false
    }
    count := 0, format := 0, total := 0, ok := true
    try {
        while (format := DllCall("EnumClipboardFormats", "UInt", format, "UInt")) {
            allowed := (format = 1 || format = 7 || format = 8 || format = 13 || format = 15 || format = 16 || format = 17)
            if (format >= 0xC000) {
                VarSetCapacity(name, 512, 0)
                DllCall("GetClipboardFormatName", "UInt", format, "Str", name, "Int", 256)
                allowed := RegExMatch(name, "i)^(HTML Format|Rich Text Format|Rich Text Format Without Objects|PNG|image/png|image/svg\+xml|CSV)$")
            }
            if !allowed
                continue
            handle := DllCall("GetClipboardData", "UInt", format, "Ptr")
            size := DllCall("GlobalSize", "Ptr", handle, "UPtr")
            if (!handle || !size || total + size > 67108864) {
                ok := false
                break
            }
            ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
            if !ptr {
                ok := false
                break
            }
            file.WriteUInt(format)
            if (A_PtrSize = 8)
                file.WriteInt64(size)
            else
                file.WriteUInt(size)
            written := file.RawWrite(ptr + 0, size)
            DllCall("GlobalUnlock", "Ptr", handle)
            if (written != size) {
                ok := false
                break
            }
            total += size, count += 1
        }
        file.WriteUInt(0)
    } finally {
        DllCall("CloseClipboard")
        file.Close()
    }
    if (ok && count) {
        FileRead, data, *c %path%
        ok := !ErrorLevel
    } else {
        ok := false
    }
    FileDelete, % path
    return ok
}

CJ_BinarySize(ByRef data) {
    return StrLen(data) * (A_IsUnicode ? 2 : 1)
}

; ClipboardAll's archive contains DWORD format, SIZE_T byte length, raw bytes,
; repeated until a zero format. Validate every offset before dereferencing.
CJ_SnapshotText(ByRef data) {
    total := CJ_BinarySize(data), offset := 0, fallback := ""
    while (offset + 4 <= total) {
        format := NumGet(data, offset, "UInt")
        if !format
            break
        headerSize := 4 + A_PtrSize
        if (offset + headerSize > total)
            return ""
        size := NumGet(data, offset + 4, "UPtr"), offset += headerSize
        if (size < 0 || size > total - offset)
            return ""
        if (format = 13 && size >= 2 && Mod(size, 2) = 0) {
            ; Limit the read to the record, even for malformed imports.
            text := StrGet(&data + offset, size // 2, "UTF-16")
            return text
        }
        if (format = 1 && size)
            fallback := StrGet(&data + offset, size, "CP0")
        if (format = 15 && size >= 20) {
            position := NumGet(data, offset, "UInt")
            wide := NumGet(data, offset + 16, "UInt")
            if (position >= 20 && position < size) {
                step := wide ? 2 : 1
                while (position + step <= size) {
                    name := StrGet(&data + offset + position, (size - position) // step, wide ? "UTF-16" : "CP0")
                    if (name = "")
                        break
                    fallback .= (fallback = "" ? "" : "`r`n") name
                    position += (StrLen(name) + 1) * step
                }
            }
        }
        offset += size
    }
    return fallback
}

CJ_WriteSnapshot(path, ByRef data) {
    size := CJ_BinarySize(data)
    if (size <= 4)
        return false
    temporary := path ".pending"
    file := FileOpen(temporary, "w", "UTF-8-RAW")
    if !IsObject(file)
        return false
    written := file.RawWrite(data, size)
    file.Close()
    if (written != size) {
        FileDelete, % temporary
        return false
    }
    ; Replace only after the complete binary has reached disk.
    FileMove, % temporary, % path, 1
    if ErrorLevel {
        FileDelete, % temporary
        return false
    }
    return true
}

CJ_SnapshotEqualsFile(path, ByRef data) {
    FileGetSize, size, % path
    if (ErrorLevel || size != CJ_BinarySize(data) || size <= 4)
        return false
    FileRead, previous, *c %path%
    if ErrorLevel
        return false
    return !DllCall("msvcrt\memcmp", "Ptr", &previous, "Ptr", &data, "UPtr", size, "Cdecl Int")
}

; ClipboardAll may block inside an application's delayed renderer. The UI
; launches an isolated, read-only worker and enforces a wall-clock deadline.
class CJ_CaptureJob {
    __New(directory, runtime, worker, settleMs := 150, timeoutMs := 3000) {
        this.Directory := directory
        this.Runtime := runtime
        this.Worker := worker
        this.SettleMs := settleMs
        this.TimeoutMs := timeoutMs
        this.Counter := 0
        this.Pending := false
        this.Pid := 0
        FileCreateDir, % directory
    }

    Queue(kind, channel) {
        this.Cancel()
        this.Kind := kind
        this.Channel := channel
        this.Sequence := CJ_ClipboardSequence()
        this.QueuedAt := DllCall("GetTickCount64", "UInt64")
        this.Pending := true
    }

    Poll() {
        if !this.Pending
            return "idle"
        if (CJ_ClipboardSequence() != this.Sequence) {
            this.Cancel()
            return "stale"
        }
        now := DllCall("GetTickCount64", "UInt64")
        if !this.Pid {
            if (now - this.QueuedAt < this.SettleMs)
                return "waiting"
            this.Counter += 1
            this.Prefix := this.Directory "\" DllCall("GetCurrentProcessId") "-" this.Counter
            command := """" this.Runtime """ /ErrorStdOut """ this.Worker """ """ this.Prefix """ " this.Sequence
            try Run, % command,, Hide, workerPid
            catch {
                this.Cancel()
                return "error"
            }
            this.Pid := workerPid
            this.StartedAt := now
            return "waiting"
        }
        if FileExist(this.Prefix ".ready")
            return "ready"
        if (now - this.StartedAt >= this.TimeoutMs) {
            this.Cancel()
            return "timeout"
        }
        pid := this.Pid
        Process, Exist, % pid
        if (!ErrorLevel || FileExist(this.Prefix ".error")) {
            this.Cancel()
            return "error"
        }
        return "waiting"
    }

    Cancel() {
        if this.Pid {
            pid := this.Pid
            Process, Close, % pid
            this.Pid := 0
        }
        if this.Prefix {
            ; Exact files belonging to this worker; no recursive cleanup.
            for _, suffix in [".avc", ".avc.pending", ".office.avc", ".txt", ".ready", ".error"] {
                path := this.Prefix suffix
                FileDelete, % path
            }
        }
        this.Pending := false
    }

    __Delete() {
        this.Cancel()
    }
}
