#Requires AutoHotkey v1.1.37+
#NoEnv
#NoTrayIcon
#SingleInstance, Off
SetBatchLines, -1
FileEncoding, UTF-8-RAW
global failures := 0, checks := 0
global originalClipboard := ClipboardAll
global root := A_ScriptDir "\.."
global testDir := A_Temp "\Clipjump-history-tests-" DllCall("GetCurrentProcessId")
FileCreateDir, % testDir
SetWorkingDir, % testDir
OnExit, Cleanup
SQLiteDB.BaseClass._SQLiteDLL := root "\runtime\" (A_PtrSize = 8 ? "x64" : "x86") "\sqlite3.dll"
global db := new SQLiteDB()
Assert(db.OpenDB(testDir "\history.db"), "open current SQLite DLL")
Assert(db.Exec("CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT, type INTEGER, fileid TEXT, time TEXT, size INTEGER)"), "create legacy history schema")
Assert(CJ_HistoryEnsureSchema(db), "migrate legacy history schema without dropping data")
Assert(CJ_HistoryEnsureSchema(db), "schema migration is idempotent")

text := "O'Brien said ""paste, safely""; DROP TABLE history; -- " Chr(0x4E2D) "`nsecond line"
Clipboard := text
snapshot := ClipboardAll
Assert(CJ_HistoryWrite(db, text, "2026-10-26 12:00:00", snapshot), "bind quotes, newlines and SQL-like clipboard text safely")
Assert(db.GetTable("SELECT data,snapshot,size FROM history", result), "read stored history")
result.Next(row)
Assert(row[1] = text, "history text remains exact")
Assert(row[3] = StrPut(text, "UTF-8") - 1, "history stores UTF-8 byte size")
Assert(CJ_SnapshotEqualsFile(row[2], snapshot), "history keeps full binary snapshot")
Assert(db.GetTable(CJ_HistorySearchSql("O'Brien"), result) && result.RowCount = 1, "search safely handles apostrophes")
Assert(db.GetTable(CJ_HistorySearchSql("paste, safely"), result) && result.RowCount = 1, "search safely handles punctuation")
Assert(db.GetTable(CJ_HistorySearchSql("O'Brien second", true), result) && result.RowCount = 1, "partial search combines literal terms")
Assert(db.GetTable(CJ_HistorySearchSql("' OR 1=1 --"), result) && result.RowCount = 0, "search treats SQL-like criteria as literal data")
Assert(!CJ_HistoryWrite(db, "[IMAGE]", "2026-10-26 12:00:00", snapshot, testDir "\missing-thumbnail.jpg"), "missing thumbnail fails safely without malformed SQL")
Assert(db.GetTable("SELECT count(*) FROM history", result), "database remains usable after missing thumbnail")
result.Next(row)
Assert(row[1] = 1, "missing thumbnail adds no broken history row")

FileAppend, % "RESULT " checks " checks; " failures " failures; " (A_PtrSize * 8) "-bit`n", *
ExitApp, % failures ? 1 : 0

Assert(condition, name) {
    global checks, failures
    checks += 1
    if !condition
        failures += 1
    FileAppend, % (condition ? "PASS " : "FAIL ") name "`n", *
}

Cleanup:
    if IsObject(db)
        db.CloseDB()
    try Clipboard := originalClipboard
    ExitApp, % failures ? 1 : 0

#Include %A_ScriptDir%\..\lib\clipboardIO.ahk
#Include %A_ScriptDir%\..\lib\historyStore.ahk
#Include %A_ScriptDir%\..\lib\SQLiteDB\Class_SQLiteDB.ahk
