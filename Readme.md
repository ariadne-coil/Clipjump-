# Clipjump Modern

A Windows 11 continuation of [Avi Aryan's Clipjump](https://github.com/aviaryan/Clipjump), preserving its keyboard-driven clipboard history, channels and plugins. Licensed under Apache 2.0; original credits remain in NOTICE.txt.

**12.6.0-beta.1 is a compatibility beta.** Automated clipboard and history regressions run on Windows 11 x64. Microsoft 365 and Adobe Creative Cloud are compatibility targets; individual app workflows must be validated using the [compatibility matrix](docs/COMPATIBILITY.md). This release does not claim error-free operation across every application.

## Run on Windows 11

Extract the portable x64 ZIP into a writable folder, then double-click **Start-Clipjump.cmd**. No AutoHotkey installation or administrator access is required. Exit an older Clipjump before starting this fork. Use a separate folder for this beta so the previous installation and history remain available.

Copy normally. Hold Ctrl and press V to enter Paste Mode; press V again while holding Ctrl to browse older clips, then release Ctrl to paste. Use the tray menu for History, channels, settings and plugins. If the latest copy is still being captured or capture fails, Ctrl+V passes through to the application's current clipboard. History remains available from the tray.

Plain text conversion is explicit through the formatting commands. Ordinary history copy and paste restore archived rich formats. Legacy history entries originally stored as plain text cannot recover formatting already discarded.

## Compatibility improvements

- Capture runs in a separate process with a three-second deadline. Rapid changes are debounced; stale captures are rejected using clipboard sequence numbers.
- Office capture requests transferable text, HTML, RTF, CSV, DIB, PNG and SVG formats, avoiding printer/metafile rendering and transient OLE object formats. Historical Excel cells retain displayed values and formatting; native copying keeps live formulas.
- Binary snapshots preserve formatting in channels and history. Duplicate detection compares binary content, including formatting changes with identical text.
- Startup indexes archives without clearing or replaying the live clipboard. Capture never steals Excel's focus or sends Delete after Ctrl+X.
- Clipboard access waits are bounded. A failed archive load cancels the paste instead of pasting a different clip.
- SQLite inserts use bound parameters; search safely handles quotes and SQL-like text. Missing thumbnails cannot create malformed SQL. Existing history databases gain a snapshot column without dropping rows.
- Builds include matching Unicode runtimes and current SQLite DLLs, verified against pinned checksums. Previews are generated from archived DIB data.

## Build and test

From PowerShell in this repository:

```powershell
powershell -File scripts/Build.ps1 -Architecture x64
powershell -File scripts/Test.ps1 -Architecture x64
```

Use `-Architecture x86` for the alternative runtime. ZIPs are written to `dist/`; logs are written to `test-results/`. Downloads use pinned vendor URLs and checksums in [scripts/dependencies.json](scripts/dependencies.json).

The application and plugins use **AutoHotkey v1**, specifically the final v1.1.37.02 Unicode runtime. They do not run under AutoHotkey v2. Native ARM64 and a v2 port require further work; x64 emulation on ARM64 has not been validated. Source builds should use the packaged matching interpreter and SQLite DLL.

[Testing details](docs/TESTING.md) · [Compatibility and limits](docs/COMPATIBILITY.md) · [Third-party notices](THIRD-PARTY-NOTICES.md)
