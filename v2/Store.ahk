#Requires AutoHotkey v2.0.31+
class CJStore {
    __New(directory, sqliteLibrary) {
        this.Root := directory
        this.ClipsDirectory := directory "\clips"
        this.ThumbsDirectory := directory "\thumbs"
        DirCreate(this.ClipsDirectory), DirCreate(this.ThumbsDirectory)
        this.DB := CJDatabase(directory "\history.db", sqliteLibrary)
        this.ThumbnailQuality := 90
        this.DB.Exec("CREATE TABLE IF NOT EXISTS channels (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, protected INTEGER NOT NULL DEFAULT 0, no_history INTEGER NOT NULL DEFAULT 0)")
        this.DB.Exec("CREATE TABLE IF NOT EXISTS clips (id INTEGER PRIMARY KEY, created TEXT NOT NULL, text TEXT NOT NULL, kind TEXT NOT NULL, bytes INTEGER NOT NULL, file TEXT NOT NULL UNIQUE, tag TEXT NOT NULL DEFAULT '', in_history INTEGER NOT NULL DEFAULT 1)")
        this.DB.Exec("CREATE TABLE IF NOT EXISTS memberships (channel_id INTEGER NOT NULL REFERENCES channels(id) ON DELETE CASCADE, clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE, position INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(channel_id,clip_id))")
        hasSlots := false
        for column in this.DB.Query("PRAGMA table_info(memberships)")
            if column.name = "fixed_slot"
                hasSlots := true
        if !hasSlots
            this.DB.Transaction(ObjBindMethod(this, "MigrateFixedSlots"))
        this.DB.Exec("CREATE TABLE IF NOT EXISTS imports (source TEXT PRIMARY KEY, clip_id INTEGER REFERENCES clips(id) ON DELETE SET NULL)")
        this.DB.Exec("CREATE INDEX IF NOT EXISTS clips_created ON clips(created)")
        this.DB.Exec("CREATE INDEX IF NOT EXISTS memberships_order ON memberships(channel_id,position)")
        this.DB.Exec("INSERT OR IGNORE INTO channels(id,name) VALUES (0,'Default')")
        this.DB.Exec("INSERT OR IGNORE INTO channels(id,name,no_history) VALUES (1,'Pit',1)")
        this.DB.Exec("PRAGMA user_version=3")
    }
    MigrateFixedSlots() {
        this.DB.Exec("ALTER TABLE memberships ADD COLUMN fixed_slot INTEGER NOT NULL DEFAULT 0")
        previousChannel := -1, slot := 0
        for row in this.DB.Query("SELECT * FROM memberships ORDER BY channel_id,pinned DESC,position DESC") {
            slot := row.channel_id = previousChannel ? slot + 1 : 1
            previousChannel := row.channel_id
            if row.pinned
                this.DB.Exec("UPDATE memberships SET fixed_slot=?1 WHERE channel_id=?2 AND clip_id=?3", [slot, row.channel_id, row.clip_id])
        }
    }

    Channels() => this.DB.Query("SELECT c.*,COUNT(m.clip_id) AS count FROM channels c LEFT JOIN memberships m ON m.channel_id=c.id GROUP BY c.id ORDER BY c.id")
    Channel(id) {
        rows := this.DB.Query("SELECT * FROM channels WHERE id=?1", [id])
        if !rows.Length
            throw Error("Channel does not exist.")
        return rows[1]
    }
    ChannelId(nameOrId) {
        if RegExMatch(String(nameOrId), "^\d+$") {
            id := Integer(nameOrId)
            this.Channel(id)
            return id
        }
        rows := this.DB.Query("SELECT id FROM channels WHERE name=?1 COLLATE NOCASE", [nameOrId])
        if !rows.Length
            throw Error("Channel does not exist: " nameOrId)
        return rows[1].id
    }
    AddChannel(name, protected := false, noHistory := false) {
        name := Trim(name)
        if name = ""
            throw Error("Enter a channel name.")
        this.DB.Exec("INSERT INTO channels(name,protected,no_history) VALUES (?1,?2,?3)", [name, protected ? 1 : 0, noHistory ? 1 : 0])
        return this.DB.LastId
    }
    UpdateChannel(id, name, protected, noHistory) {
        if Trim(name) = ""
            throw Error("Enter a channel name.")
        this.DB.Exec("UPDATE channels SET name=?1,protected=?2,no_history=?3 WHERE id=?4", [Trim(name), protected ? 1 : 0, noHistory ? 1 : 0, id])
    }
    DeleteChannel(id) {
        if id = 0
            throw Error("The default channel cannot be deleted.")
        this.DB.Exec("DELETE FROM channels WHERE id=?1", [id])
        this.Purge()
    }

    List(channel := 0, history := false, search := "", limit := 2000, partial := false) {
        if history {
            rows := this.DB.Query("SELECT c.*,0 AS pinned,0 AS position,0 AS fixed_slot,-1 AS channel_id FROM clips c WHERE c.in_history=1 ORDER BY c.id DESC")
        } else if channel = -1 {
            rows := this.DB.Query("SELECT c.*,MAX(m.pinned) AS pinned,MAX(m.position) AS position,0 AS fixed_slot,-1 AS channel_id FROM clips c JOIN memberships m ON m.clip_id=c.id GROUP BY c.id ORDER BY c.id DESC")
        } else {
            rows := this.DB.Query("SELECT c.*,m.pinned,m.position,m.fixed_slot,m.channel_id FROM clips c JOIN memberships m ON m.clip_id=c.id WHERE m.channel_id=?1 ORDER BY m.position DESC", [channel])
            rows := CJStore.FixedOrder(rows)
        }
        result := []
        for row in rows {
            if !CJStore.Matches(row.text " " row.tag, search, partial)
                continue
            result.Push(row)
            if result.Length >= limit
                break
        }
        return result
    }
    static Matches(text, search, partial := false) {
        if search = ""
            return true
        terms := partial ? StrSplit(Trim(RegExReplace(search, "\s+", " ")), " ") : [search]
        for term in terms
            if !InStr(StrLower(text), StrLower(term), true)
                return false
        return true
    }
    static FixedOrder(rows) {
        result := [], pins := []
        for row in rows {
            if !row.pinned {
                result.Push(row)
                continue
            }
            index := 1
            while index <= pins.Length && pins[index].fixed_slot <= row.fixed_slot
                index += 1
            pins.InsertAt(index, row)
        }
        for row in pins
            result.InsertAt(Max(1, Min(row.fixed_slot, result.Length + 1)), row)
        return result
    }
    Get(id) {
        rows := this.DB.Query("SELECT c.*,0 AS pinned,0 AS position FROM clips c WHERE c.id=?1", [id])
        if !rows.Length
            throw Error("Clip does not exist.")
        return rows[1]
    }
    Path(recordOrId) {
        record := IsObject(recordOrId) ? recordOrId : this.Get(recordOrId)
        if !RegExMatch(record.file, "^[a-f0-9]{32}\.cjc$")
            throw Error("Unsafe clip file name in database.")
        return this.ClipsDirectory "\" record.file
    }
    Thumbnail(recordOrId) {
        record := IsObject(recordOrId) ? recordOrId : this.Get(recordOrId)
        this.Path(record)
        return this.ThumbsDirectory "\" SubStr(record.file, 1, -4) ".jpg"
    }
    Snapshot(recordOrId) => CJSnapshot.Load(this.Path(recordOrId))

    Add(snapshot, channel := 0, archive := true, deduplicate := false, created := "") {
        this.Channel(channel)
        if !snapshot.Entries.Length
            throw Error("The clip has no transferable formats.")
        if deduplicate {
            previous := this.List(channel, false, "", 1)
            if previous.Length {
                try {
                    if snapshot.Equals(this.Snapshot(previous[1]))
                        return previous[1].id
                }
            }
        }
        name := CJNewId() ".cjc", path := this.ClipsDirectory "\" name
        snapshot.Save(path)
        try {
            this.DB.Exec("BEGIN IMMEDIATE")
            this.DB.Exec("INSERT INTO clips(created,text,kind,bytes,file,in_history) VALUES (?1,?2,?3,?4,?5,?6)", [created != "" ? created : CJNow(), snapshot.Text, snapshot.Kind, snapshot.Size, name, archive ? 1 : 0])
            id := this.DB.LastId
            this.AddMembership(id, channel)
            this.DB.Exec("COMMIT")
        } catch as err {
            try this.DB.Exec("ROLLBACK")
            try FileDelete(path)
            throw err
        }
        try CJImage.Thumbnail(snapshot, this.Thumbnail(id), false, this.ThumbnailQuality)
        return id
    }

    AddHistory(snapshot, created := "") {
        id := this.Add(snapshot, 0, true, false, created)
        this.DB.Exec("DELETE FROM memberships WHERE clip_id=?1", [id])
        return id
    }

    AddMembership(id, channel) {
        this.Channel(channel)
        this.DB.Exec("INSERT INTO memberships(channel_id,clip_id,position) SELECT ?1,?2,COALESCE(MAX(position),0)+1 FROM memberships WHERE channel_id=?1 ON CONFLICT(channel_id,clip_id) DO UPDATE SET position=excluded.position", [channel, id])
    }

    Move(id, origin, destination, copy := false) {
        this.Get(id), this.Channel(destination)
        this.DB.Exec("BEGIN IMMEDIATE")
        try {
            this.AddMembership(id, destination)
            if !copy && origin != destination {
                if origin = -1
                    this.DB.Exec("DELETE FROM memberships WHERE channel_id<>?1 AND clip_id=?2", [destination, id])
                else
                    this.DB.Exec("DELETE FROM memberships WHERE channel_id=?1 AND clip_id=?2", [origin, id])
            }
            this.DB.Exec("COMMIT")
        } catch as err {
            this.DB.Exec("ROLLBACK")
            throw err
        }
    }

    Pin(id, channel, value) {
        slot := 0
        if value
            for index, row in this.List(channel, false, "", 100000)
                if row.id = id
                    slot := index
        this.DB.Exec("UPDATE memberships SET pinned=?1,fixed_slot=?2 WHERE channel_id=?3 AND clip_id=?4", [value ? 1 : 0, slot, channel, id])
    }
    ToFront(id, channel) {
        this.AddMembership(id, channel)
        this.DB.Exec("UPDATE memberships SET fixed_slot=fixed_slot+1 WHERE channel_id=?1 AND pinned=1 AND clip_id<>?2", [channel, id])
        this.DB.Exec("UPDATE memberships SET fixed_slot=1 WHERE channel_id=?1 AND clip_id=?2 AND pinned=1", [channel, id])
    }
    SwapClips(first, second, firstChannel, secondChannel) {
        if first = second && firstChannel = secondChannel
            return
        a := this.DB.Query("SELECT * FROM memberships WHERE channel_id=?1 AND clip_id=?2", [firstChannel, first])
        b := this.DB.Query("SELECT * FROM memberships WHERE channel_id=?1 AND clip_id=?2", [secondChannel, second])
        if !a.Length || !b.Length
            throw Error("Both clips must belong to the selected channels.")
        if firstChannel != secondChannel && (this.DB.Query("SELECT 1 FROM memberships WHERE channel_id=?1 AND clip_id=?2", [firstChannel, second]).Length || this.DB.Query("SELECT 1 FROM memberships WHERE channel_id=?1 AND clip_id=?2", [secondChannel, first]).Length)
            throw Error("A clip already belongs to the other channel. Choose a different pair.")
        this.DB.Exec("BEGIN IMMEDIATE")
        try {
            this.DB.Exec("DELETE FROM memberships WHERE (channel_id=?1 AND clip_id=?2) OR (channel_id=?3 AND clip_id=?4)", [firstChannel, first, secondChannel, second])
            for pair in [[a[1], second], [b[1], first]]
                this.DB.Exec("INSERT INTO memberships(channel_id,clip_id,position,pinned,fixed_slot) VALUES (?1,?2,?3,?4,?5)", [pair[1].channel_id, pair[2], pair[1].position, pair[1].pinned, pair[1].fixed_slot])
            this.DB.Exec("COMMIT")
        } catch as err {
            this.DB.Exec("ROLLBACK")
            throw err
        }
    }
    SwapChannels(first, second) {
        this.Channel(first), this.Channel(second)
        if first = second
            return
        rows := this.DB.Query("SELECT * FROM memberships WHERE channel_id=?1 OR channel_id=?2", [first, second])
        this.DB.Exec("BEGIN IMMEDIATE")
        try {
            this.DB.Exec("DELETE FROM memberships WHERE channel_id=?1 OR channel_id=?2", [first, second])
            for row in rows
                this.DB.Exec("INSERT INTO memberships(channel_id,clip_id,position,pinned,fixed_slot) VALUES (?1,?2,?3,?4,?5)", [row.channel_id = first ? second : first, row.clip_id, row.position, row.pinned, row.fixed_slot])
            this.DB.Exec("COMMIT")
        } catch as err {
            this.DB.Exec("ROLLBACK")
            throw err
        }
    }
    Tag(id, tag) => this.DB.Exec("UPDATE clips SET tag=?1 WHERE id=?2", [tag, id])

    Replace(id, snapshot) {
        original := this.Get(id), name := CJNewId() ".cjc", path := this.ClipsDirectory "\" name
        snapshot.Save(path)
        try this.DB.Exec("UPDATE clips SET text=?1,kind=?2,bytes=?3,file=?4 WHERE id=?5", [snapshot.Text, snapshot.Kind, snapshot.Size, name, id])
        catch as err {
            try FileDelete(path)
            throw err
        }
        try FileDelete(this.Path(original))
        try FileDelete(this.Thumbnail(original))
        try CJImage.Thumbnail(snapshot, this.Thumbnail(id), false, this.ThumbnailQuality)
    }

    Remove(id, channel := 0, fromHistory := false) {
        if fromHistory
            this.DB.Exec("UPDATE clips SET in_history=0 WHERE id=?1", [id])
        else if channel = -1
            this.DB.Exec("DELETE FROM memberships WHERE clip_id=?1", [id])
        else
            this.DB.Exec("DELETE FROM memberships WHERE channel_id=?1 AND clip_id=?2", [channel, id])
        this.Purge()
    }
    Clear(channel := 0, history := false) {
        if history
            this.DB.Exec("UPDATE clips SET in_history=0")
        else if channel = -1
            this.DB.Exec("DELETE FROM memberships")
        else
            this.DB.Exec("DELETE FROM memberships WHERE channel_id=?1", [channel])
        this.Purge()
    }
    Compact(channel, maximum) {
        records := this.DB.Query("SELECT clip_id FROM memberships WHERE channel_id=?1 AND pinned=0 ORDER BY position DESC LIMIT -1 OFFSET ?2", [channel, maximum])
        for record in records
            this.DB.Exec("DELETE FROM memberships WHERE channel_id=?1 AND clip_id=?2", [channel, record.clip_id])
        this.Purge()
    }
    Expire(days) {
        if days > 0
            this.DB.Exec("UPDATE clips SET in_history=0 WHERE created<datetime('now','localtime',?1)", ["-" days " days"])
        this.Purge()
    }
    Purge() {
        records := this.DB.Query("SELECT * FROM clips WHERE in_history=0 AND NOT EXISTS(SELECT 1 FROM memberships WHERE clip_id=clips.id)")
        for record in records {
            path := this.Path(record), thumbnail := this.Thumbnail(record)
            this.DB.Exec("DELETE FROM clips WHERE id=?1", [record.id])
            try FileDelete(path)
            try FileDelete(thumbnail)
        }
    }
    Close() => this.DB.Close()
}
