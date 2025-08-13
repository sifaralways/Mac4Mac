#!/usr/bin/env swift

import Foundation

// Copy of the LogWriter struct for testing
struct LogWriter {
    enum LogLevel: Int, CaseIterable {
        case essential = 0  
        case normal = 1     
        case debug = 2      
        
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
    
    static var currentLogLevel: LogLevel = .debug
    static var maxLogFiles: Int = 30
    
    static func log(_ message: String, level: LogLevel = .normal) {
        guard level.rawValue <= currentLogLevel.rawValue else { return }
        
        createLogDirectoryIfNeeded()
        cleanupOldLogFiles()
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(level.prefix) \(message)\n"
        let logFile = currentLogFile

        do {
            if FileManager.default.fileExists(atPath: logFile.path) {
                let handle = try FileHandle(forWritingTo: logFile)
                handle.seekToEndOfFile()
                if let data = fullMessage.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try fullMessage.write(to: logFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("❌ Failed to write to log file: \(error.localizedDescription)")
        }

        print(fullMessage, terminator: "")
    }
    
    static func logEssential(_ message: String) {
        log(message, level: .essential)
    }
    
    static func logNormal(_ message: String) {
        log(message, level: .normal)
    }
    
    static func logDebug(_ message: String) {
        log(message, level: .debug)
    }
    
    private static func createLogDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: logDirectory, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
        } catch {
            print("❌ Failed to create log directory: \(error.localizedDescription)")
        }
    }
    
    private static func cleanupOldLogFiles() {
        do {
            let fileManager = FileManager.default
            
            let logFiles = try fileManager.contentsOfDirectory(at: logDirectory, 
                                                             includingPropertiesForKeys: [.creationDateKey], 
                                                             options: [.skipsHiddenFiles])
                .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("MAC4MAC_") }
                .sorted { file1, file2 in
                    let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
                }
            
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
}

// Test the logging system
print("🧪 Testing MAC4MAC Daily Log Rotation System")
print("Log directory: \(LogWriter.logDirectory.path)")
print("Current log file: \(LogWriter.currentLogFile.lastPathComponent)")
print("")

// Test different log levels
LogWriter.logEssential("Essential: App launched successfully")
LogWriter.logNormal("Normal: Audio device detected")
LogWriter.logDebug("Debug: Detailed system information")

// Show available log files
let logFiles = LogWriter.getAvailableLogFiles()
print("\n📁 Available log files:")
for file in logFiles {
    print("  - \(file.lastPathComponent)")
}

print("\n✅ Logging test completed! Check the log directory for the new files.")
