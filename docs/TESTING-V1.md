# Testing

Run `scripts/Build.ps1` and `scripts/Test.ps1` with the same architecture. Tests temporarily replace the system clipboard with synthetic fixtures and restore its previous value on exit. Run sequentially on an interactive Windows desktop; concurrent clipboard tests would interfere.

## Automated coverage

- Capture/restoration: Unicode, emoji, RTF, HTML with fragment offsets, DIB, SVG, opaque bytes including embedded zeroes, PDF/AICB-style formats and Office's safe profile.
- Atomic storage: binary comparison, formatting-only changes, Unicode paths and preservation of an existing archive when a replacement fails.
- Lifecycle: worker completion, sequence invalidation, locked clipboard access and a deliberately blocked delayed renderer with a bounded deadline.
- History: migration from the original schema, repeated migration, exact text with quotes/newlines/SQL-like content, UTF-8 sizes, binary archives and literal searches.
- Missing thumbnails cannot produce invalid SQL or broken history rows.
- Full application: startup with matching SQLite DLL and confirmation that the clipboard sequence is unchanged.

CI runs both interpreter architectures on Windows runners. These checks do not substitute for app-level testing.

## Manual app acceptance procedure

Use disposable documents; record app version and Windows build. Keep default formatting selected.

1. Copy text with bold, italic, a hyperlink, a table and non-ASCII characters. Paste the latest clip, an older channel clip and a History clip. Verify formatting after restarting Clipjump.
2. Repeat with identical text but different formatting. Both versions should remain distinct with duplicate suppression enabled.
3. In Excel, test rectangular cells with formulas, values, dates, currency, merged cells and different number formats. Repeat native cut/paste; capture must not send Delete or change the source selection.
4. In Word/Outlook/PowerPoint, test text, embedded images, tables and mixed content. Test plain-text paste as an explicit separate action.
5. In Illustrator/InDesign/Photoshop, test text, vectors, transparent raster selections and cross-app copy. Record formats surviving historical replay. Live OLE/linked objects are outside the supported archive contract.
6. In Acrobat, test ordinary Copy, Copy With Formatting and different PDFs, with and without switching windows.
7. Repeat fast consecutive copies and a large supported image. Native clipboard should remain usable; unavailable snapshots must fail without pasting another item.

## Direct application results

Development machine: Windows 11 Home x64 build 26200; Microsoft 365 x64 version 16.0.20430.20182. Results are recorded after each check. Adobe Creative Cloud applications are not installed here.

- Word: copied a bold sample, pasted through Ctrl+V into a paragraph with bold disabled, then selected an older sample in Clipjump History and used instant paste. Both restored the bold sample with no observed error dialog. This is a basic rich-text check, not coverage of embedded OLE objects, all Word formats or every Office app.
- Excel: copied bold currency cells containing a value of 100 and formula `=A1*2` from A1:B1 to D1:E1. Formatting survived and E1 retained the adjusted formula `=D1*2`. Cut D1:E1 to G1:H1; source cells remained present after Ctrl+X and were cleared once on paste. No error dialog was observed. Copy/cut monitoring was changed to passive key observation after direct testing exposed a failure in the original re-sent keystrokes.
- Excel History: replaying an initial ClipboardAll snapshot reproduced the current Excel cross-instance formula warning. The final Office profile resolves hidden clipboard owners by PID and omits BIFF/spreadsheet XML. Repeating History instant paste into A2:B2 preserved bold currency values 100 and 200 with no warning dialog. Historical formulas are intentionally flattened to their displayed values.
