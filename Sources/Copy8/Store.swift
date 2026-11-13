import Foundation
import SQLite3

/// Archivio SQLite della cronologia. Le immagini stanno in file PNG a parte.
final class Store {
    enum StoreError: Error { case open(String) }

    let imagesDirectory: URL
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        imagesDirectory = directory.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.sqlite").path
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
        exec("""
        CREATE TABLE IF NOT EXISTS clips(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind INTEGER NOT NULL,
            text TEXT NOT NULL,
            rtf BLOB,
            html BLOB,
            image TEXT,
            width INTEGER NOT NULL DEFAULT 0,
            height INTEGER NOT NULL DEFAULT 0,
            bytes INTEGER NOT NULL DEFAULT 0,
            source_name TEXT,
            source_bundle TEXT,
            copied_at REAL NOT NULL,
            hash TEXT NOT NULL UNIQUE
        );
        CREATE INDEX IF NOT EXISTS clips_copied_at ON clips(copied_at);
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Lettura

    func loadAll() -> [ClipItem] {
        let sql = "SELECT id, kind, text, image, width, height, bytes, source_name, source_bundle, copied_at, hash FROM clips ORDER BY copied_at DESC"
        guard let st = prepare(sql) else { return [] }
        defer { sqlite3_finalize(st) }
        var items: [ClipItem] = []
        while sqlite3_step(st) == SQLITE_ROW {
            items.append(ClipItem(
                id: sqlite3_column_int64(st, 0),
                kind: ClipKind(rawValue: Int(sqlite3_column_int(st, 1))) ?? .text,
                text: text(st, 2) ?? "",
                imageFile: text(st, 3),
                width: Int(sqlite3_column_int(st, 4)),
                height: Int(sqlite3_column_int(st, 5)),
                byteCount: Int(sqlite3_column_int64(st, 6)),
                sourceName: text(st, 7),
                sourceBundle: text(st, 8),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(st, 9)),
                hash: text(st, 10) ?? ""
            ))
        }
        return items
    }

    func richData(id: Int64) -> (rtf: Data?, html: Data?) {
        guard let st = prepare("SELECT rtf, html FROM clips WHERE id = ?") else { return (nil, nil) }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, id)
        guard sqlite3_step(st) == SQLITE_ROW else { return (nil, nil) }
        return (blob(st, 0), blob(st, 1))
    }

    // MARK: Scrittura

    /// Inserisce un elemento o, se il contenuto esiste già, lo riporta in cima. Restituisce l'id.
    func upsert(kind: ClipKind, text: String, rtf: Data?, html: Data?, image: String?, width: Int, height: Int,
                bytes: Int, sourceName: String?, sourceBundle: String?, date: Date, hash: String) -> Int64? {
        let sql = """
        INSERT INTO clips(kind, text, rtf, html, image, width, height, bytes, source_name, source_bundle, copied_at, hash)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(hash) DO UPDATE SET kind = excluded.kind, rtf = excluded.rtf, html = excluded.html,
            source_name = excluded.source_name, source_bundle = excluded.source_bundle, copied_at = excluded.copied_at
        RETURNING id
        """
        guard let st = prepare(sql) else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(kind.rawValue))
        bind(st, 2, text)
        bind(st, 3, rtf)
        bind(st, 4, html)
        bind(st, 5, image)
        sqlite3_bind_int64(st, 6, Int64(width))
        sqlite3_bind_int64(st, 7, Int64(height))
        sqlite3_bind_int64(st, 8, Int64(bytes))
        bind(st, 9, sourceName)
        bind(st, 10, sourceBundle)
        sqlite3_bind_double(st, 11, date.timeIntervalSince1970)
        bind(st, 12, hash)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(st, 0)
    }

    func touch(id: Int64, date: Date) {
        guard let st = prepare("UPDATE clips SET copied_at = ? WHERE id = ?") else { return }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_double(st, 1, date.timeIntervalSince1970)
        sqlite3_bind_int64(st, 2, id)
        sqlite3_step(st)
    }

    /// Elimina un elemento e restituisce il nome del file immagine, se c'era.
    func delete(id: Int64) -> [String] {
        let files = imageFiles("SELECT image FROM clips WHERE id = ? AND image IS NOT NULL") { sqlite3_bind_int64($0, 1, id) }
        if let st = prepare("DELETE FROM clips WHERE id = ?") {
            sqlite3_bind_int64(st, 1, id)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
        return files
    }

    /// Elimina gli elementi copiati prima di `date` (esclusa) e restituisce i file immagine da rimuovere.
    func deleteOlder(than date: Date) -> [String] {
        deleteWhere("copied_at < ?", date)
    }

    /// Elimina gli elementi copiati fino a `date` (inclusa).
    func deleteUpTo(_ date: Date) -> [String] {
        deleteWhere("copied_at <= ?", date)
    }

    // MARK: Utilità

    private func deleteWhere(_ condition: String, _ date: Date) -> [String] {
        let time = date.timeIntervalSince1970
        let files = imageFiles("SELECT image FROM clips WHERE \(condition) AND image IS NOT NULL") { sqlite3_bind_double($0, 1, time) }
        if let st = prepare("DELETE FROM clips WHERE \(condition)") {
            sqlite3_bind_double(st, 1, time)
            sqlite3_step(st)
            sqlite3_finalize(st)
        }
        return files
    }

    private func imageFiles(_ sql: String, bind: (OpaquePointer) -> Void) -> [String] {
        guard let st = prepare(sql) else { return [] }
        defer { sqlite3_finalize(st) }
        bind(st)
        var files: [String] = []
        while sqlite3_step(st) == SQLITE_ROW {
            if let name = text(st, 0) { files.append(name) }
        }
        return files
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            NSLog("Copy8 SQLite: %@", String(cString: sqlite3_errmsg(db)))
            return nil
        }
        return st
    }

    private func bind(_ st: OpaquePointer, _ index: Int32, _ value: String?) {
        guard let value else { sqlite3_bind_null(st, index); return }
        let chars = value.utf8CString
        chars.withUnsafeBufferPointer { buffer in
            _ = sqlite3_bind_text(st, index, buffer.baseAddress, Int32(buffer.count - 1), transient)
        }
    }

    private func bind(_ st: OpaquePointer, _ index: Int32, _ value: Data?) {
        guard let value, !value.isEmpty else { sqlite3_bind_null(st, index); return }
        value.withUnsafeBytes { buffer in
            _ = sqlite3_bind_blob(st, index, buffer.baseAddress, Int32(buffer.count), transient)
        }
    }

    private func text(_ st: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(st, index) else { return nil }
        let count = Int(sqlite3_column_bytes(st, index))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
    }

    private func blob(_ st: OpaquePointer, _ index: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(st, index) else { return nil }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(st, index)))
    }
}
