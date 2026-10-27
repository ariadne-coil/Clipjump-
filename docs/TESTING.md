# AutoHotkey v2 validation

Run `scripts/Build.ps1` and `scripts/Test.ps1` with the same architecture. Run sequentially on an interactive Windows desktop with other clipboard managers closed. The tests temporarily replace the clipboard with synthetic data, then restore the original value. They create an isolated temporary data/config directory and remove only that generated directory.

## Automated checks

The native v2 suites make **86 engine assertions, 132 feature assertions and 9 compiled-application assertions on each of x64 and x86**, plus separate script and executable startup smoke tests for each assembled portable package. That is 454 assertions and four package startup checks across both architectures.

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
- Compiled main app and capture worker run in an isolated folder containing no AutoHotkey interpreter or source scripts. Checks cover API discovery, capture-to-history, opaque binary preservation, unchanged live clipboard, worker handle cleanup and shutdown.
- Exact fixed-slot ordering, pinned-order/database migration, clip/channel swaps, combined views, unlimited channels and cleanup thresholds.
- History-only and strict incognito, image-history exclusion, session cleanup, manual-copy owner/expiry checks, Win copy intent, One Time Stop and PitSwap.
- Remembered/default formats, exact plain text with trailing newlines, rich-to-original restoration, mixed Office text/bitmap clips, image-only preservation, History formatting and multipaste/cancel behavior.
- Fast formatted paste waits for the worker; repeated presses queue relative jumps; a new copy cancels the pending paste and still enters history.
- Native search mode, preview Find, full image sizing, New Clip, isolated Hold buffers, external text/image save/reload, Explorer provider integration and multiple file paths.
- Startup shortcut creation/removal in a temporary directory, JPEG quality encoders, complete label catalogs for seven languages and strict-incognito settings migration.
- Deterministic update-worker success/timeout fixtures verify immediate return, callback reporting, process-handle cleanup and temporary-file removal. CI does not depend on a live update service.

The local platform is Windows 11 Home x64 build 26200. Both architectures pass locally. CI runs the same builds and suites on Windows runners. These checks are not application certification.

Beta.2's English and German settings windows were inspected on the local desktop, including the plain-text selector, remembered-format checkbox and shortcut layout. Saving the isolated configuration persisted both formatting and language choices. A separate live update-worker probe successfully read the fork's published releases without blocking the calling app.

## Direct application validation

Microsoft 365 x64 version 16.0.20430.20182 is installed. The earlier v1 beta's Word/Excel acceptance results and Excel-warning reproduction are retained in [TESTING-V1.md](TESTING-V1.md). V2-specific direct results are recorded below as checks are completed.

Adobe Creative Cloud is not installed. PDF/AICB/SVG fixtures verify format-byte preservation, not Photoshop, Illustrator, InDesign or Acrobat behavior. PowerPoint, Outlook, OneNote, Access, Office web apps and ARM64 still need direct acceptance testing.

Explorer integration has automated tests for injected shell selections, folder paths, multiple paths, standard file-list fallback and file data. Direct acceptance across Windows 11 multi-tab Explorer and third-party file managers remains pending. Translation catalogs are complete for the bundled v2 labels; native-speaker review remains welcome.

## Acceptance procedure

Use disposable documents and record app/Windows versions. Copy formatted text, hyperlinks, tables, Unicode and images; replay both the latest copy and an older saved clip after restarting Clipjump. In Excel, check formulas on live first paste, displayed values/formatting from History, and cut/paste without premature source deletion. In Adobe apps, test vectors, transparent raster selections, formatted text and cross-app paste. Exercise rapid copies, a large supported image and a busy clipboard. Failed snapshots must not paste another item.
