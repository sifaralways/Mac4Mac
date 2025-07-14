import Foundation

class LogMonitor {
    private static var latestSampleRateHz: Double = 0
    private static var latestTrackName: String = ""
    private static var logStreamTask: Process?
    private static var isMonitoring = false
    private static let processingQueue = DispatchQueue(label: "LogMonitorQueue")

    /// Starts streaming Music.app logs and caches latest sample rate info
    private static func startMonitoringIfNeeded() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let script = """
        log stream --style syslog --predicate 'process == "Music"' --info
        """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let handle = pipe.fileHandleForReading

        task.terminationHandler = { _ in
            LogWriter.logEssential("⚠️ Log stream terminated unexpectedly")
            isMonitoring = false
        }

        handle.readabilityHandler = { fileHandle in
            guard let line = String(data: fileHandle.availableData, encoding: .utf8) else { return }
            parseLogLine(line)
        }

        do {
            try task.run()
            logStreamTask = task
            LogWriter.logEssential("📡 Log stream started for sample rate monitoring")
        } catch {
            LogWriter.logEssential("❌ Failed to start log stream: \(error)")
        }
    }
    //using stream now
    private static func parseLogLine(_ line: String) {
        guard line.contains("activeFormat:") else { return }

        // Note: adjusted pattern to extract sample rate from groupID
        let pattern = #"tier: ([^;]+);.*groupID: audio-[^;]+-([0-9]+)-[0-9]+;.*bitDepth: ([^;]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return
        }

        guard let qualityRange = Range(match.range(at: 1), in: line),
              let sampleRateRange = Range(match.range(at: 2), in: line),
              let bitDepthRange = Range(match.range(at: 3), in: line) else {
            return
        }

        let quality = String(line[qualityRange])
        let sampleRateStr = String(line[sampleRateRange])
        let bitDepth = String(line[bitDepthRange])

        guard let rateHz = Double(sampleRateStr) else { return }

        processingQueue.async {
            if abs(rateHz - latestSampleRateHz) >= 1 {
                LogWriter.logEssential("🎚️ Stream detected new sample rate: \(rateHz) Hz (\(quality), \(bitDepth))")
            }
            latestSampleRateHz = rateHz
        }
    }



    /// API-compatible method used elsewhere in the app
    static func fetchLatestSampleRate(forTrack trackName: String, completion: @escaping (Double, String) -> Void) {
        startMonitoringIfNeeded()

        processingQueue.asyncAfter(deadline: .now() + 0.1) {
            // Fallback if no sample rate detected yet
            if latestSampleRateHz == 0 {
                LogWriter.logNormal("⚠️ No sample rate detected yet via log stream — returning 0")
            }
            completion(latestSampleRateHz, trackName)
        }
    }

    /// Call this on app exit
    static func stopMonitoring() {
        logStreamTask?.terminate()
        logStreamTask = nil
        isMonitoring = false
    }
}
