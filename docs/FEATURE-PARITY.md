# Features in 13.0.0-beta.3

This comparison covers the non-legacy gaps identified between original Clipjump 12.5 and the first native v2 beta. Windows controls and native v2 implementations replace the old UI components. It is a feature comparison, not certification of every Microsoft 365 or Adobe workflow; see [COMPATIBILITY.md](COMPATIBILITY.md).

| Area | Native v2 behavior |
| --- | --- |
| Formatting | Retain the last-used format across sessions, or reset to a chosen default; exact plain text is a default, paste-mode choice and one-time shortcut. History instant paste follows the same preference. |
| Session storage | Retain or clear the default channel across restarts. History and other channels persist independently. |
| Channel capacity | Default-channel limit, cleanup threshold, zero for unlimited, optional limit on every channel. Other channels are unlimited by default. |
| Image history | Exclude images from History while retaining their channel clips; configurable JPEG thumbnail quality. |
| Copy feedback | Silent by default, including upgrades from earlier v2 settings; capture confirmation and a beep are explicit options. The isolated reader starts immediately without a settle delay. |
| Capture control | Pause monitoring, capture only explicit copy/cut, One Time Stop, system-only copy/cut shortcuts, optional Win+C/X/V split. |
| Incognito | Exclude new copies from History while keeping channel capture; optional strict mode stops channel capture too. Beta.1's strict incognito preference survives upgrade. |
| PitSwap | Switch to the Pit channel and back to the previous channel. |
| Paste controls | Compact native tooltip showing the clip number and contents; extra caption details only for a chosen format, alternate action or non-default channel. Configurable keys, relative number jumps, first-position jump, move-to-front, exact fixed positions, action modes, channel arrows, copy without pasting, F1 help and multipaste. |
| Search-paste mode | Search and paste without holding Ctrl; Enter/middle-click pastes, Ctrl+Enter keeps the window open, Ctrl+F returns a selection to normal paste mode. Optional start-in-search setting. |
| History and channels | Combined channel view, literal/partial search, new clips/channels, clip/channel swaps and a configurable close-after-paste policy. |
| Preview | Full saved image with aspect-preserving resize; text Find with Ctrl+F, F3 and Enter. Clipboard HTML is never executed. |
| Hold | Copy a fresh selection into a temporary Hold buffer without automatically adding it to a channel; copy/paste, formats and explicit Add to channel. |
| External editing | Configurable text/image executables; saved changes reload into the selected clip. Text edits become plain text; unchanged internal edits preserve rich formatting. |
| Explorer actions | Selected file paths, active folder path and selected file contents through the shell; standard copied file lists provide a fallback for other managers. |
| Languages | Native interface catalogs for English, German, Dutch, Brazilian Portuguese, Russian, Swedish and Simplified Chinese. User text and channel names are preserved. |
| System and appearance | Startup shortcut, process priority, optional working-set trim, paste overlay visibility/position and pasting confirmation. |
| Updates | Checks this fork's releases in a separate worker with an eight-second deadline; opens a release page on request. |

## Formatting setup

In **Settings → General**:

- For a remembered choice, enable **Retain last-used paste format**. The last format actually used in paste mode, History instant paste or Common Formats is reused. Canceling a selection does not replace it.
- For consistent plain text, disable that option and select **Plain text** under **Default paste format**.
- For rich formatting, disable it and select **Keep original formatting**. Live first paste keeps the source application's clipboard, including Excel formulas; stored Office clips use transferable formatting and displayed values.

During normal Ctrl+V paste mode, **Z** cycles formats and **P** chooses plain text. Release Ctrl to apply. **Ctrl+Alt+V** performs a one-time plain-text paste without changing the remembered preference. Image-only clips stay images. Text transformations preserve Unicode and plain text does not trim whitespace or trailing newlines.

## Restored workflows

Optional global shortcuts are blank until assigned in **Settings → Shortcuts**. PitSwap, One Time Stop and Explorer actions also appear in the action menu. Enabling **Use Win+C / Win+X for Clipjump** changes paste mode to Win+V. Ctrl+C/X continues to copy/cut normally but does not enter Clipjump; Win+C/X arms Clipjump capture and sends the application's native copy/cut.

**X** in paste mode cycles cancel, delete, move, copy and delete-all. Releasing the modifier confirms the displayed action. **S** keeps the selection on the clipboard without sending paste; **A** jumps to the first clip; **Q** moves the selected clip to first position; number keys jump relative to the current direction. **Space** fixates a clip at its current numbered slot. **F1** displays the configured keys. Escape cancels directly.

From History, use **New clip** or Ctrl+N; Ctrl+Shift+N opens channel creation. **Swap** exchanges two selected clips in the current channel, or opens a source/destination chooser for one selection. The channel organizer exchanges whole channel contents while retaining channel names and identities. Duplicate cross-channel membership collisions are rejected without changing stored data.

**Hold selection** sends one native copy to the previously active app. The resulting temporary buffer is not archived until explicitly added. **External editor** opens a working file for an existing clip. Save normally in the editor, then use **Finish** in Clipjump when done. The watcher stays active even when the editor hands the document to another process. Finishing removes Clipjump's temporary working file; imported changes remain in the clip.

## Legacy work excluded

This update does not emulate AutoHotkey v1 syntax, execute old custom INI script strings, expose arbitrary internal globals/functions, port third-party v1 plugins automatically, or restore IE/ActiveX, old GDI overlays or the legacy settings editor. The existing safe v1 data importer and limited API bridge remain available; their legacy compatibility has not been expanded. Native callback plugins and declarative v2 customization are documented in [PORTING-V2.md](PORTING-V2.md).

Direct Adobe application testing, untested Office applications, Windows ARM64, Windows 11 Explorer multi-tab acceptance and native-speaker translation review remain validation work, not claimed compatibility guarantees.
