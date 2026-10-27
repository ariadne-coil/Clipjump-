#Requires AutoHotkey v2.0.31+
; Copy to User.ahk to enable. Never use v1 command syntax here.
CJ_UserPluginLoader := RegisterExamplePlugins
RegisterExamplePlugins(registry) {
    registry.Register("prefix", "Add a note prefix", (text, parameter) => "Note: " text)
}
