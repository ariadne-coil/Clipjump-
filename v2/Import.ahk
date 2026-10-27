#Requires AutoHotkey v2.0.31+
; Imports are explicit, repeatable, and never modify the v1 source directory.
class CJLegacyImport {
    __New(store, sqliteLibrary) {
        this.Store := store, this.Library := sqliteLibrary
    }

    static Records(raw, width) {
        records := [], offset := 0
        if raw.Size > CJSnapshot.MaximumBytes
            throw Error("Legacy snapshot is too large.")
        while offset + 4 <= raw.Size {
            id := NumGet(raw, offset, "UInt"), offset += 4
            if !id {
                if offset != raw.Size || !records.Length
                    throw Error("Invalid legacy archive terminator.")
                return records
            }
            if offset + width > raw.Size
                throw Error("Truncated legacy archive.")
            bytes := NumGet(raw, offset, width = 8 ? "UInt64" : "UInt"), offset += width
            if bytes > raw.Size - offset || records.Length >= 1024
                throw Error("Invalid legacy archive record.")
            records.Push({Id: id, Offset: offset, Bytes: bytes})
            offset += bytes
        }
        throw Error("Legacy archive has no terminator.")
    }

    static Snapshot(path, includeRegistered := false, width := 0) {
        raw := FileRead(path, "RAW"), records := 0
        if width
            records := this.Records(raw, width)
        else {
            try records := this.Records(raw, 4)
            catch
                records := this.Records(raw, 8)
        }
        snapshot := CJSnapshot()
        excel := false
        if includeRegistered
            for record in records
                if RegExMatch(CJClipboard.FormatName(record.Id), "i)^Biff\d+$")
                    excel := true
        for record in records {
            id := record.Id, name := CJClipboard.FormatName(id)
            standard := id = 1 || id = 7 || id = 8 || id = 13 || id = 15 || id = 16 || id = 17
            registered := includeRegistered && id >= 0xC000 && name != "" && !CJClipboard.VolatileFormat(name)
            if excel && !CJClipboard.OfficeFormat(id, name)
                continue
            if standard || registered
                snapshot.Entries.Push({Id: id, Name: standard ? "" : name, Data: CJSnapshot.Copy(raw, record.Offset, record.Bytes)})
        }
        if !snapshot.Entries.Length
            throw Error("No portable formats could be recovered from the legacy archive.")
        return snapshot
    }

    static FullPath(path) {
        pathBuffer := Buffer(65536)
        length := DllCall("GetFullPathNameW", "Str", path, "UInt", 32768, "Ptr", pathBuffer, "Ptr", 0)
        if !length || length >= 32768
            throw Error("Invalid import path.")
        return RTrim(StrGet(pathBuffer), "\")
    }

    SourceFile(root, relative) {
        path := RegExMatch(relative, "i)^(?:[a-z]:\\|\\\\)") ? relative : root "\" relative
        path := CJLegacyImport.FullPath(path)
        if StrLower(SubStr(path, 1, StrLen(root) + 1)) != StrLower(root "\")
            throw Error("An imported history path is outside the selected source folder.")
        return path
    }

    Seen(key) => this.Store.DB.Query("SELECT source FROM imports WHERE source=?1", [key]).Length != 0
    Remember(key, id) => this.Store.DB.Exec("INSERT OR REPLACE INTO imports(source,clip_id) VALUES (?1,?2)", [key, id])

    Run(root, includeRegistered := false) {
        root := CJLegacyImport.FullPath(root)
        report := {Imported: 0, Skipped: 0, Failed: 0, RegisteredFormats: includeRegistered}
        settings := root "\settings.ini", channelMap := Map(0, 0)
        Loop Files root "\cache\clips*", "D" {
            directory := A_LoopFileFullPath, folder := A_LoopFileName
            if !RegExMatch(folder, "^clips(\d*)$", &match)
                continue
            sourceChannel := match[1] = "" ? 0 : Integer(match[1])
            if !channelMap.Has(sourceChannel) {
                name := IniRead(settings, "Channels", sourceChannel, "Imported " sourceChannel)
                try destination := this.Store.ChannelId(name)
                catch
                    destination := this.Store.AddChannel(name, SubStr(name, 1, 1) = "_", StrLower(name) = "pit")
                channelMap[sourceChannel] := destination
            }
            names := ""
            Loop Files directory "\*.avc", "F"
                if RegExMatch(A_LoopFileName, "^\d+\.avc$")
                    names .= A_LoopFileName "`n"
            for name in StrSplit(Trim(Sort(names, "N"), "`n"), "`n") {
                if name = ""
                    continue
                path := directory "\" name, sourceId := SubStr(name, 1, -4)
                key := path "|" FileGetTime(path, "M") "|" FileGetSize(path)
                if this.Seen(key) {
                    report.Skipped += 1
                    continue
                }
                try {
                    snapshot := CJLegacyImport.Snapshot(path, includeRegistered)
                    id := this.Store.Add(snapshot, channelMap[sourceChannel], false)
                    preferences := directory "\prefs.ini"
                    tag := IniRead(preferences, sourceId, "Tags", "")
                    fixed := IniRead(preferences, sourceId, "fixed", "0")
                    this.Store.Tag(id, tag)
                    if fixed = "1"
                        this.Store.Pin(id, channelMap[sourceChannel], true)
                    this.Remember(key, id)
                    report.Imported += 1
                } catch {
                    report.Failed += 1
                }
            }
        }
        database := root "\cache\data.db"
        if FileExist(database) {
            source := CJDatabase(database, this.Library, true)
            try {
                columns := source.Query("PRAGMA table_info(history)"), hasSnapshot := false
                for column in columns
                    if column.name = "snapshot"
                        hasSnapshot := true
                rows := source.Query("SELECT id,data,type,fileid,time" (hasSnapshot ? ",snapshot" : ",'' AS snapshot") " FROM history ORDER BY id")
                for row in rows {
                    key := database "|history|" row.id "|" row.time
                    if this.Seen(key) {
                        report.Skipped += 1
                        continue
                    }
                    try {
                        if row.snapshot != "" && FileExist(path := this.SourceFile(root, row.snapshot))
                            snapshot := CJLegacyImport.Snapshot(path, includeRegistered)
                        else if row.type = 1
                            snapshot := CJImage.FromFile(this.SourceFile(root, row.fileid))
                        else
                            snapshot := CJSnapshot.FromText(row.data)
                        id := this.Store.AddHistory(snapshot, row.time)
                        this.Remember(key, id)
                        report.Imported += 1
                    } catch {
                        report.Failed += 1
                    }
                }
            } finally source.Close()
        }
        return report
    }
}
