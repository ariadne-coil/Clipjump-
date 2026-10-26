# Native AutoHotkey v2 port

## Scope

The entry point and application under `v2/` run only on AutoHotkey 2.0.31 or later. They use native v2 Gui/ListView, callback hotkeys, ClipboardAll buffers, bound SQLite parameters, and a separate capture worker. No v1 interpreter or converter is used at runtime. `lib/` and `plugins/` are retained as reference source. The v1 entry point and SDK remain on `master` and in Git history.

Implemented: keyboard paste mode; live first paste; next/previous and numeric clip selection; multi-paste and shift-pop; channel switching; pins, tags and search; rich history and previews; hold/edit; ignored source processes/classes; monitoring/private mode; settings; custom hotkeys and hotstrings; format plugins; image-file import; file-path maintenance; translation-file inspection; v1 import and `.cjc` import/export; external API.

The UI has been rebuilt with native Windows controls. HTML previews display text and format metadata without executing pasted markup. Existing language files are available to the translation lookup, but the new interface currently retains English labels for new controls. Old custom script evaluation, internal global-variable access, arbitrary `runFunction` strings, v1 third-party plugins and old IE/GDI UI extensions are not compatible. Legacy custom INI files are not executed automatically.

## Clipboard and storage contract

New archives have a CJ2B header, version, entry count, and records containing a format ID, UTF-8 format name and byte payload. Registered IDs are recreated from names when restoring. Record sizes and terminators are validated. History metadata and channel memberships are in a new SQLite database; archive writes use a temporary file and atomic rename.

Office processes use a transferable-format profile: text, HTML, RTF, CSV, DIB/DIBV5, PNG and SVG. Historical Excel replay intentionally flattens formulas to displayed values to avoid cross-instance BIFF/XML warnings. Immediate first paste retains the original application clipboard. Live OLE links and process-owned objects are not portable archives.

Capture is read-only in a child process. It is debounced for 150 ms, canceled on sequence changes, and terminated after a three-second worker deadline. The parent retains a process handle to avoid terminating a reused PID. Copy/cut shortcuts pass through untouched. Startup does not replay archives or alter the clipboard.

## Legacy import

Select the old installation folder from the tray. Numeric `.avc` files under `cache/clips*` and `cache/data.db` are imported into the new database. Pinned state and tags are copied where available. Import keys prevent duplicate imports of unchanged files. A history snapshot is preferred; otherwise the old text or image is recovered. Source files are opened read-only. Existing discarded formatting cannot be reconstructed.

Safe import accepts standard clipboard formats and detects both old SIZE_T widths. Registered IDs are meaningful only in the Windows session that created them. Enable the optional registered-format recovery only for data from that same session. Old settings/hotkeys are not blindly translated; configure the new settings explicitly.

## Native plugins

Create `plugins-v2/User.ahk` using the supplied example. Assign `CJ_UserPluginLoader` to a callback which receives the registry:

```autohotkey
CJ_UserPluginLoader := RegisterMyPlugins
RegisterMyPlugins(registry) {
    registry.Register("prefix", "Add prefix", (text, parameter) => "Note: " text)
    registry.Register("my-history", "Open history", (*) => registry.App.Action("history"), "command")
}
```

Format callbacks accept `(text, parameter)` and return text. Command callbacks can use `registry.App`. Plugin code is trusted local code, runs in the main process and must use v2 syntax. The registry includes plain/trim/upper/lower/sentence/numbered/HTML-list/BBCode-list/escape-HTML/HTML-to-text/regex formats and native equivalents of bundled management tools. Translation cleaning reports duplicate keys for review rather than rewriting the vendor files.

## Declarative customization

`ClipjumpCustom-v2.ini` uses `[Hotkeys]` entries such as `^!h=history` and an optional `[AutoRun]` list of named actions. `HotPaste-v2.ini` uses `[Text]` entries such as `signature=Regards` and `[Clips]` entries such as `address=0,1` (channel ID/name, one-based clip index). Use the tray plugin tools to edit these files and reload their configuration.

Actions include `history`, `channel-clips`, `channels`, `settings`, `plugins`, `formats`, `hold`, `ignore`, `ini`, `custom`, `hotpaste`, `translations`, `import-v1`, `import`, `plain`, `sync`, `monitor:on`, `incognito:on`, `channel:2`, `plugin:upper`, `format:plain`, `text:Hello`, `paste:0,1`, `tip:Hello`, `send:^c`, `sleep:100`, `delete-files`, `history-paths`, `copy-file-data`, `copy-file-path`, `copy-folder-path` and `actions`. Sleep is capped at 10 seconds. Use native callbacks for richer extensions.

## External API

Include `publicAPI.ahk` in a v2 script, then use `cj := Clipjump()` and `cj.getVar("version")`. An optional HWND targets a particular instance. Calls have a two-second transport deadline; each request has a per-client reply file removed after reading. Newlines and backslashes are escaped in requests. Errors raise an exception instead of waiting indefinitely.

Supported operations: `getVar`, `getClipAt`, `getClipLoc`, `getChStrength`, `getChannel`, `changeChannel`, `paste`, `pasteText`, `incognitoMode`, `disable`, `blockMonitoring`, `emptyChannel`, `runPlugin` and `action`. Read-only compatibility globals are explicitly listed in `v2/API.ahk`; assignment is limited to monitoring state. Only known GUI aliases are accepted by `runFunction`. UI/paste commands are deferred outside synchronous WM_COPYDATA handling. The old v1 API wire prefix has a limited bridge; v1 client code itself still needs its v1 interpreter. New `.cjc` paths are not v1 ClipboardAll files.
