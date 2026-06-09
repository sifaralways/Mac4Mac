import Foundation

class LogMonitor {

    private static var latestSampleRateHz: Double = 0
    private static var latestTrackName: String = ""
    private static var latestAudioFormat: String = ""

    private static var logStreamTask: Process?
    private static var isMonitoring = false
    private static let processingQueue = DispatchQueue(label: "LogMonitorQueue")

    /// Starts streaming Music.app logs and caches latest sample rate info
    private static func startMonitoringIfNeeded() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let script = """
        log stream --style syslog --predicate 'process == "Music" AND composedMessage CONTAINS "Creating AudioQueue with format"' --info
        """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        let handle = pipe.fileHandleForReading

        task.terminationHandler = { _ in
            LogWriter.logEssential("⚠️ Log stream terminated unexpectedly", module: .monitoringAndRateSwitching)
            isMonitoring = false
        }

        handle.readabilityHandler = { fileHandle in
            guard let chunk = String(data: fileHandle.availableData, encoding: .utf8) else { return }
            parseLogLine(chunk)
        }

        do {
            try task.run()
            logStreamTask = task
            LogWriter.logEssential("📡 Log stream started for sample rate monitoring", module: .monitoringAndRateSwitching)
        } catch {
            LogWriter.logEssential("❌ Failed to start log stream: \(error)", module: .monitoringAndRateSwitching)
        }
    }

    /// Parses log stream lines and extracts sample rate + audio format
    private static func parseLogLine(_ chunk: String) {

        let lines = chunk.components(separatedBy: .newlines)

        guard let lastLine = lines.last(where: {
            $0.contains("sampleRate:") && $0.contains("format:'")
        }) else {
            return
        }

        // MARK: - Sample Rate Extraction
        let sampleRatePattern = #"sampleRate:\s*([^,]+)"#

        guard let rateRegex = try? NSRegularExpression(pattern: sampleRatePattern),
              let rateMatch = rateRegex.firstMatch(
                in: lastLine,
                range: NSRange(lastLine.startIndex..., in: lastLine)
              ),
              let rateRange = Range(rateMatch.range(at: 1), in: lastLine)
        else {
            return
        }

        let sampleRateStr = String(lastLine[rateRange]).trimmingCharacters(in: .whitespaces)

        let cleanedRate = sampleRateStr.filter {
            ("0"..."9").contains($0) || $0 == "."
        }

        guard let rateHz = Double(cleanedRate) else { return }

        // MARK: - Audio Format Extraction
        let formatPattern = #"format:'([^']+)'"#

        var audioFormat = ""

        if let formatRegex = try? NSRegularExpression(pattern: formatPattern),
           let formatMatch = formatRegex.firstMatch(
                in: lastLine,
                range: NSRange(lastLine.startIndex..., in: lastLine)
           ),
           let formatRange = Range(formatMatch.range(at: 1), in: lastLine) {

            audioFormat = String(lastLine[formatRange])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ".", with: "")
        }

        processingQueue.async {
            let rateChanged = abs(rateHz - latestSampleRateHz) >= 1
            let formatChanged = audioFormat != latestAudioFormat

            if rateChanged || formatChanged {
                LogWriter.logEssential(
                    "🎚️ Audio Update → format: \(audioFormat), sampleRate: \(rateHz) Hz",
                    module: .monitoringAndRateSwitching
                )
            }

            latestSampleRateHz = rateHz
            latestAudioFormat = audioFormat
        }
    }

    /// API used elsewhere in the app
    static func fetchLatestSampleRate(
        forTrack trackName: String,
        completion: @escaping (Double, String, String) -> Void
    ) {
        startMonitoringIfNeeded()

        processingQueue.asyncAfter(deadline: .now() + 0.1) {

            if latestSampleRateHz == 0 {
                LogWriter.logNormal(
                    "⚠️ No sample rate detected yet via log stream — returning 0",
                    module: .monitoringAndRateSwitching
                )
            }

            completion(
                latestSampleRateHz,
                trackName,
                latestAudioFormat
            )
        }
    }

    /// Call this on app exit
    static func stopMonitoring() {
        logStreamTask?.terminate()
        logStreamTask = nil
        isMonitoring = false
    }
}
