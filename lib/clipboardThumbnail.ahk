; Decode a DIB already present in the archive. Never reopen an Office/Adobe
; clipboard from the UI process merely to generate a preview.
CJ_SaveThumbnail(ByRef snapshot, path, quality := 90) {
    total := CJ_BinarySize(snapshot), offset := 0
    while (offset + 4 + A_PtrSize <= total) {
        format := NumGet(snapshot, offset, "UInt")
        if !format
            return false
        size := NumGet(snapshot, offset + 4, "UPtr")
        offset += 4 + A_PtrSize
        if (size < 0 || size > total - offset)
            return false
        if (format = 8 || format = 17) {
            if (size < 40)
                return false
            header := NumGet(snapshot, offset, "UInt")
            if (header < 40 || header > size)
                return false
            bits := NumGet(snapshot, offset + 14, "UShort")
            compression := NumGet(snapshot, offset + 16, "UInt")
            colors := NumGet(snapshot, offset + 32, "UInt")
            if (!colors && bits <= 8)
                colors := 1 << bits
            pixelOffset := header + colors * 4
            if (header = 40 && compression = 3)
                pixelOffset += 12
            if (header = 40 && compression = 6)
                pixelOffset += 16
            if (pixelOffset >= size)
                return false
            token := Gdip_Startup()
            bitmap := 0
            result := DllCall("gdiplus\GdipCreateBitmapFromGdiDib", "Ptr", &snapshot + offset, "Ptr", &snapshot + offset + pixelOffset, "PtrP", bitmap)
            if (result = 0 && bitmap) {
                result := Gdip_SaveBitmapToFile(bitmap, path, quality)
                Gdip_DisposeImage(bitmap)
            }
            Gdip_Shutdown(token)
            return FileExist(path) != ""
        }
        offset += size
    }
    return false
}
