import Foundation

struct LogWriter {
    static let logFile: URL = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("MAC4MAC.log")
    }()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)\n"

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
}
