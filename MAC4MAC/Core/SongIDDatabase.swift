import Foundation
import SQLite3
import MusicKit

/// SQLite-based Song ID Mapper with proper indexing and data integrity
public class SongIDDatabase {
    public static let shared = SongIDDatabase()
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let accessQueue = DispatchQueue(label: "com.mac4mac.songiddb", attributes: .concurrent)
    
    // MARK: - Data Model
    
    public struct SongRecord: Codable {
        public let musicItemID: String        // Primary key, universal
        public let catalogID: String?         // Apple Music Store ID
        public let legacyPersistentID: String? // Device-specific iTunes ID
        public let title: String?
        public let artist: String?
        public let album: String?
        public let isComplete: Bool           // True if all IDs are available
        public let isHealthy: Bool            // Data quality flag
        public let createdAt: Date
        public let updatedAt: Date
        
        public init(musicItemID: String, catalogID: String?, legacyPersistentID: String?, 
             title: String?, artist: String?, album: String?, 
             isHealthy: Bool = true) {
            self.musicItemID = musicItemID
            self.catalogID = catalogID
            self.legacyPersistentID = legacyPersistentID
            self.title = title
            self.artist = artist
            self.album = album
            self.isComplete = (catalogID != nil && legacyPersistentID != nil)
            self.isHealthy = isHealthy
            let now = Date()
            self.createdAt = now
            self.updatedAt = now
        }
    }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MAC4MAC", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        dbPath = appFolder.appendingPathComponent("SongIDMappings.db").path
        
        openDatabase()
        createTables()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Error opening database at \(dbPath)")
        } else {
            print("✅ Database opened at \(dbPath)")
        }
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            print("❌ Error closing database")
        }
        db = nil
    }
    
    private func createTables() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS song_mappings (
            music_item_id TEXT PRIMARY KEY NOT NULL,
            catalog_id TEXT,
            legacy_persistent_id TEXT,
            title TEXT,
            artist TEXT,
            album TEXT,
            is_complete INTEGER NOT NULL DEFAULT 0,
            is_healthy INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            print("❌ Error creating table")
        }
        
        // Create indexes for fast lookups
        createIndex(name: "idx_music_item_id", column: "music_item_id")
        createIndex(name: "idx_catalog_id", column: "catalog_id")
        createIndex(name: "idx_legacy_persistent_id", column: "legacy_persistent_id")
        createIndex(name: "idx_is_complete", column: "is_complete")
        createIndex(name: "idx_is_healthy", column: "is_healthy")
        
        print("✅ Database tables and indexes created")
    }
    
    private func createIndex(name: String, column: String) {
        let createIndexSQL = "CREATE INDEX IF NOT EXISTS \(name) ON song_mappings(\(column));"
        sqlite3_exec(db, createIndexSQL, nil, nil, nil)
    }
    
    // MARK: - CRUD Operations
    
    /// Insert or update a song record
    public func upsert(_ record: SongRecord) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO song_mappings 
        (music_item_id, catalog_id, legacy_persistent_id, title, artist, album, 
         is_complete, is_healthy, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if let errorMessage = sqlite3_errmsg(db) {
                print("❌ Error preparing upsert statement: \(String(cString: errorMessage))")
            }
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        // Helper to bind text safely
        func bindText(_ index: Int32, _ value: String?) {
            if let value = value {
                sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else {
                sqlite3_bind_null(statement, index)
            }
        }
        
        bindText(1, record.musicItemID)
        bindText(2, record.catalogID)
        bindText(3, record.legacyPersistentID)
        bindText(4, record.title)
        bindText(5, record.artist)
        bindText(6, record.album)
        sqlite3_bind_int(statement, 7, record.isComplete ? 1 : 0)
        sqlite3_bind_int(statement, 8, record.isHealthy ? 1 : 0)
        sqlite3_bind_double(statement, 9, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 10, record.updatedAt.timeIntervalSince1970)
        
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            if let errorMessage = sqlite3_errmsg(db) {
                print("❌ Error executing upsert: \(String(cString: errorMessage))")
            }
            return false
        }
        
        return true
    }
    
    /// Batch insert with transaction for performance
    public func upsertBatch(_ records: [SongRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        
        // Begin transaction
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        
        var success = true
        for record in records {
            if !upsert(record) {
                success = false
                break
            }
        }
        
        // Commit or rollback
        if success {
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        } else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
        }
        
        return success
    }
    
    /// Lookup by MusicItemID (indexed)
    public func lookupByMusicItemID(_ id: String) -> SongRecord? {
        return lookup(column: "music_item_id", value: id)
    }
    
    /// Lookup by CatalogID (indexed)
    public func lookupByCatalogID(_ id: String) -> SongRecord? {
        return lookup(column: "catalog_id", value: id)
    }
    
    /// Lookup by Legacy Persistent ID (indexed)
    public func lookupByLegacyID(_ id: String) -> SongRecord? {
        return lookup(column: "legacy_persistent_id", value: id)
    }
    
    private func lookup(column: String, value: String) -> SongRecord? {
        let sql = "SELECT * FROM song_mappings WHERE \(column) = ? LIMIT 1;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (value as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        
        return extractRecord(from: statement!)
    }
    
    private func extractRecord(from statement: OpaquePointer) -> SongRecord? {
        let musicItemID = String(cString: sqlite3_column_text(statement, 0))
        let catalogID = sqlite3_column_text(statement, 1).map { String(cString: $0) }
        let legacyID = sqlite3_column_text(statement, 2).map { String(cString: $0) }
        let title = sqlite3_column_text(statement, 3).map { String(cString: $0) }
        let artist = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let album = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        _ = sqlite3_column_int(statement, 6) == 1 // isComplete (computed)
        let isHealthy = sqlite3_column_int(statement, 7) == 1
        _ = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)) // createdAt (auto-set)
        _ = Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)) // updatedAt (auto-set)
        
        return SongRecord(
            musicItemID: musicItemID,
            catalogID: catalogID,
            legacyPersistentID: legacyID,
            title: title,
            artist: artist,
            album: album,
            isHealthy: isHealthy
        )
    }
    
    /// Check if a song exists in the database
    public func exists(_ musicItemID: String) -> Bool {
        let sql = "SELECT 1 FROM song_mappings WHERE music_item_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (musicItemID as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        return sqlite3_step(statement) == SQLITE_ROW
    }
    
    /// Update health status
    func updateHealth(_ musicItemID: String, isHealthy: Bool) -> Bool {
        let sql = """
        UPDATE song_mappings 
        SET is_healthy = ?, updated_at = ?
        WHERE music_item_id = ?;
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, isHealthy ? 1 : 0)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, (musicItemID as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        return sqlite3_step(statement) == SQLITE_DONE
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> (total: Int, complete: Int, healthy: Int, withCatalog: Int, withLegacy: Int) {
        let sql = """
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN is_complete = 1 THEN 1 ELSE 0 END) as complete,
            SUM(CASE WHEN is_healthy = 1 THEN 1 ELSE 0 END) as healthy,
            SUM(CASE WHEN catalog_id IS NOT NULL THEN 1 ELSE 0 END) as with_catalog,
            SUM(CASE WHEN legacy_persistent_id IS NOT NULL THEN 1 ELSE 0 END) as with_legacy
        FROM song_mappings;
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            sqlite3_finalize(statement)
            return (0, 0, 0, 0, 0)
        }
        
        defer { sqlite3_finalize(statement) }
        
        return (
            total: Int(sqlite3_column_int(statement, 0)),
            complete: Int(sqlite3_column_int(statement, 1)),
            healthy: Int(sqlite3_column_int(statement, 2)),
            withCatalog: Int(sqlite3_column_int(statement, 3)),
            withLegacy: Int(sqlite3_column_int(statement, 4))
        )
    }
    
    /// Get all incomplete records (missing IDs)
    func getIncompleteRecords(limit: Int = 100) -> [SongRecord] {
        let sql = "SELECT * FROM song_mappings WHERE is_complete = 0 LIMIT ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(limit))
        
        var records: [SongRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = extractRecord(from: statement!) {
                records.append(record)
            }
        }
        
        return records
    }
    
    /// Get all unhealthy records
    func getUnhealthyRecords(limit: Int = 100) -> [SongRecord] {
        let sql = "SELECT * FROM song_mappings WHERE is_healthy = 0 LIMIT ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(limit))
        
        var records: [SongRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = extractRecord(from: statement!) {
                records.append(record)
            }
        }
        
        return records
    }
    
    /// Clear all data
    public func clearAll() -> Bool {
        return sqlite3_exec(db, "DELETE FROM song_mappings;", nil, nil, nil) == SQLITE_OK
    }
    
    /// Vacuum database to reclaim space
    func vacuum() {
        sqlite3_exec(db, "VACUUM;", nil, nil, nil)
    }
}
