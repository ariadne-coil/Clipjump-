#Requires AutoHotkey v2.0.31+
#NoTrayIcon
#SingleInstance Off
if A_Args.Length != 2 || A_Args[1] != "--updates"
    ExitApp(2)
if InStr(A_Args[2], "\slow\")
    Sleep(10000)
FileAppend('[{"tag_name":"v13.0.0-beta.3"}]', A_Args[2], "UTF-8-RAW")
ExitApp(0)
