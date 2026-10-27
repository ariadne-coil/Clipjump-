# Compatibility and validation

Target platform: Windows 11 x64. Version 13.0.0-beta.3 is a native AutoHotkey v2 port with rebuilt Windows dialogs and clipboard/storage layers, plus restored non-legacy settings and workflows. Compatibility is limited to the tested workflows below; it does not guarantee every app-specific workflow. See the [feature comparison](FEATURE-PARITY.md).

| Area | Status |
| --- | --- |
| Windows 11 Home x64, build 26200 | Local test platform |
| AutoHotkey 2.0.31 Unicode, x64 and x86 | 240 assertions per architecture plus script/executable package startup |
| SQLite 3.54.1, matching DLL architecture | Storage, cross-architecture legacy import, API and startup tests |
| Unicode/emoji, RTF and HTML | Capture, archive and restoration fixtures |
| DIB, opaque binary, Adobe PDF/AICB-style and SVG payloads | Binary restoration fixtures; not Adobe application certification |
| Busy clipboard, stalled renderer, stale capture | Failure and timeout fixtures |
| Microsoft 365 Word/Excel | v1 baseline in TESTING-V1.md; v2 results in TESTING.md |
| PowerPoint, Outlook, OneNote and Access | Direct validation pending |
| Photoshop, Illustrator, InDesign and Acrobat | Direct validation pending; not installed on the development machine |
| Other Creative Cloud apps | Direct validation pending |
| Windows 11 ARM64 | Not validated; no native ARM64 runtime |

## Office capture

The clipboard owner process, rather than the foreground window, selects the Office profile. Recognized names are EXCEL, WINWORD, POWERPNT, OUTLOOK, ONENOTE and MSACCESS.

The profile saves memory-backed text, HTML, RTF, CSV, PNG, SVG and DIB formats when offered. It avoids requesting live OLE objects, linked objects, printer-dependent metafiles and application handles. Such objects have a lifecycle outside a portable archive. Native application copy/paste keeps the original live clipboard; a historical snapshot copies the transferable formats.

Historical Excel clips contain displayed values and formatting. BIFF and spreadsheet XML formats are intentionally omitted: replaying those archived formula payloads in current Excel produced a warning that formulas could not be pasted into the current instance. Native copying/cutting and immediate pasting retain the original live clipboard and its formulas. Linked/embedded Office objects are not certified for historical replay. Microsoft 365 web apps require separate browser testing.

AutoHotkey's standard ClipboardAll routine is used for other apps, including Adobe. It preserves supported registered formats as binary data. Some app-private OLE objects and handles cannot be serialized by that runtime. Adobe fixtures exercise byte preservation; layered Photoshop objects, Illustrator paths, InDesign objects and cross-app paste modes still require licensed-app tests.

## Timing and failures

Capture starts immediately in an isolated worker, without an intentional settle delay. New notifications replace pending work. A worker may run for up to three seconds; a stale or failed result is discarded. The Office profile limits exported memory formats to 64 MiB per clip. Capture does not write to the live clipboard. A clipboard that never settles may not enter history. With original formatting selected, native first paste remains available while capture is pending or unsuccessful. An explicitly selected text format waits for capture and cancels on failure or a new copy; it does not fall back to pasting rich content. Text with a bitmap representation, such as Excel cells, remains eligible for plain-text conversion.

Windows requests can block in a source application's delayed renderer. The worker isolates the stall from Clipjump's UI; it cannot guarantee that the source app itself will not display an error. Requests exceeding the deadline are abandoned.

## Existing data

The port uses separate `cache-v2/` and `settings-v2.ini` files. The tray importer reads original `cache/clips*` and `cache/data.db` without modifying the selected source. Both v1 pointer widths are detected. Safe import recovers standard text, DIB images and file lists. Optional registered-format import is only valid for archives from the same Windows session; numeric IDs in old files cannot reliably identify formats after reboot.

New `.cjc` archives store registered format names and binary payloads, so they can be shared across x86/x64 runtimes and Windows sessions. Lost formatting in old text-only history cannot be recovered. V1 third-party plugins and custom script strings require conversion to native v2 callbacks or named actions. Portable packages contain no user settings or clipboard data.

## Upstream reports guiding this work

- [#73: Word formatting loss](https://github.com/aviaryan/Clipjump/issues/73)
- [#128: Acrobat copying failures](https://github.com/aviaryan/Clipjump/issues/128)
- [#131: Excel copying failures](https://github.com/aviaryan/Clipjump/issues/131)
- [#134: SQLite syntax errors](https://github.com/aviaryan/Clipjump/issues/134)
- [#144: clipboard monitoring interferes with copying](https://github.com/aviaryan/Clipjump/issues/144)

These reports motivate the changes. They are not marked resolved upstream: their original environments and all modern equivalents have not been reproduced.

Primary references: [Windows clipboard operations](https://learn.microsoft.com/en-us/windows/win32/dataxchg/using-the-clipboard), [AutoHotkey clipboard implementation](https://github.com/AutoHotkey/AutoHotkey/blob/v2.0.31/source/clipboard.cpp), [SQLite downloads](https://www.sqlite.org/download.html).
