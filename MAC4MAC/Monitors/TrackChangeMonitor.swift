import Foundation
import AppKit

class TrackChangeMonitor {
    var lastTrackID: String?
    private var timer: Timer?
    private var artworkCache: [String: Data] = [:]
    private var trackInfoCache: [String: CachedTrackInfo] = [:]
    
    // Track state for each track ID to prevent duplicate callbacks
    private var trackStates: [String: TrackState] = [:]
    
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
        LogWriter.logEssential("🚀 STARTING PRIORITY SEQUENCE:")
        self.lastTrackID = currentTrackID
        
        // STEP 2: PRIORITY 1 - Immediate sample rate sync (CRITICAL PATH)
        LogWriter.logEssential("🚨 PRIORITY 1: Sample rate sync (CRITICAL)")
        self.handleSampleRateSync(for: currentTrackID)
        
        // STEP 3: PRIORITY 2 - Fetch track info (async, for remote app)
        LogWriter.logNormal("📊 PRIORITY 2: Track info (PARALLEL)")
        self.handleTrackInfoFetch(for: currentTrackID)
        
        // STEP 4: PRIORITY 3 - Fetch artwork (async, heavy operation)
        LogWriter.logNormal("🖼️ PRIORITY 3: Artwork (PARALLEL)")
        self.handleArtworkFetch(for: currentTrackID)
    }
    
    // PRIORITY 1: Critical path - sample rate sync (IMMEDIATE)
    private func handleSampleRateSync(for trackID: String) {
        // Initialize track state
        if trackStates[trackID] == nil {
            trackStates[trackID] = TrackState()
        }
        
        // Only send initial callback once per track
        guard let state = trackStates[trackID], !state.hasSentInitialCallback else {
            return
        }
        
        // Use cached track name if available, otherwise use generic name
        let trackName = trackInfoCache[trackID]?.name ?? "Current Track"
        
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
        DispatchQueue.main.async { [weak self] in
            self?.onTrackChange?(minimalTrackInfo)
        }
    }
    
    // PRIORITY 2: Track info for remote app (async)
    private func handleTrackInfoFetch(for trackID: String) {
        LogWriter.logNormal("📊 PARALLEL: Starting track info fetch")
        
        // Check cache first
        if let cachedInfo = trackInfoCache[trackID], !cachedInfo.isExpired {
            LogWriter.logDebug("Using cached track info for \(trackID)")
            updateWithCachedInfo(trackID: trackID, cachedInfo: cachedInfo)
            return
        }
        
        DispatchQueue.global().async { [weak self] in
            self?.fetchTrackInfo(for: trackID)
        }
    }
    
    // PRIORITY 3: Artwork fetch (async, lowest priority)
    private func handleArtworkFetch(for trackID: String) {
        LogWriter.logNormal("🖼️ PARALLEL: Starting artwork fetch")
        
        // Check artwork cache first
        if let cachedArtwork = artworkCache[trackID] {
            LogWriter.logDebug("Using cached artwork for \(trackID)")
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
