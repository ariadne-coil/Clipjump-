# Native AutoHotkey v2 port

## Scope

The entry point and application under `v2/` run only on AutoHotkey 2.0.31 or later. They use native v2 Gui/ListView, callback hotkeys, ClipboardAll buffers, bound SQLite parameters, and a separate capture worker. No v1 interpreter or converter is used at runtime. `lib/` and `plugins/` are retained as reference source. The v1 entry point and SDK remain on `master` and in Git history.

Implemented: keyboard and search-paste modes; live first paste; configurable paste keys and relative jumps; multi-paste and shift-pop; remembered or default formatting and exact plain text; channel switching/PitSwap; exact fixed positions, tags and partial search; combined channel view and clip/channel swaps; rich history, full image previews and Find; new clips, fresh-selection Hold and external editing; ignored source processes/classes; one-time/manual capture and both incognito policies; Explorer paths/contents; session and storage settings; seven-language UI; startup, priority, memory and overlay controls; bounded update checks; custom hotkeys/hotstrings; native plugins; image-file import; file-path maintenance; translation inspection; existing v1 import and `.cjc` import/export; external API. See [FEATURE-PARITY.md](FEATURE-PARITY.md) for behavior and exclusions.

The UI has been rebuilt with native Windows controls. HTML previews display text and format metadata without executing pasted markup. Original language resources are supplemented by `languages-v2/` catalogs for English, German, Dutch, Brazilian Portuguese, Russian, Swedish and Simplified Chinese. Only interface labels are translated; clipboard contents and channel names are preserved. Native OS error messages and third-party plugin names can remain in their source language. Old custom script evaluation, internal global-variable access, arbitrary `runFunction` strings, v1 third-party plugins and old IE/GDI UI extensions are not compatible. Legacy custom INI files are not executed automatically.

## Clipboard and storage contract

New archives have a CJ2B header, version, entry count, and records containing a format ID, UTF-8 format name and byte payload. Registered IDs are recreated from names when restoring. Record sizes and terminators are validated. History metadata and channel memberships are in a new SQLite database; archive writes use a temporary file and atomic rename.

Office processes use a transferable-format profile: text, HTML, RTF, CSV, DIB/DIBV5, PNG and SVG. Historical Excel replay intentionally flattens formulas to displayed values to avoid cross-instance BIFF/XML warnings. Immediate first paste retains the original application clipboard. Live OLE links and process-owned objects are not portable archives.

Capture is read-only in a child process. It is debounced for 150 ms, canceled on sequence changes, and terminated after a three-second worker deadline. The parent retains a process handle to avoid terminating a reused PID. Copy/cut shortcuts pass through untouched in the default configuration. Optional Win+C/X sends a native copy/cut and arms capture; ordinary Ctrl+C/X stays on the system clipboard in that mode. Startup does not replay archives or alter the clipboard. Explicit formatted paste waits for capture when necessary; capture failure never falls through to an unexpected rich paste.

Database schema 3 adds fixed-slot metadata in a transaction. Existing beta.1 pins retain their prior visible order. The default channel's limit can be zero (unlimited); other channels are unlimited unless the all-channel limit option is enabled. KeepSession controls only the default channel, and does not delete History or other channels. Incognito stops new History entries; its separate strict option also stops capture. Existing strict beta.1 incognito is preserved on upgrade.

The main app keeps file watching and UI work outside the clipboard worker. External editor sessions remain active until **Finish**, since modern editors can hand documents to another process. Update downloads use the same utility executable with an eight-second deadline. Neither worker is terminated by PID alone.

## Legacy import

Select the old installation folder from the tray. Numeric `.avc` files under `cache/clips*` and `cache/data.db` are imported into the new database. Pinned state and tags are copied where available. Import keys prevent duplicate imports of unchanged files. A history snapshot is preferred; otherwise the old text or image is recovered. Source files are opened read-only. Existing discarded formatting cannot be reconstructed.

Safe import accepts standard clipboard formats and detects both old SIZE_T widths. Registered IDs are meaningful only in the Windows session that created them. Enable the optional registered-format recovery only for data from that same session. Old settings/hotkeys are not blindly translated; configure the new settings explicitly.

## Native plugins

The release includes `Clipjump.exe` and `ClipjumpCapture.exe`, compiled using the pinned v2 runtime. Both run without an installed AutoHotkey interpreter. Extract the complete ZIP: the matching SQLite DLL is an external dependency. The bundled source and interpreter remain available for development. Executable plugins are fixed at compile time. To load a local `User.ahk` without compiling, exit `Clipjump.exe` and launch `Clipjump.ahk` with the included matching interpreter, for example `runtime-v2\x64\AutoHotkey.exe Clipjump.ahk` from the extracted folder. Personal `User.ahk` files are excluded from distributed builds.

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

Actions include `history`, `channel-clips`, `channels`, `settings`, `plugins`, `formats`, `hold`, `new-clip`, `external-edit`, `pitswap`, `one-time`, `system-copy`, `system-cut`, `updates`, `paste-help`, `ignore`, `ini`, `custom`, `hotpaste`, `translations`, `import-v1`, `import`, `plain`, `sync`, `monitor:on`, `incognito:on`, `channel:2`, `plugin:upper`, `format:plain`, `text:Hello`, `paste:0,1`, `tip:Hello`, `send:^c`, `sleep:100`, `delete-files`, `history-paths`, `copy-file-data`, `copy-file-path`, `copy-folder-path` and `actions`. Sleep is capped at 10 seconds. `format:plain` sets the default and clears the remembered choice. Use native callbacks for richer extensions.

For isolated development, `--config-dir <folder>` selects settings/customization files and `--data-dir <folder>` selects the database/archive directory. Normal portable launch uses the application folder. The language and worker resources remain relative to the application folder.

## External API

Include `publicAPI.ahk` in a v2 script, then use `cj := Clipjump()` and `cj.getVar("version")`. An optional HWND targets a particular instance. Calls have a two-second transport deadline; each request has a per-client reply file removed after reading. Newlines and backslashes are escaped in requests. Errors raise an exception instead of waiting indefinitely.

Supported operations: `getVar`, `getClipAt`, `getClipLoc`, `getChStrength`, `getChannel`, `changeChannel`, `paste`, `pasteText`, `incognitoMode`, `disable`, `blockMonitoring`, `emptyChannel`, `runPlugin` and `action`. Read-only compatibility globals are explicitly listed in `v2/API.ahk`; assignment is limited to monitoring state. Only known GUI aliases are accepted by `runFunction`. UI/paste commands are deferred outside synchronous WM_COPYDATA handling. The old v1 API wire prefix has a limited bridge; v1 client code itself still needs its v1 interpreter. New `.cjc` paths are not v1 ClipboardAll files.
