# AutoHotkey v2 validation

Run `scripts/Build.ps1` and `scripts/Test.ps1` with the same architecture. Run sequentially on an interactive Windows desktop with other clipboard managers closed. The tests temporarily replace the clipboard with synthetic data, then restore the original value. They create an isolated temporary data/config directory and remove only that generated directory.

## Automated checks

The native v2 regression suite currently makes **86 assertions on each of x64 and x86**, plus a separate smoke test of each assembled portable package.

- Unicode/emoji, quoted text, HTML, RTF, SVG, PDF and Adobe AICB-style binary format capture and replay.
- Name-based registered format restoration independent of old numeric IDs; archive bounds and terminator validation.
- Office safe-format allowlist and exclusions of BIFF, spreadsheet XML and live OLE object formats.
- V1 32/64-bit archive import, safe default versus same-session registered formats, idempotent directory import, source preservation and path traversal rejection.
- Bound SQLite values, binary deduplication, channel copy/move, tags, literal search, pin-preserving compaction, archive replacement and lifetime cleanup.
- DIB encoding, DIBV5 decoding, bitmap fallback and thumbnails.
- Native format plugins, controlled regex errors, custom callback registration and non-executing HTML text parsing.
- Live first paste leaves the application's clipboard unchanged, sends one paste, cycles history, restores rich data on cancel, and cancels when an external copy supersedes it.
- Private mode, ignored processes and all primary native dialogs.
- Cross-process API with escaped multiline/backslash parameters and controlled unknown-operation errors.
- Separate clipboard worker: success, read-only behavior, stale sequence invalidation, lock contention, blocked delayed rendering, bounded deadline and process-handle cleanup.

The local platform is Windows 11 Home x64 build 26200. Both architectures pass locally. CI runs the same builds and suites on Windows runners. These checks are not application certification.

## Direct application validation

Microsoft 365 x64 version 16.0.20430.20182 is installed. The earlier v1 beta's Word/Excel acceptance results and Excel-warning reproduction are retained in [TESTING-V1.md](TESTING-V1.md). V2-specific direct results are recorded below as checks are completed.

Adobe Creative Cloud is not installed. PDF/AICB/SVG fixtures verify format-byte preservation, not Photoshop, Illustrator, InDesign or Acrobat behavior. PowerPoint, Outlook, OneNote, Access, Office web apps and ARM64 still need direct acceptance testing.

## Acceptance procedure

Use disposable documents and record app/Windows versions. Copy formatted text, hyperlinks, tables, Unicode and images; replay both the latest copy and an older saved clip after restarting Clipjump. In Excel, check formulas on live first paste, displayed values/formatting from History, and cut/paste without premature source deletion. In Adobe apps, test vectors, transparent raster selections, formatted text and cross-app paste. Exercise rapid copies, a large supported image and a busy clipboard. Failed snapshots must not paste another item.
