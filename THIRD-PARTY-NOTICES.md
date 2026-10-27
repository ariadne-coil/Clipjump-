# Third-party components

Clipjump Modern is derived from Avi Aryan's Clipjump, Apache License 2.0. The original NOTICE.txt and source attribution are preserved.

Portable builds bundle unmodified AutoHotkey 2.0.31 Unicode runtimes, licensed under GNU GPL version 2 or later. Each runtime directory includes its vendor license. Corresponding source for this exact runtime is available at https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.31. Clipjump source files are distributed alongside the interpreter.

SQLite 3.54.1 is public domain: https://www.sqlite.org/copyright.html. Binary origins and SHA-256 checksums are recorded in scripts/dependencies.json.

Clipjump.exe and ClipjumpCapture.exe embed the AutoHotkey 2.0.31 interpreter and application source using the official Ahk2Exe compiler. The GPL runtime license, application sources and exact vendor source link accompany the executables. Ahk2Exe 1.1.37.02a2 is a build-only dependency, GPL version 2 or later, from https://github.com/AutoHotkey/Ahk2Exe/tree/Ahk2Exe1.1.37.02a2; its pinned download checksum is recorded in scripts/dependencies.json. The compiler itself is not distributed in the portable ZIP.

Existing GDI+, SQLite wrapper, TooltipEx, font, translation and plugin attributions remain in their original files. The fork does not claim authorship of those components.
