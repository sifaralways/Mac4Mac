import Foundation
import AppKit

class TrackChangeMonitor {
    private var lastTrackID: String?
    private var timer: Timer?

    struct TrackInfo {
        let name: String
        let artist: String
        let album: String
        let persistentID: String
        let artworkData: Data?
    }

    var onTrackChange: ((TrackInfo) -> Void)?

    func startMonitoring() {
        LogWriter.log("🎯 TrackChangeMonitor: Starting monitoring...")
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            LogWriter.log("🔄 TrackChangeMonitor: Timer tick - checking for track changes...")
            
            let script = """
            tell application "Music"
                if it is running then
                    try
                        delay 0.2
                        if exists current track then
                            set t to current track
                            set trackName to name of t
                            set artistName to artist of t
                            set albumName to album of t
                            if persistent ID of t is not missing value then
                                set trackID to persistent ID of t
                            else
                                set trackID to "MISSING_ID"
                            end if
                            return trackName & "||" & artistName & "||" & albumName & "||" & trackID
                        else
                            return "NO_TRACK"
                        end if
                    on error errMsg
                        return "ERROR: " & errMsg
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
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) {
                
                LogWriter.log("🎵 TrackChangeMonitor: AppleScript output: '\(output)'")
                
                if !output.isEmpty && !output.hasPrefix("ERROR") && output != "NOT_RUNNING" && output != "NO_TRACK" {
                    let components = output.components(separatedBy: "||")
                    LogWriter.log("📊 TrackChangeMonitor: Parsed \(components.count) components: \(components)")
                    
                    guard components.count == 4 else {
                        LogWriter.log("⚠️ TrackChangeMonitor: Unexpected component count, expected 4, got \(components.count)")
                        return
                    }

                    let name = components[0]
                    let artist = components[1]
                    let album = components[2]
                    let id = components[3]
                    
                    LogWriter.log("🎯 TrackChangeMonitor: Current track ID: '\(id)', Last ID: '\(self.lastTrackID ?? "nil")'")

                    if self.lastTrackID != id {
                        LogWriter.log("🔄 TrackChangeMonitor: Track changed detected!")
                        self.lastTrackID = id
                        
                        // Fetch artwork using the working method
                        LogWriter.log("🖼️ TrackChangeMonitor: Starting artwork fetch...")
                        self.fetchArtworkFixed(for: id, trackName: name) { artworkData in
                            let trackInfo = TrackInfo(
                                name: name,
                                artist: artist,
                                album: album,
                                persistentID: id,
                                artworkData: artworkData
                            )
                            
                            LogWriter.log("🎶 TrackChangeMonitor: Track info created - calling onTrackChange callback")
                            LogWriter.log("📋 TrackChangeMonitor: Track: \(name) by \(artist) from \(album)")
                            
                            if artworkData != nil {
                                LogWriter.log("🖼️ TrackChangeMonitor: Artwork fetched successfully (\(artworkData!.count) bytes)")
                            } else {
                                LogWriter.log("⚠️ TrackChangeMonitor: No artwork found for current track")
                            }
                            
                            // Call the callback
                            self.onTrackChange?(trackInfo)
                            LogWriter.log("✅ TrackChangeMonitor: onTrackChange callback completed")
                        }
                    } else {
                        // Uncomment this line if you want to see when tracks haven't changed
                        // LogWriter.log("➡️ TrackChangeMonitor: Same track, no change")
                    }
                } else {
                    LogWriter.log("⚠️ TrackChangeMonitor: Invalid output: '\(output)'")
                }
            } else {
                LogWriter.log("❌ TrackChangeMonitor: No output from AppleScript")
            }
        }
        
        LogWriter.log("✅ TrackChangeMonitor: Timer scheduled successfully")
    }

    private func fetchArtworkFixed(for persistentID: String, trackName: String, completion: @escaping (Data?) -> Void) {
        LogWriter.log("🖼️ fetchArtworkFixed: Starting for track '\(trackName)' with ID '\(persistentID)'")
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("mac4mac_artwork_\(UUID().uuidString).jpg")
        LogWriter.log("📁 fetchArtworkFixed: Temp file path: \(tempFile.path)")
        
        let script = """
        tell application "Music"
            try
                set t to some track of library playlist 1 whose persistent ID is "\(persistentID)"
                
                -- Use the working method: check count first
                if (count of artworks of t) > 0 then
                    set artworkData to data of artwork 1 of t
                    
                    -- Save to temp file (no length check needed)
                    set fileRef to open for access POSIX file "\(tempFile.path)" with write permission
                    write artworkData to fileRef
                    close access fileRef
                    
                    return "SUCCESS"
                else
                    return "NO_ARTWORK"
                end if
            on error errMsg
                try
                    close access fileRef
                end try
                return "ERROR:" & errMsg
            end try
        end tell
        """

        DispatchQueue.global().async {
            LogWriter.log("🔄 fetchArtworkFixed: Executing AppleScript on background thread...")
            
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) {
                    
                    LogWriter.log("🖼️ fetchArtworkFixed: AppleScript result: '\(output)'")
                    
                    if output == "SUCCESS" {
                        do {
                            let artworkData = try Data(contentsOf: tempFile)
                            LogWriter.log("✅ fetchArtworkFixed: Artwork loaded successfully: \(artworkData.count) bytes")
                            
                            // Verify it's a valid image
                            if artworkData.starts(with: [0xFF, 0xD8, 0xFF]) {
                                LogWriter.log("📸 fetchArtworkFixed: Confirmed JPEG format")
                            } else if artworkData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                                LogWriter.log("📸 fetchArtworkFixed: Confirmed PNG format")
                            } else {
                                LogWriter.log("❓ fetchArtworkFixed: Unknown format - first bytes: \(artworkData.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))")
                            }
                            
                            // Clean up temp file
                            try? FileManager.default.removeItem(at: tempFile)
                            LogWriter.log("🧹 fetchArtworkFixed: Temp file cleaned up")
                            
                            DispatchQueue.main.async {
                                LogWriter.log("📤 fetchArtworkFixed: Calling completion with artwork data")
                                completion(artworkData)
                            }
                        } catch {
                            LogWriter.log("❌ fetchArtworkFixed: Failed to read artwork file: \(error.localizedDescription)")
                            try? FileManager.default.removeItem(at: tempFile)
                            DispatchQueue.main.async {
                                LogWriter.log("📤 fetchArtworkFixed: Calling completion with nil (read error)")
                                completion(nil)
                            }
                        }
                    } else {
                        LogWriter.log("⚠️ fetchArtworkFixed: No artwork or error: \(output)")
                        DispatchQueue.main.async {
                            LogWriter.log("📤 fetchArtworkFixed: Calling completion with nil (no artwork)")
                            completion(nil)
                        }
                    }
                } else {
                    LogWriter.log("❌ fetchArtworkFixed: No output from artwork AppleScript")
                    DispatchQueue.main.async {
                        LogWriter.log("📤 fetchArtworkFixed: Calling completion with nil (no output)")
                        completion(nil)
                    }
                }
            } catch {
                LogWriter.log("❌ fetchArtworkFixed: Failed to execute artwork script: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    LogWriter.log("📤 fetchArtworkFixed: Calling completion with nil (execution error)")
                    completion(nil)
                }
            }
        }
    }

    func stopMonitoring() {
        LogWriter.log("🛑 TrackChangeMonitor: Stopping monitoring...")
        timer?.invalidate()
        timer = nil
        LogWriter.log("✅ TrackChangeMonitor: Monitoring stopped")
    }
}
