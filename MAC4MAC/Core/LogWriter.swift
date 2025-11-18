import Foundation

struct LogWriter {
    enum LogLevel: Int, CaseIterable {
        case essential = 0  // Only critical logs (track changes, sample rate, errors)
        case normal = 1     // Essential + important events
        case debug = 2      // All logs (for debugging)
        
        var prefix: String {
            switch self {
            case .essential: return "🎵"
            case .normal: return "ℹ️"
            case .debug: return "🔍"
            }
        }
    }
    
    // Log directory for daily rotated files
    static let logDirectory: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("MAC4MAC_Logs")
    }()
    
    // Get current log file URL with date stamp
    static var currentLogFile: URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return logDirectory.appendingPathComponent("MAC4MAC_\(dateString).log")
    }
    
    // Set to .essential for production, .debug for development
    static var currentLogLevel: LogLevel = .essential
    
    // Maximum number of log files to keep (default: 30 days)
    static var maxLogFiles: Int = 30
    
    static func log(_ message: String, level: LogLevel = .normal) {
        // Only log if message level is at or above current level
        guard level.rawValue <= currentLogLevel.rawValue else { return }
        
        // Ensure log directory exists
        createLogDirectoryIfNeeded()
        
        // Clean up old log files periodically
        cleanupOldLogFiles()
        
        let timestamp = formatTimestamp(Date())
        let levelTag = formatLevelTag(level)
        let fullMessage = "\(timestamp) | \(levelTag) | \(message)\n"
        let logFile = currentLogFile

        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                let handle = try FileHandle(forWritingTo: logFile)
                handle.seekToEndOfFile()
                if let data = fullMessage.data(using: String.Encoding.utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try fullMessage.write(to: logFile, atomically: true, encoding: String.Encoding.utf8)
            }
        } catch {
            print("❌ Failed to write to log file: \(error.localizedDescription)")
        }

        print(fullMessage, terminator: "")
    }
    
    // Convenience methods for different log levels
    static func logEssential(_ message: String) {
        log(message, level: .essential)
    }
    
    static func logNormal(_ message: String) {
        log(message, level: .normal)
    }
    
    static func logDebug(_ message: String) {
        log(message, level: .debug)
    }
    
    // MARK: - Specialized Logging Methods
    
    /// Logs a clear track separator with track information and sample rate
    static func logTrackSeparator(trackName: String, artist: String, album: String, sampleRate: Double) {
        let separator = "═══════════════════════════════════════════════════════════════════════════════════"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm:ss a"
        let timeString = timeFormatter.string(from: Date())
        
        // Format sample rate in kHz
        let sampleRateKHz = String(format: "%.0f", sampleRate / 1000.0)
        
        let trackInfo = "🎵 NEW TRACK | \(trackName) - \(artist) | \(album) | \(sampleRateKHz) kHz | \(timeString)"
        
        // Write separator and track info as a special formatted entry
        logRaw("\n\(separator)")
        logRaw(trackInfo)
        logRaw(separator)
    }
    
    /// Logs an immediate track change separator with just the track ID
    static func logTrackChangeDetected(trackID: String) {
        let separator = "═══════════════════════════════════════════════════════════════════════════════════"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm:ss a"
        let timeString = timeFormatter.string(from: Date())
        
        // Generate session ID for this track change sequence
        let sessionID = String(trackID.suffix(8))
        
        let trackInfo = "🎵 NEW TRACK DETECTED | ID: \(trackID) | Session: \(sessionID) | \(timeString)"
        
        // Store session ID for correlation
        currentSessionID = sessionID
        sessionStartTime = Date()
        
        // Write separator and track info as a special formatted entry
        logRaw("\n\(separator)")
        logRaw(trackInfo)
        logRaw(separator)
    }
    
    // Session tracking for correlation
    private static var currentSessionID: String = ""
    private static var sessionStartTime: Date = Date()
    
    /// Logs with session correlation and timing
    static func logWithSession(_ message: String, level: LogLevel = .normal, phase: String? = nil, status: String? = nil) {
        let elapsed = String(format: "%.0f", Date().timeIntervalSince(sessionStartTime) * 1000)
        let sessionTag = currentSessionID.isEmpty ? "" : "[\(currentSessionID)]"
        let phaseTag = phase != nil ? "[\(phase!)]" : ""
        let statusTag = status != nil ? "[\(status!)]" : ""
        let timingTag = "[\(elapsed)ms]"
        
        let enhancedMessage = "\(sessionTag)\(phaseTag)\(statusTag)\(timingTag) \(message)"
        log(enhancedMessage, level: level)
    }
    
    /// Logs operation start with timing
    static func logOperationStart(_ operation: String, phase: String? = nil) {
        logWithSession("🚀 START: \(operation)", level: .essential, phase: phase, status: "INIT")
    }
    
    /// Logs operation success with timing
    static func logOperationSuccess(_ operation: String, phase: String? = nil, details: String? = nil) {
        let message = details != nil ? "\(operation) - \(details!)" : operation
        logWithSession("✅ SUCCESS: \(message)", level: .essential, phase: phase, status: "OK")
    }
    
    /// Logs operation failure with timing
    static func logOperationFailure(_ operation: String, phase: String? = nil, error: String) {
        logWithSession("❌ FAILED: \(operation) - \(error)", level: .essential, phase: phase, status: "ERR")
    }
    
    /// Logs operation timeout with timing
    static func logOperationTimeout(_ operation: String, phase: String? = nil, timeoutMs: Int) {
        logWithSession("⏰ TIMEOUT: \(operation) after \(timeoutMs)ms", level: .essential, phase: phase, status: "TMO")
    }
    
    /// Logs state transition
    static func logStateChange(from: String, to: String, reason: String? = nil) {
        let reasonText = reason != nil ? " - \(reason!)" : ""
        logWithSession("🔄 STATE: \(from) → \(to)\(reasonText)", level: .normal, status: "STATE")
    }
    
    /// Logs sample rate changes with directional indicators
    static func logSampleRateChange(from oldRate: Double, to newRate: Double, succeeded: Bool) {
        let oldKHz = String(format: "%.1f", oldRate / 1000.0)
        let newKHz = String(format: "%.1f", newRate / 1000.0)
        
        let direction: String
        let indicator: String
        
        if oldRate < newRate {
            direction = "UP"
            indicator = "⬆️"
        } else if oldRate > newRate {
            direction = "DOWN" 
            indicator = "⬇️"
        } else {
            direction = "SAME"
            indicator = "➡️"
        }
        
        let status = succeeded ? "✅ SUCCESS" : "❌ FAILED"
        let message = "🎚️ \(indicator) SAMPLE RATE \(direction): \(oldKHz) kHz → \(newKHz) kHz | \(status)"
        
        logEssential(message)
    }
    
    // MARK: - MusicKit Logging
    
    static func logMusicKit(_ message: String, level: LogLevel = .debug) {
        let prefixedMessage = "🎵 MUSICKIT: \(message)"
        log(prefixedMessage, level: level)
    }
    
    static func logMusicKitAuth(_ status: String) {
        logMusicKit("Authorization status: \(status)", level: .essential)
    }
    
    static func logMusicKitTrack(_ trackInfo: String) {
        logMusicKit("Track: \(trackInfo)", level: .essential)
    }
    
    static func logMusicKitError(_ error: String) {
        logMusicKit("❌ ERROR: \(error)", level: .essential)
    }
    
    /// Logs raw message without timestamp formatting (for separators)
    private static func logRaw(_ message: String) {
        let logFile = currentLogFile
        let fullMessage = "\(message)\n"
        
        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                let handle = try FileHandle(forWritingTo: logFile)
                handle.seekToEndOfFile()
                if let data = fullMessage.data(using: String.Encoding.utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try fullMessage.write(to: logFile, atomically: true, encoding: String.Encoding.utf8)
            }
        } catch {
            print("❌ Failed to write to log file: \(error.localizedDescription)")
        }
        
        print(fullMessage, terminator: "")
    }
    
    // MARK: - Helper Methods
    
    /// Formats timestamp in a more readable format
    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
    
    /// Formats the log level tag in a compact format
    private static func formatLevelTag(_ level: LogLevel) -> String {
        switch level {
        case .essential: return "🎵 ESS"
        case .normal: return "ℹ️ NOR"
        case .debug: return "🔍 DBG"
        }
    }
    
    /// Creates the log directory if it doesn't exist
    private static func createLogDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: logDirectory, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
        } catch {
            print("❌ Failed to create log directory: \(error.localizedDescription)")
        }
    }
    
    /// Removes old log files to prevent unlimited accumulation
    private static func cleanupOldLogFiles() {
        do {
            let fileManager = FileManager.default
            
            // Get all log files in the directory
            let logFiles = try fileManager.contentsOfDirectory(at: logDirectory, 
                                                             includingPropertiesForKeys: [.creationDateKey], 
                                                             options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("MAC4MAC_") }
                .sorted { file1, file2 in
                    let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }
            
            // Remove excess files (keep only the most recent maxLogFiles)
            if logFiles.count > maxLogFiles {
                let filesToRemove = logFiles.dropFirst(maxLogFiles)
                for file in filesToRemove {
                    try fileManager.removeItem(at: file)
                    print("🗑️ Removed old log file: \(file.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Failed to cleanup old log files: \(error.localizedDescription)")
        }
    }
    
    /// Gets all available log files sorted by date (newest first)
    static func getAvailableLogFiles() -> [URL] {
        do {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: logDirectory.path) else { return [] }
            
            return try fileManager.contentsOfDirectory(at: logDirectory, 
                                                     includingPropertiesForKeys: [.creationDateKey], 
                                                     options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("MAC4MAC_") }
                .sorted { file1, file2 in
                    let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }
        } catch {
            print("❌ Failed to get available log files: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Migrates the old single log file to the new date-stamped system (one-time operation)
    static func migrateOldLogFileIfNeeded() {
        let oldLogFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MAC4MAC.log")
        
        guard FileManager.default.fileExists(atPath: oldLogFile.path) else { return }
        
        do {
            // Create log directory
            createLogDirectoryIfNeeded()
            
            // Get file creation date for naming
            let attributes = try FileManager.default.attributesOfItem(atPath: oldLogFile.path)
            let creationDate = attributes[.creationDate] as? Date ?? Date()
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: creationDate)
            
            let migratedLogFile = logDirectory.appendingPathComponent("MAC4MAC_\(dateString)_migrated.log")
            
            // Move the old log file to the new location
            try FileManager.default.moveItem(at: oldLogFile, to: migratedLogFile)
            
            print("✅ Migrated old log file to: \(migratedLogFile.lastPathComponent)")
            
            // Log the migration
            logEssential("Log file migration completed successfully from single file to daily rotation system")
            
        } catch {
            print("❌ Failed to migrate old log file: \(error.localizedDescription)")
            // If migration fails, we'll just start fresh with the new system
        }
    }
}
