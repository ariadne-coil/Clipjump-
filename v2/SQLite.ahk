#Requires AutoHotkey v2.0.31+
; Native SQLite wrapper for the v2 application. Apache-2.0.
class CJDatabase {
    __New(path, library, readOnly := false) {
        this.Handle := 0
        this.Module := DllCall("LoadLibraryExW", "Str", library, "Ptr", 0, "UInt", 8, "Ptr")
        if !this.Module
            throw Error("Cannot load the matching SQLite runtime: " library)
        this.Functions := Map()
        handle := 0
        flags := readOnly ? 1 : 6
        if readOnly {
            utf8 := CJDatabase.Utf8(path)
            rc := DllCall(this.Proc("sqlite3_open_v2"), "Ptr", utf8, "Ptr*", &handle, "Int", flags, "Ptr", 0, "Cdecl Int")
        } else
            rc := DllCall(this.Proc("sqlite3_open16"), "Str", path, "Ptr*", &handle, "Cdecl Int")
        this.Handle := handle
        if rc {
            this.Close()
            throw Error("Cannot open the clipboard database (SQLite " rc ").")
        }
        DllCall(this.Proc("sqlite3_busy_timeout"), "Ptr", handle, "Int", 1500, "Cdecl Int")
        if !readOnly {
            this.Exec("PRAGMA foreign_keys=ON")
            this.Exec("PRAGMA journal_mode=WAL")
        }
    }

    static Utf8(text) {
        data := Buffer(StrPut(text, "UTF-8"))
        StrPut(text, data, "UTF-8")
        return data
    }

    Proc(name) {
        if !this.Functions.Has(name) {
            address := DllCall("GetProcAddress", "Ptr", this.Module, "AStr", name, "Ptr")
            if !address
                throw Error("Required SQLite function is missing: " name)
            this.Functions[name] := address
        }
        return this.Functions[name]
    }

    Version => StrGet(DllCall(this.Proc("sqlite3_libversion"), "Cdecl Ptr"), "UTF-8")
    LastId => DllCall(this.Proc("sqlite3_last_insert_rowid"), "Ptr", this.Handle, "Cdecl Int64")
    Changes => DllCall(this.Proc("sqlite3_changes"), "Ptr", this.Handle, "Cdecl Int")

    Prepare(sql, parameters) {
        statement := 0
        rc := DllCall(this.Proc("sqlite3_prepare16_v2"), "Ptr", this.Handle, "Str", sql, "Int", -1, "Ptr*", &statement, "Ptr", 0, "Cdecl Int")
        if rc
            throw Error("SQLite prepare failed (code " rc ").")
        try {
            for index, value in parameters {
                if value is Buffer
                    rc := DllCall(this.Proc("sqlite3_bind_blob"), "Ptr", statement, "Int", index, "Ptr", value, "Int", value.Size, "Ptr", -1, "Cdecl Int")
                else if Type(value) = "Integer"
                    rc := DllCall(this.Proc("sqlite3_bind_int64"), "Ptr", statement, "Int", index, "Int64", value, "Cdecl Int")
                else if Type(value) = "Float"
                    rc := DllCall(this.Proc("sqlite3_bind_double"), "Ptr", statement, "Int", index, "Double", value, "Cdecl Int")
                else
                    rc := DllCall(this.Proc("sqlite3_bind_text16"), "Ptr", statement, "Int", index, "Str", value, "Int", StrLen(value) * 2, "Ptr", -1, "Cdecl Int")
                if rc
                    throw Error("SQLite parameter binding failed (code " rc ").")
            }
            return statement
        } catch as err {
            DllCall(this.Proc("sqlite3_finalize"), "Ptr", statement, "Cdecl Int")
            throw err
        }
    }

    Exec(sql, parameters := []) {
        statement := this.Prepare(sql, parameters)
        try {
            loop {
                rc := DllCall(this.Proc("sqlite3_step"), "Ptr", statement, "Cdecl Int")
                if rc = 101
                    return true
                if rc != 100
                    throw Error("SQLite write failed (code " rc ").")
            }
        } finally DllCall(this.Proc("sqlite3_finalize"), "Ptr", statement, "Cdecl Int")
    }

    Query(sql, parameters := []) {
        statement := this.Prepare(sql, parameters), rows := []
        try {
            count := DllCall(this.Proc("sqlite3_column_count"), "Ptr", statement, "Cdecl Int")
            names := []
            loop count
                names.Push(StrGet(DllCall(this.Proc("sqlite3_column_name16"), "Ptr", statement, "Int", A_Index - 1, "Cdecl Ptr")))
            loop {
                rc := DllCall(this.Proc("sqlite3_step"), "Ptr", statement, "Cdecl Int")
                if rc = 101
                    break
                if rc != 100
                    throw Error("SQLite query failed (code " rc ").")
                row := {}
                loop count {
                    index := A_Index - 1
                    kind := DllCall(this.Proc("sqlite3_column_type"), "Ptr", statement, "Int", index, "Cdecl Int")
                    switch kind {
                        case 1: value := DllCall(this.Proc("sqlite3_column_int64"), "Ptr", statement, "Int", index, "Cdecl Int64")
                        case 2: value := DllCall(this.Proc("sqlite3_column_double"), "Ptr", statement, "Int", index, "Cdecl Double")
                        case 3:
                            ptr := DllCall(this.Proc("sqlite3_column_text16"), "Ptr", statement, "Int", index, "Cdecl Ptr")
                            bytes := DllCall(this.Proc("sqlite3_column_bytes16"), "Ptr", statement, "Int", index, "Cdecl Int")
                            value := bytes ? StrGet(ptr, bytes // 2, "UTF-16") : ""
                        case 4:
                            bytes := DllCall(this.Proc("sqlite3_column_bytes"), "Ptr", statement, "Int", index, "Cdecl Int")
                            ptr := DllCall(this.Proc("sqlite3_column_blob"), "Ptr", statement, "Int", index, "Cdecl Ptr")
                            value := Buffer(bytes)
                            if bytes
                                DllCall("RtlMoveMemory", "Ptr", value, "Ptr", ptr, "UPtr", bytes)
                        default: value := ""
                    }
                    row.DefineProp(names[A_Index], {Value: value})
                }
                rows.Push(row)
            }
            return rows
        } finally DllCall(this.Proc("sqlite3_finalize"), "Ptr", statement, "Cdecl Int")
    }

    Transaction(callback) {
        this.Exec("BEGIN IMMEDIATE")
        try {
            result := callback.Call()
            this.Exec("COMMIT")
            return result
        } catch as err {
            try this.Exec("ROLLBACK")
            throw err
        }
    }

    Close() {
        if this.Handle {
            DllCall(this.Proc("sqlite3_close_v2"), "Ptr", this.Handle, "Cdecl Int")
            this.Handle := 0
        }
    }

    __Delete() {
        try this.Close()
        if this.HasOwnProp("Module") && this.Module
            DllCall("FreeLibrary", "Ptr", this.Module)
    }
}
