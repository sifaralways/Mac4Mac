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
    
    static let logFile: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("MAC4MAC.log")
    }()
    
    // Set to .essential for production, .debug for development
    static var currentLogLevel: LogLevel = .essential
    
    static func log(_ message: String, level: LogLevel = .normal) {
        // Only log if message level is at or above current level
        guard level.rawValue <= currentLogLevel.rawValue else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(level.prefix) \(message)\n"

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

        print(fullMessage)
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
}
