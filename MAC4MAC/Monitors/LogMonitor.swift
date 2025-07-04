import Foundation

class LogMonitor {
    static func fetchLatestSampleRate(completion: @escaping (Double, String) -> Void) {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "show",
            "--predicate",
            "eventMessage CONTAINS \"Created new AudioQueue for format:\"",
            "--style",
            "syslog",
            "--last",
            "10s"
        ]
        task.standardOutput = pipe

        let handle = pipe.fileHandleForReading
        task.terminationHandler = { _ in
            let data = handle.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n").reversed()
                for line in lines {
                    if let rate = parseSampleRate(from: line), let song = parseSongName(from: line) {
                        LogWriter.log("🧠 Matched sampleRate: \(rate), song: \(song)")
                        completion(rate, song)
                        return
                    }
                }
                LogWriter.log("⚠️ No sampleRate or song found in last 10s logs.")
            }
        }

        do {
            try task.run()
        } catch {
            LogWriter.log("❌ Failed to run log command: \(error.localizedDescription)")
        }
    }

    static func parseSampleRate(from log: String) -> Double? {
        let pattern = #"sampleRate:(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
           let range = Range(match.range(at: 1), in: log) {
            return Double(log[range])
        }
        return nil
    }

    static func parseSongName(from log: String) -> String? {
        let pattern = #"Queue->Player synchronization started - player:[^\]]* queueItems:\[<AVPlayerItem:[^>]*> [^\[]* \(([^\)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: log) {
            return String(log[range])
        }
        return "Apple Music Track"
    }
}
