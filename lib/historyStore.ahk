; SQLite history storage. Clipboard text is always bound as data.
CJ_ExecBound(db, sql, values) {
    statement := 0
    rc := DllCall("sqlite3\sqlite3_prepare16_v2", "Ptr", db._Handle, "WStr", sql, "Int", -1, "PtrP", statement, "Ptr", 0, "Cdecl Int")
    if rc
        return false
    try {
        for index, value in values {
            rc := DllCall("sqlite3\sqlite3_bind_text16", "Ptr", statement, "Int", index, "WStr", value, "Int", -1, "Ptr", -1, "Cdecl Int")
            if rc
                return false
        }
        return DllCall("sqlite3\sqlite3_step", "Ptr", statement, "Cdecl Int") = 101 ; SQLITE_DONE
    } finally {
        DllCall("sqlite3\sqlite3_finalize", "Ptr", statement, "Cdecl Int")
    }
}

CJ_HistoryEnsureSchema(db) {
    if !db.Exec("CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT, type INTEGER, fileid TEXT, time TEXT, size INTEGER, snapshot TEXT)")
        return false
    if !db.GetTable("SELECT snapshot FROM history LIMIT 0", schema)
        return db.Exec("ALTER TABLE history ADD COLUMN snapshot TEXT")
    return true
}

CJ_HistoryWrite(db, text, timestamp, ByRef snapshot, imagePath := "") {
    archive := "", image := "", type := 0
    size := StrPut(text, "UTF-8") - 1
    FileCreateDir, cache\history
    stem := "cache\history\" DllCall("GetTickCount64", "UInt64") "-" DllCall("GetCurrentProcessId") "-" A_TickCount
    ; A counter also distinguishes multiple inserts in the same millisecond.
    static counter := 0
    stem .= "-" ++counter
    if (imagePath != "") {
        source := FileOpen(imagePath, "r")
        if !IsObject(source)
            return false ; No empty size field / invalid SQL when thumbnail creation failed.
        size := source.Length
        source.Close()
        image := stem ".jpg"
        FileCopy, % imagePath, % image
        if ErrorLevel
            return false
        type := 1, text := "[IMAGE]"
    }
    if (CJ_BinarySize(snapshot) > 4) {
        archive := stem ".avc"
        if !CJ_WriteSnapshot(archive, snapshot) {
            if image
                FileDelete, % image
            return false
        }
    }
    ok := CJ_ExecBound(db, "INSERT INTO history (data,type,fileid,time,size,snapshot) VALUES (?1,?2,?3,?4,?5,?6)", [text, type, image, timestamp, size, archive])
    if !ok {
        if archive
            FileDelete, % archive
        if image
            FileDelete, % image
    }
    return ok
}

CJ_SqlText(text) {
    return "'" StrReplace(text, "'", "''") "'"
}

CJ_HistorySearchSql(criteria := "", partial := false) {
    sql := "SELECT * FROM history", condition := ""
    criteria := Trim(criteria)
    if (criteria = "")
        return sql
    if partial {
        Loop, Parse, criteria, % " `t", % " `t"
            condition .= (condition = "" ? "" : " AND ") "instr(lower(data),lower(" CJ_SqlText(A_LoopField) ")) > 0"
    } else {
        condition := "instr(lower(data),lower(" CJ_SqlText(criteria) ")) > 0"
    }
    return sql " WHERE " condition
}
