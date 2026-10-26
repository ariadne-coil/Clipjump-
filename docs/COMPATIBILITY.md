# Compatibility and validation

Target platform: Windows 11 x64. This beta preserves the original UI and scripting model while replacing clipboard capture and storage paths. It is not a complete rewrite or a guarantee against all app-specific errors.

| Area | Status |
| --- | --- |
| Windows 11 Home x64, build 26200 | Local test platform |
| AutoHotkey 1.1.37.02 Unicode, x64 and x86 | Clipboard and SQLite regression suites |
| SQLite 3.54.1, matching DLL architecture | Storage, legacy-schema migration and startup tests |
| Unicode/emoji, RTF and HTML | Capture, archive and restoration fixtures |
| DIB, opaque binary, Adobe PDF/AICB-style and SVG payloads | Binary restoration fixtures; not Adobe application certification |
| Busy clipboard, stalled renderer, stale capture | Failure and timeout fixtures |
| Microsoft 365 Word/Excel | Direct results recorded in TESTING.md |
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

Capture starts after 150 milliseconds of stability. New notifications replace pending work. A worker may run for up to three seconds; a stale or failed result is discarded. The Office profile limits exported memory formats to 64 MiB per clip. Capture does not write to the live clipboard. A clipboard that never settles may not enter history. Native paste remains available while capture is pending or unsuccessful.

Windows requests can block in a source application's delayed renderer. The worker isolates the stall from Clipjump's UI; it cannot guarantee that the source app itself will not display an error. Requests exceeding the deadline are abandoned.

## Existing data

Keep the previous installation backed up. This beta adds a nullable snapshot column to the existing history table. Existing text-only history remains readable; newly captured entries retain rich-format archives. History expiration and deletion remove associated snapshot files.

Legacy `.avc` archives depend on the runtime's pointer width. Do not copy old x86 archives into an x64 installation or vice versa. Architecture migration and cross-architecture import validation are not included in this beta. Portable packages contain no user settings or clipboard data.

## Upstream reports guiding this work

- [#73: Word formatting loss](https://github.com/aviaryan/Clipjump/issues/73)
- [#128: Acrobat copying failures](https://github.com/aviaryan/Clipjump/issues/128)
- [#131: Excel copying failures](https://github.com/aviaryan/Clipjump/issues/131)
- [#134: SQLite syntax errors](https://github.com/aviaryan/Clipjump/issues/134)
- [#144: clipboard monitoring interferes with copying](https://github.com/aviaryan/Clipjump/issues/144)

These reports motivate the changes. They are not marked resolved upstream: their original environments and all modern equivalents have not been reproduced.

Primary references: [Windows clipboard operations](https://learn.microsoft.com/en-us/windows/win32/dataxchg/using-the-clipboard), [AutoHotkey clipboard implementation](https://github.com/AutoHotkey/AutoHotkey/blob/v1.1.37.02/source/clipboard.cpp), [SQLite downloads](https://www.sqlite.org/download.html).
