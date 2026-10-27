#Requires AutoHotkey v2.0.31+
class CJImage {
    static Token := 0
    static Module := 0
    static Start() {
        if !this.Token {
            if !this.Module
                this.Module := DllCall("LoadLibraryW", "Str", "gdiplus.dll", "Ptr")
            info := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            NumPut("UInt", 1, info)
            token := 0
            if DllCall("gdiplus\GdiplusStartup", "UPtr*", &token, "Ptr", info, "Ptr", 0)
                throw Error("Image previews are unavailable.")
            this.Token := token
        }
    }
    static Stop() {
        if this.Token {
            DllCall("gdiplus\GdiplusShutdown", "UPtr", this.Token)
            this.Token := 0
        }
        if this.Module {
            DllCall("FreeLibrary", "Ptr", this.Module)
            this.Module := 0
        }
    }
    static Save(bitmap, path, png := false, quality := 90) {
        clsid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "Str", png ? "{557cf406-1a04-11d3-9a73-0000f81ef32e}" : "{557cf401-1a04-11d3-9a73-0000f81ef32e}", "Ptr", clsid)
        parameters := Buffer(A_PtrSize = 8 ? 40 : 32, 0), value := Buffer(4, 0)
        offset := A_PtrSize = 8 ? 8 : 4
        NumPut("UInt", 1, parameters), NumPut("UInt", Max(1, Min(100, quality)), value)
        DllCall("ole32\CLSIDFromString", "Str", "{1D5BE4B5-FA4A-452D-9CDD-5DB35105E7EB}", "Ptr", parameters.Ptr + offset)
        NumPut("UInt", 1, parameters, offset + 16), NumPut("UInt", 4, parameters, offset + 20), NumPut("Ptr", value.Ptr, parameters, offset + 24)
        return DllCall("gdiplus\GdipSaveImageToFile", "Ptr", bitmap, "Str", path, "Ptr", clsid, "Ptr", png ? 0 : parameters.Ptr) = 0
    }
    static Thumbnail(snapshot, path, png := false, quality := 90) {
        this.Start()
        bitmap := 0, stream := 0
        try {
            data := snapshot.Find(17)
            if !data
                data := snapshot.Find(8)
            if data {
                if data.Size < 40
                    return false
                header := NumGet(data, 0, "UInt"), bits := NumGet(data, 14, "UShort"), compression := NumGet(data, 16, "UInt"), colors := NumGet(data, 32, "UInt")
                if header < 40 || header > data.Size
                    return false
                width := NumGet(data, 4, "Int"), height := NumGet(data, 8, "Int")
                if width <= 0 || height = 0 || Abs(height) > 100000 || width > 100000 || NumGet(data, 12, "UShort") != 1
                    return false
                if !InStr("|1|4|8|16|24|32|", "|" bits "|") || (compression != 0 && compression != 3 && compression != 6)
                    return false
                if !colors && bits <= 8
                    colors := 1 << bits
                offset := header + colors * 4 + (header = 40 && compression = 3 ? 12 : header = 40 && compression = 6 ? 16 : 0)
                pixelBytes := ((width * bits + 31) // 32) * 4 * Abs(height)
                if offset >= data.Size || pixelBytes > data.Size - offset
                    return false
                DllCall("gdiplus\GdipCreateBitmapFromGdiDib", "Ptr", data, "Ptr", data.Ptr + offset, "Ptr*", &bitmap)
            } else {
                data := snapshot.Find("PNG")
                if !data
                    data := snapshot.Find("image/png")
                if !data
                    return false
                memory := DllCall("GlobalAlloc", "UInt", 2, "UPtr", data.Size, "Ptr")
                ptr := DllCall("GlobalLock", "Ptr", memory, "Ptr")
                if !ptr {
                    DllCall("GlobalFree", "Ptr", memory)
                    return false
                }
                DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", data, "UPtr", data.Size)
                DllCall("GlobalUnlock", "Ptr", memory)
                if DllCall("ole32\CreateStreamOnHGlobal", "Ptr", memory, "Int", true, "Ptr*", &stream) {
                    DllCall("GlobalFree", "Ptr", memory)
                    return false
                }
                DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", stream, "Ptr*", &bitmap)
            }
            return bitmap ? this.Save(bitmap, path, png, quality) : false
        } finally {
            if bitmap
                DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
            if stream
                ObjRelease(stream)
        }
    }

    static FromFile(path) {
        this.Start()
        bitmap := 0
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "Str", path, "Ptr*", &bitmap)
            throw Error("The selected file is not a supported image.")
        try {
            width := 0, height := 0
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", bitmap, "UInt*", &width)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", bitmap, "UInt*", &height)
            if !width || !height || width * height * 4 > 67108864
                throw Error("Image exceeds the 64 MiB import limit.")
            rect := Buffer(16, 0), lock := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
            NumPut("Int", width, rect, 8), NumPut("Int", height, rect, 12)
            if DllCall("gdiplus\GdipBitmapLockBits", "Ptr", bitmap, "Ptr", rect, "UInt", 1, "Int", 0x26200A, "Ptr", lock)
                throw Error("Image pixel data cannot be read.")
            try {
                stride := NumGet(lock, 8, "Int"), source := NumGet(lock, 16, "Ptr"), bytes := width * height * 4
                data := Buffer(124 + bytes, 0)
                NumPut("UInt", 124, data), NumPut("Int", width, data, 4), NumPut("Int", -height, data, 8)
                NumPut("UShort", 1, data, 12), NumPut("UShort", 32, data, 14), NumPut("UInt", 3, data, 16), NumPut("UInt", bytes, data, 20)
                NumPut("UInt", 0x00FF0000, data, 40), NumPut("UInt", 0x0000FF00, data, 44), NumPut("UInt", 0x000000FF, data, 48), NumPut("UInt", 0xFF000000, data, 52)
                NumPut("UInt", 0x73524742, data, 56)
                loop height
                    DllCall("RtlMoveMemory", "Ptr", data.Ptr + 124 + (A_Index - 1) * width * 4, "Ptr", source + (A_Index - 1) * stride, "UPtr", width * 4)
            } finally DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", bitmap, "Ptr", lock)
            snapshot := CJSnapshot()
            snapshot.Entries.Push({Id: 17, Name: "", Data: data})
            fallback := Buffer(40 + bytes, 0)
            DllCall("RtlMoveMemory", "Ptr", fallback, "Ptr", data, "UPtr", 40)
            NumPut("UInt", 40, fallback), NumPut("UInt", 0, fallback, 16)
            DllCall("RtlMoveMemory", "Ptr", fallback.Ptr + 40, "Ptr", data.Ptr + 124, "UPtr", bytes)
            snapshot.Entries.Push({Id: 8, Name: "", Data: fallback})
            return snapshot
        } finally DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
    }
    static Dimensions(path) {
        this.Start(), bitmap := 0, width := 0, height := 0
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "Str", path, "Ptr*", &bitmap)
            return false
        try {
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", bitmap, "UInt*", &width)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", bitmap, "UInt*", &height)
            return {Width: width, Height: height}
        } finally DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
    }
}
