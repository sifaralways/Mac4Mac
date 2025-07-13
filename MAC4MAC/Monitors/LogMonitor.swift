import Foundation

class LogMonitor {
    static func fetchLatestSampleRate(forTrack trackName: String, completion: @escaping (Double, String) -> Void) {
        LogWriter.logEssential("🔍 CRITICAL: Starting sample rate detection for: \(trackName)")

        let script = """
        log show --style syslog --predicate "process == \\\"Music\\\"" --last 5m | grep -i "activeFormat:" | sed -nE 's/.*tier: ([^;]+);.*groupID: [^:]+-([0-9]+)-[0-9]+;.*bitDepth: ([^;]+);.*/SampleRate: \\2, BitDepth: \\3, Quality: \\1/p'
        """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            LogWriter.logEssential("Failed to run sample rate detection: \(error.localizedDescription)")
            // Don't change sample rate on failure - continue with previous rate
            completion(0, trackName) // 0 indicates no change should be made
            return
        }

        DispatchQueue.global().async {
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                LogWriter.logNormal("No sample rate found in logs - keeping current rate")
                completion(0, trackName) // 0 indicates no change should be made
                return
            }

            let lines = output.components(separatedBy: "\n").filter { $0.contains("SampleRate:") }
            guard let lastLine = lines.last else {
                LogWriter.logNormal("No sample rate data in log output")
                completion(0, trackName)
                return
            }

            LogWriter.logDebug("Sample rate log output: \(lastLine)")

            let pattern = #"SampleRate: ([^,]+), BitDepth: ([^,]+), Quality: ([^,]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: lastLine, range: NSRange(lastLine.startIndex..., in: lastLine)) else {
                LogWriter.logNormal("Failed to parse sample rate from log")
                completion(0, trackName)
                return
            }

            let sampleRateRange = Range(match.range(at: 1), in: lastLine)
            let bitDepthRange = Range(match.range(at: 2), in: lastLine)
            let qualityRange = Range(match.range(at: 3), in: lastLine)

            guard let sampleRateStr = sampleRateRange.map({ String(lastLine[$0]) })?.replacingOccurrences(of: "khz", with: ""),
                  let sampleRateKhz = Double(sampleRateStr) else {
                LogWriter.logNormal("Failed to extract sample rate value")
                completion(0, trackName)
                return
            }

            let rateHz = sampleRateKhz
            let bitDepth = bitDepthRange.map { String(lastLine[$0]) } ?? "?"
            let quality = qualityRange.map { String(lastLine[$0]) } ?? "?"
            let description = "\(quality) \(bitDepth)"
            
            LogWriter.logEssential("Audio format detected: \(description) at \(rateHz) Hz")
            LogWriter.logEssential("Track: \(trackName)")
            
            completion(rateHz, trackName)
        }
    }
}
