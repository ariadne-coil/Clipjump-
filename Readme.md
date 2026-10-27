# Clipjump Modern — AutoHotkey v2

A native AutoHotkey v2 continuation of [Avi Aryan’s Clipjump](https://github.com/aviaryan/Clipjump), targeting Windows 11. Version **13.0.0-beta.2** ports the clipboard engine, history, channels, paste mode, settings, bundled formats, customization and public API to **AutoHotkey 2.0.31**. Apache 2.0; original credits remain in NOTICE.txt.

This is a compatibility beta. Microsoft 365 and Adobe Creative Cloud are targets; see the [tested scope and limits](docs/COMPATIBILITY.md). Adobe application testing is still pending. The v1 beta remains on `master` while this port is reviewed on `port/ahk-v2`.

## Run

Download the x64 portable ZIP from [Releases](https://github.com/ariadne-coil/Clipjump-/releases), extract the whole ZIP to a writable folder, and double-click **Clipjump.exe**. Keep `ClipjumpCapture.exe` and the `runtime-v2` folder beside it. The matching SQLite DLL is included; no administrator access or AutoHotkey installation is required. **Start-Clipjump.cmd** also launches the executable. Exit other Clipjump instances before starting. The x86 ZIP is available as an alternative.

Copy normally. Hold Ctrl and press V to enter paste mode, press V again to browse older clips, then release Ctrl to paste. With **Keep original formatting** selected, the first paste uses the live application clipboard, preserving Excel’s current formulas and cut operation. Historical Office clips retain transferable rich formatting and displayed cell values.

Copying is silent by default, including when upgrading earlier v2 settings. Capture starts immediately in the background without a settle delay. Paste mode uses the original compact native tooltip: the clip number and contents, with line breaks preserved. A chosen format or alternate action adds a short caption; **F1** opens the shortcut help. Optional copy feedback is available in **Settings → Capture**.

- **Ctrl+Shift+H:** searchable history and combined channel view, previews with Find, instant paste, new clips, external editing, tags, fixed positions, swaps, moving/copying and archive import/export.
- **Ctrl+Shift+O:** channel organizer, protected channels and history exclusion.
- **Ctrl+Shift+A:** action menu. The tray also opens settings, plugins and formatting tools.
- **Ctrl+Alt+V:** explicit plain-text paste.
- In paste mode: **C** previous, **X** cycle cancel/delete/move/copy/delete-all, **Z** next format, **P** plain text, **S** copy without pasting, **A** first clip, **Q** move to first position, **F** search, **Up/Down** change channel, **Space** fixate, **T** tag, **H** external editor, **E** export, **F1** help, **Enter** paste and continue, **1–9** jump relative to the current position. Keep Ctrl held. Escape cancels; Shift when releasing Ctrl removes the pasted channel entry. Paste keys are configurable.

## Formatting and restored features

Open **Settings → General**. **Retain last-used paste format** remembers the format actually used in paste mode, History instant paste or Common Formats, including across restarts. To always paste plain text, clear that checkbox and choose **Plain text** as the default paste format. To keep rich formatting by default, clear it and choose **Keep original formatting**. Ctrl+Alt+V remains a one-time plain-text shortcut. Text conversion preserves Unicode, spaces and trailing newlines; image-only clips stay images. A quick formatted paste waits for a safe snapshot instead of briefly pasting rich data.

Beta.2 restores the non-legacy gaps identified in the first v2 beta: default-channel session retention, unlimited channels and cleanup thresholds, optional image history, copy sounds, manual-copy capture, separate Win+C/X/V shortcuts, One Time Stop, system-only copy/cut, PitSwap, search-paste mode, clip/channel swaps, exact fixed positions, new clips and fresh-selection Hold, external text/image editors, Explorer path/content actions, full image preview and Find, seven-language UI labels, startup/priority/memory controls, overlay settings and a bounded update checker. See the [feature comparison and usage notes](docs/FEATURE-PARITY.md).

Incognito normally keeps channel clips while excluding new copies from History. **Also stop channel capture in incognito** enables stricter privacy. An existing beta.1 installation with incognito enabled keeps that stricter behavior during upgrade.

## Data and extensions

The port starts with separate `cache-v2/` and `settings-v2.ini` files. Use **Import v1 data** from the tray to copy old channel/history data. Both 32-bit and 64-bit v1 archive layouts are recognized. Original files remain untouched. Registered format IDs in old archives cannot reliably identify formats across Windows sessions; safe import recovers standard text, images and file lists. The optional same-session import also recovers registered formats when their IDs still match.

New `.cjc` archives store registered format **names** and binary payloads, making them independent of session IDs and interpreter architecture. History and channel copies retain rich data. Text editing or a formatting command explicitly creates plain text.

V1 third-party scripts need a native v2 port. The bundled formatting/maintenance tools have native v2 equivalents. Prebuilt executables embed the bundled plugins; loading a local `plugins-v2/User.ahk` requires the included source launch mode or a custom compile. See [migration, plugins, custom actions and API](docs/PORTING-V2.md). Old source is retained in the repository for reference and excluded from portable v2 packages.

## Build and test

Run sequentially on an interactive Windows desktop with other clipboard managers closed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Build.ps1 -Architecture x64
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test.ps1 -Architecture x64
```

Repeat with `x86` for the other runtime. Downloads are verified against pinned vendor SHA-256 checksums. Packages in `dist/` exclude developer caches, user settings, clipboard data and v1 code. Test logs are in `test-results/`.

[Feature comparison](docs/FEATURE-PARITY.md) · [Validation](docs/TESTING.md) · [Compatibility](docs/COMPATIBILITY.md) · [Porting guide](docs/PORTING-V2.md) · [Third-party notices](THIRD-PARTY-NOTICES.md)
