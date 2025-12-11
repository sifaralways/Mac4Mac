import Foundation
import MusicKit

/// Maps between different song identifier formats: MusicItemID, CatalogID, and Legacy Persistent ID
/// Provides fast lookup and persistence for cross-platform song identification
public class SongIDMapper {
    public static let shared = SongIDMapper()
    
    private init() {
        LogWriter.log("SongIDMapper initialized with SQLite backend")
    }
    
    // MARK: - Public API
    
    /// Build the complete ID mapping database by scanning the entire library
    /// - Parameter forceRebuild: If true, rebuilds from scratch. If false, resumes from existing data.
    public func buildDatabase(forceRebuild: Bool = false) async throws {
        LogWriter.logEssential("🗄️ Building Song ID Mapping Database...")
        
        // Request MusicKit authorization
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            LogWriter.logEssential("❌ MusicKit authorization required")
            throw NSError(domain: "SongIDMapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "MusicKit not authorized"])
        }
        
        // Use SQLite database instead of JSON
        let db = SongIDDatabase.shared
        let stats = db.getStatistics()
        
        if forceRebuild && stats.total > 0 {
            LogWriter.logEssential("🔄 Force rebuild requested - clearing database...")
            _ = db.clearAll()
        } else if stats.total > 0 {
            LogWriter.logEssential("📂 Found existing database with \(stats.total) records")
            LogWriter.logEssential("🔄 Resuming from last checkpoint...")
        }
        
        // Fetch all songs from library
        var allSongs: [Song] = []
        var offset = 0
        let batchSize = 100
        
        LogWriter.logNormal("📊 Fetching songs from library...")
        
        while true {
            var songsRequest = MusicLibraryRequest<Song>()
            songsRequest.limit = batchSize
            songsRequest.offset = offset
            
            let songsResponse = try await songsRequest.response()
            
            if songsResponse.items.isEmpty {
                break
            }
            
            allSongs.append(contentsOf: songsResponse.items)
            offset += batchSize
            
            LogWriter.logNormal("   📥 Retrieved \(allSongs.count) songs so far...")
            
            // Safety check
            if allSongs.count > 50000 {
                LogWriter.logEssential("⚠️ Reached 50,000 songs limit")
                break
            }
        }
        
        LogWriter.logEssential("✅ Total songs retrieved: \(allSongs.count)")
        
        // Build mappings (skip already processed songs unless force rebuild)
        LogWriter.logEssential("🔍 Building ID mappings...")
        let startTime = Date()
        var processedCount = 0
        var skippedCount = 0
        var batchRecords: [SongIDDatabase.SongRecord] = []
        
        for (index, song) in allSongs.enumerated() {
            let musicItemID = song.id.rawValue
            
            // Skip if already processed (unless force rebuild)
            if !forceRebuild && db.exists(musicItemID) {
                skippedCount += 1
                if index % 100 == 0 && index > 0 && skippedCount > 0 {
                    LogWriter.logNormal("   Skipped \(skippedCount) already processed songs...")
                }
                continue
            }
            
            // Progress logging with percentage
            if processedCount % 100 == 0 && processedCount > 0 {
                let totalToProcess = allSongs.count - (forceRebuild ? 0 : skippedCount)
                let progress = Double(processedCount) / Double(totalToProcess) * 100
                let elapsed = Date().timeIntervalSince(startTime)
                let estimatedTotal = (elapsed / Double(processedCount)) * Double(totalToProcess)
                let remaining = estimatedTotal - elapsed
                let remainingMinutes = Int(remaining / 60)
                
                LogWriter.logNormal("   Processing \(processedCount)/\(totalToProcess) (\(String(format: "%.1f", progress))%) - ~\(remainingMinutes) min remaining...")
            }
            
            let catalogID = getCatalogID(for: song)
            let legacyID = await getLegacyPersistentID(for: song)
            
            let record = SongIDDatabase.SongRecord(
                musicItemID: musicItemID,
                catalogID: catalogID,
                legacyPersistentID: legacyID,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle
            )
            
            batchRecords.append(record)
            processedCount += 1
            
            // Batch insert every 100 songs for better performance
            if batchRecords.count >= 100 {
                _ = db.upsertBatch(batchRecords)
                batchRecords.removeAll()
                LogWriter.logNormal("   💾 Saved batch to database")
            }
        }
        
        // Save any remaining records
        if !batchRecords.isEmpty {
            _ = db.upsertBatch(batchRecords)
        }
        
        // Update in-memory cache and save JSON for backwards compatibility
        let finalStats = db.getStatistics()
        
        if !forceRebuild && skippedCount > 0 {
            LogWriter.logEssential("✅ Database updated: \(processedCount) new records added, \(skippedCount) already existed")
        } else {
            LogWriter.logEssential("✅ Database built successfully: \(finalStats.total) records created")
        }
        LogWriter.logEssential("   📊 Complete: \(finalStats.complete), Healthy: \(finalStats.healthy)")
        LogWriter.logEssential("   💾 Saved to SQLite database")
    }
    
    /// Lookup song by MusicItemID
    public func lookupByMusicItemID(_ id: String) -> SongIDDatabase.SongRecord? {
        return SongIDDatabase.shared.lookupByMusicItemID(id)
    }
    
    /// Lookup song by CatalogID
    public func lookupByCatalogID(_ id: String) -> SongIDDatabase.SongRecord? {
        return SongIDDatabase.shared.lookupByCatalogID(id)
    }
    
    /// Lookup song by Legacy Persistent ID
    public func lookupByLegacyID(_ id: String) -> SongIDDatabase.SongRecord? {
        return SongIDDatabase.shared.lookupByLegacyID(id)
    }
    
    /// Get database statistics
    public func getStatistics() -> (totalMappings: Int, complete: Int, healthy: Int, withCatalogID: Int, withLegacyID: Int, lastUpdated: Date?) {
        let stats = SongIDDatabase.shared.getStatistics()
        // TODO: Track last updated time separately
        return (stats.total, stats.complete, stats.healthy, stats.withCatalog, stats.withLegacy, nil)
    }
    
    // MARK: - Private Helpers
    
    /// Get catalog ID for a song (if available)
    private func getCatalogID(for song: Song) -> String? {
        // For Apple Music catalog songs, check if they have playParameters
        // This indicates it's a catalog song that can be played via Apple Music
        
        // If song has playParameters, it's a catalog song
        guard song.playParameters != nil else {
            // No play parameters = local/imported song only
            return nil
        }
        
        // For catalog songs, the MusicItemID itself can serve as the catalog ID
        // MusicKit uses the same ID for both in most cases
        let rawID = song.id.rawValue
        
        // Check if it's a numeric ID (pure catalog format)
        if rawID.allSatisfy({ $0.isNumber }) {
            return rawID
        }
        
        // For i.XXXXX format IDs, these are still universal catalog IDs
        // We can return the MusicItemID as it works for catalog lookups
        if rawID.hasPrefix("i.") {
            return rawID
        }
        
        return nil
    }
    
    /// Get legacy persistent ID using AppleScript
    private func getLegacyPersistentID(for song: Song) async -> String? {
        // Use AppleScript to find the track by metadata and get its persistent ID
        let title = song.title
        guard !title.isEmpty else { return nil }
        
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let artist = song.artistName
        let escapedArtist = artist.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        tell application "Music"
            try
                set matchingTracks to (every track of library playlist 1 whose name is "\(escapedTitle)" and artist is "\(escapedArtist)")
                if (count of matchingTracks) > 0 then
                    set theTrack to item 1 of matchingTracks
                    return persistent ID of theTrack
                else
                    return ""
                end if
            on error
                return ""
            end try
        end tell
        """
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", script]
                
                let pipe = Pipe()
                task.standardOutput = pipe
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !output.isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
