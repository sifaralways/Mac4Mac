import Foundation
import AppKit

class TrackChangeMonitor {
    var lastTrackID: String?
    private var timer: Timer?
    private var artworkCache: [String: Data] = [:]
    private var trackInfoCache: [String: CachedTrackInfo] = [:]
    
    // Track state for each track ID to prevent duplicate callbacks
    private var trackStates: [String: TrackState] = [:]
    
    // Cleanup counter for periodic cache maintenance
    private var checkCounter: Int = 0
    private let cleanupInterval: Int = 30 // Clean every 30 checks (30 seconds)
    
    // Cache limits
    private let maxArtworkCacheSize: Int = 50 // Keep last 50 artworks (reasonable for typical session)
    
    struct TrackState {
        var hasTrackInfo: Bool = false
        var hasArtwork: Bool = false
        var hasSentInitialCallback: Bool = false
        var hasSentFullCallback: Bool = false
    }
    
    struct TrackInfo {
        let name: String
        let artist: String
        let album: String
        let persistentID: String
        let artworkData: Data?
    }
    
    struct CachedTrackInfo {
        let name: String
        let artist: String
        let album: String
        let timestamp: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5 minutes cache
        }
    }

    var onTrackChange: ((TrackInfo) -> Void)?

    func startMonitoring() {
        LogWriter.logEssential("Track change monitoring started")
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkForTrackChange()
        }
    }
    
    private func checkForTrackChange() {
        // Periodic cache cleanup to prevent unbounded growth
        checkCounter += 1
        if checkCounter >= cleanupInterval {
            cleanupExpiredCaches()
            checkCounter = 0
        }
        
        // STEP 1: Quick check for track ID change (lightweight AppleScript)
        let quickCheckScript = """
        tell application "Music"
            if it is running then
                try
                    if exists current track then
                        return persistent ID of current track
                    else
                        return "NO_TRACK"
                    end if
                on error errMsg
                    return "ERROR"
                end try
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", quickCheckScript]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty && !output.hasPrefix("ERROR") && output != "NOT_RUNNING" && output != "NO_TRACK" else {
            return
        }

        let currentTrackID = output
        
        // Check if track actually changed
        guard self.lastTrackID != currentTrackID else {
            return // Same track, no action needed
        }
        
        LogWriter.logEssential("Track change detected: \(currentTrackID)")
        
        // Clear state for the previous track to allow replays
        if let previousTrackID = self.lastTrackID {
            if trackStates[previousTrackID] != nil {
                trackStates[previousTrackID] = nil
                LogWriter.logEssential("🧹 CLEANUP: Cleared state for previous track \(previousTrackID.suffix(8))")
            }
        }
        
        // Log immediate track separator for clear visual separation
        LogWriter.logTrackChangeDetected(trackID: currentTrackID)
        
        LogWriter.logOperationStart("3-Phase Track Processing")
        self.lastTrackID = currentTrackID

        // STEP 2: PRIORITY 1 - Immediate sample rate sync (CRITICAL PATH)
        LogWriter.logOperationStart("Sample Rate Sync", phase: "P1")
        self.handleSampleRateSync(for: currentTrackID)
        
        // STEP 3: PRIORITY 2 - Fetch track info (async, for remote app)
        LogWriter.logOperationStart("Track Info Fetch", phase: "P2")
        self.handleTrackInfoFetch(for: currentTrackID)
        
        // STEP 4: PRIORITY 3 - Fetch artwork (async, heavy operation)
        LogWriter.logOperationStart("Artwork Fetch", phase: "P3")
        self.handleArtworkFetch(for: currentTrackID)
    }
    
    // PRIORITY 1: Critical path - sample rate sync (IMMEDIATE)
    private func handleSampleRateSync(for trackID: String) {
        // Initialize track state
        if trackStates[trackID] == nil {
            trackStates[trackID] = TrackState()
            LogWriter.logEssential("🔧 INIT: Created new track state for \(trackID.suffix(8))")
        }
        
        // Only send initial callback once per track
        guard let state = trackStates[trackID], !state.hasSentInitialCallback else {
            LogWriter.logEssential("⏭️ SKIP P1: Sample rate sync already sent for track \(trackID.suffix(8)) (hasSentInitialCallback=\(trackStates[trackID]?.hasSentInitialCallback ?? false))")
            return
        }
        
        // Use cached track name if available, otherwise use generic name
        let trackName = trackInfoCache[trackID]?.name ?? "Current Track"
        
        LogWriter.logEssential("✅ P1 CALLBACK: Firing minimal callback for track \(trackID.suffix(8))")
        
        // IMMEDIATE: Trigger callback for sample rate sync (don't wait for detection)
        let minimalTrackInfo = TrackInfo(
            name: trackName,
            artist: "Loading...",
            album: "Loading...",
            persistentID: trackID,
            artworkData: nil
        )
        
        // Mark as sent and call immediately - this triggers sample rate detection in AppDelegate
        trackStates[trackID]?.hasSentInitialCallback = true
        LogWriter.logEssential("🏁 P1 STATE: Marked hasSentInitialCallback=true for \(trackID.suffix(8))")
        DispatchQueue.main.async { [weak self] in
            self?.onTrackChange?(minimalTrackInfo)
        }
    }
    
    // PRIORITY 2: Track info for remote app (async)
    private func handleTrackInfoFetch(for trackID: String) {
        LogWriter.logWithSession("Starting track info fetch", level: .normal, phase: "P2")
        
        // Check cache first
        if let cachedInfo = trackInfoCache[trackID], !cachedInfo.isExpired {
            LogWriter.logEssential("🗄️ P2 CACHE HIT: Using cached info for \(trackID.suffix(8)): \(cachedInfo.name)")
            LogWriter.logWithSession("Using cached track info", level: .debug, phase: "P2", status: "CACHE")
            updateWithCachedInfo(trackID: trackID, cachedInfo: cachedInfo)
            return
        }
        
        LogWriter.logEssential("📡 P2 CACHE MISS: Fetching track info for \(trackID.suffix(8))")
        DispatchQueue.global().async { [weak self] in
            self?.fetchTrackInfo(for: trackID)
        }
    }
    
    // PRIORITY 3: Artwork fetch (async, lowest priority)
    private func handleArtworkFetch(for trackID: String) {
        LogWriter.logWithSession("Starting artwork fetch", level: .normal, phase: "P3")
        
        // Check artwork cache first
        if let cachedArtwork = artworkCache[trackID] {
            LogWriter.logWithSession("Using cached artwork (\(cachedArtwork.count) bytes)", level: .debug, phase: "P3", status: "CACHE")
            // Mark artwork as ready for this track
            if trackStates[trackID] == nil {
                trackStates[trackID] = TrackState()
            }
            trackStates[trackID]?.hasArtwork = true
            return // Artwork already cached
        }
        
        DispatchQueue.global().async { [weak self] in
            self?.fetchArtwork(for: trackID)
        }
    }
    
    private func fetchTrackInfo(for trackID: String) {
        let script = """
        tell application "Music"
            if it is running then
                try
                    if exists current track then
                        set t to current track
                        if persistent ID of t is "\(trackID)" then
                            set trackName to name of t
                            set artistName to artist of t
                            set albumName to album of t
                            return trackName & "||" & artistName & "||" & albumName
                        else
                            return "TRACK_CHANGED"
                        end if
                    else
                        return "NO_TRACK"
                    end if
                on error errMsg
                    return "ERROR"
                end try
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty && !output.hasPrefix("ERROR") && output != "NOT_RUNNING" && output != "NO_TRACK" && output != "TRACK_CHANGED" else {
            LogWriter.logDebug("Failed to fetch track info or track changed during fetch")
            return
        }

        let components = output.components(separatedBy: "||")
        guard components.count == 3 else {
            LogWriter.logDebug("Invalid track info format")
            return
        }

        let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
        
        let finalName = name.isEmpty ? "Unknown Track" : name
        let finalArtist = artist.isEmpty ? "Unknown Artist" : artist
        let finalAlbum = album.isEmpty ? "Unknown Album" : album
        
        // Cache the track info
        let cachedInfo = CachedTrackInfo(
            name: finalName,
            artist: finalArtist,
            album: finalAlbum,
            timestamp: Date()
        )
        trackInfoCache[trackID] = cachedInfo
        
        // Mark track info as ready
        if trackStates[trackID] == nil {
            trackStates[trackID] = TrackState()
        }
        trackStates[trackID]?.hasTrackInfo = true
        
        LogWriter.logNormal("Track info fetched: \(finalName) by \(finalArtist)")
        LogWriter.logNormal("📊 PARALLEL: Track info fetch completed")
        
        // Check if we can send full update
        DispatchQueue.main.async { [weak self] in
            self?.checkAndSendFullUpdate(for: trackID)
        }
    }
    
    private func fetchArtwork(for trackID: String) {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("mac4mac_artwork_\(UUID().uuidString).jpg")
        
        let script = """
        tell application "Music"
            try
                if exists current track then
                    set t to current track
                    if persistent ID of t is "\(trackID)" then
                        set artworkCount to count of artworks of t
                        
                        if artworkCount > 0 then
                            set artworkData to data of artwork 1 of t
                            
                            set fileRef to open for access POSIX file "\(tempFile.path)" with write permission
                            write artworkData to fileRef
                            close access fileRef
                            
                            return "SUCCESS"
                        else
                            return "NO_ARTWORK"
                        end if
                    else
                        return "TRACK_CHANGED"
                    end if
                else
                    return "NO_TRACK"
                end if
            on error errMsg
                try
                    close access fileRef
                end try
                return "ERROR"
            end try
        end tell
        """

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) {
                
                if output == "SUCCESS" {
                    do {
                        let artworkData = try Data(contentsOf: tempFile)
                        
                        // Verify it's valid image data
                        guard artworkData.count > 8 else {
                            LogWriter.logDebug("Artwork data too small")
                            try? FileManager.default.removeItem(at: tempFile)
                            return
                        }
                        
                        // Cache the artwork
                        artworkCache[trackID] = artworkData
                        
                        // Mark artwork as ready
                        if trackStates[trackID] == nil {
                            trackStates[trackID] = TrackState()
                        }
                        trackStates[trackID]?.hasArtwork = true
                        
                        LogWriter.logNormal("Artwork cached for track (\(artworkData.count) bytes)")
                        LogWriter.logNormal("🖼️ PARALLEL: Artwork fetch completed")
                        
                        // Clean up temp file
                        try? FileManager.default.removeItem(at: tempFile)
                        
                        // 🖼️ Send artwork update to remote clients
                        DispatchQueue.main.async { [weak self] in
                            self?.sendArtworkUpdate(for: trackID, artworkData: artworkData)
                        }
                    } catch {
                        LogWriter.logDebug("Failed to read artwork file: \(error.localizedDescription)")
                        try? FileManager.default.removeItem(at: tempFile)
                    }
                } else {
                    LogWriter.logDebug("No artwork available: \(output)")
                    // Mark artwork as "ready" (even though it's nil) so full update can proceed
                    if trackStates[trackID] == nil {
                        trackStates[trackID] = TrackState()
                    }
                    trackStates[trackID]?.hasArtwork = true
                    
                    LogWriter.logDebug("🖼️ No artwork available for this track")
                    // Don't send artwork update if there's no artwork
                }
            }
        } catch {
            LogWriter.logDebug("Failed to execute artwork script: \(error.localizedDescription)")
            // Mark artwork as "ready" (failed) so full update can proceed
            if trackStates[trackID] == nil {
                trackStates[trackID] = TrackState()
            }
            trackStates[trackID]?.hasArtwork = true
            
            LogWriter.logDebug("🖼️ Artwork fetch failed for this track")
            // Don't send artwork update if artwork fetch failed
        }
    }
    
    // Smart callback system - only send full update once when track info is ready
    private func checkAndSendFullUpdate(for trackID: String) {
        guard let state = trackStates[trackID] else { return }
        
        // Only send full update once, and only when we have track info
        if state.hasTrackInfo && !state.hasSentFullCallback {
            trackStates[trackID]?.hasSentFullCallback = true
            
            guard let cachedInfo = trackInfoCache[trackID] else { return }
            let artworkData = artworkCache[trackID] // May be nil, that's OK
            
            let trackInfo = TrackInfo(
                name: cachedInfo.name,
                artist: cachedInfo.artist,
                album: cachedInfo.album,
                persistentID: trackID,
                artworkData: artworkData
            )
            
            LogWriter.logEssential("📱 PHASE 1 READY: \(cachedInfo.name) by \(cachedInfo.artist)")
            onTrackChange?(trackInfo)
        }
    }
    
    // Send artwork update without triggering full track processing
    private func sendArtworkUpdate(for trackID: String, artworkData: Data) {
        guard let cachedInfo = trackInfoCache[trackID] else {
            LogWriter.logDebug("No track info available for artwork update")
            return
        }
        
        // Only send artwork update if we already sent the initial track info
        guard let state = trackStates[trackID], state.hasSentFullCallback else {
            LogWriter.logDebug("Track info not sent yet, artwork will be included in full update")
            return
        }
        
        let trackInfo = TrackInfo(
            name: cachedInfo.name,
            artist: cachedInfo.artist,
            album: cachedInfo.album,
            persistentID: trackID,
            artworkData: artworkData
        )
        
        LogWriter.logEssential("🖼️ ARTWORK UPDATE: Sending artwork for \(cachedInfo.name)")
        onTrackChange?(trackInfo)
    }
    
    private func updateWithCachedInfo(trackID: String, cachedInfo: CachedTrackInfo) {
        // For cached info, send immediate full update
        if trackStates[trackID] == nil {
            trackStates[trackID] = TrackState()
        }
        
        guard let state = trackStates[trackID], !state.hasSentFullCallback else {
            return // Already sent full update
        }
        
        trackStates[trackID]?.hasTrackInfo = true
        trackStates[trackID]?.hasSentFullCallback = true
        
        let artworkData = artworkCache[trackID]
        
        let trackInfo = TrackInfo(
            name: cachedInfo.name,
            artist: cachedInfo.artist,
            album: cachedInfo.album,
            persistentID: trackID,
            artworkData: artworkData
        )
        
        LogWriter.logEssential("📱 PHASE 1 CACHED: \(cachedInfo.name) by \(cachedInfo.artist)")
        DispatchQueue.main.async { [weak self] in
            self?.onTrackChange?(trackInfo)
        }
    }
    
    // MARK: - Cache Management
    
    /// Removes expired entries from caches to prevent unbounded growth
    private func cleanupExpiredCaches() {
        let beforeTrackInfoCount = trackInfoCache.count
        let beforeArtworkCount = artworkCache.count
        
        // Remove expired track info entries (5-minute TTL)
        trackInfoCache = trackInfoCache.filter { !$0.value.isExpired }
        
        // Remove track states for tracks no longer in cache
        let validTrackIDs = Set(trackInfoCache.keys).union(Set([lastTrackID].compactMap { $0 }))
        trackStates = trackStates.filter { validTrackIDs.contains($0.key) }
        
        // Artwork cleanup strategy: Only remove if we exceed size limit
        // Keep artwork for tracks with valid track info + current track (more lenient than track info TTL)
        if artworkCache.count > maxArtworkCacheSize {
            // Remove artwork for expired tracks first
            let artworkKeysToKeep = validTrackIDs
            artworkCache = artworkCache.filter { artworkKeysToKeep.contains($0.key) }
            
            // If still over limit after removing expired, remove oldest entries
            // (This is a simple cleanup; proper LRU would require tracking access timestamps)
            if artworkCache.count > maxArtworkCacheSize {
                let excessCount = artworkCache.count - maxArtworkCacheSize
                let keysToRemove = Array(artworkCache.keys.prefix(excessCount))
                keysToRemove.forEach { artworkCache.removeValue(forKey: $0) }
                LogWriter.logNormal("🧹 Artwork cache exceeded limit, removed \(excessCount) oldest entries")
            }
        }
        
        let removedTrackInfo = beforeTrackInfoCount - trackInfoCache.count
        let removedArtwork = beforeArtworkCount - artworkCache.count
        
        if removedTrackInfo > 0 || removedArtwork > 0 {
            LogWriter.logNormal("🧹 Cache cleanup: Removed \(removedTrackInfo) track info, \(removedArtwork) artwork entries (artwork cache: \(artworkCache.count)/\(maxArtworkCacheSize))")
        }
    }
    
    func stopMonitoring() {
        LogWriter.logEssential("Track change monitoring stopped")
        timer?.invalidate()
        timer = nil
        artworkCache.removeAll()
        trackInfoCache.removeAll()
        trackStates.removeAll()
    }
    
    func clearCaches() {
        artworkCache.removeAll()
        trackInfoCache.removeAll()
        trackStates.removeAll()
        LogWriter.logNormal("Track and artwork caches cleared")
    }
    
    func forceTrackUpdate() {
        LogWriter.logNormal("Forcing track update check")
        lastTrackID = nil
        trackStates.removeAll()
    }
}
