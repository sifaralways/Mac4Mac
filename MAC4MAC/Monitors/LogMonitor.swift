import Foundation

class LogMonitor {
    static func fetchLatestSampleRate(forTrack trackName: String, completion: @escaping (Double, String) -> Void) {
        LogWriter.log("🔍 Fetching Sample Rate...")

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
            LogWriter.log("❌ Failed to run log fetch: \(error.localizedDescription)")
            completion(44100.0, trackName)
            return
        }

        DispatchQueue.global().async {
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()

            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                LogWriter.log("⚠️ No sampleRate or song found in last 5m logs.")
                completion(44100.0, trackName)
                return
            }

            let lines = output.components(separatedBy: "\n").filter { $0.contains("SampleRate:") }
            if let lastLine = lines.last {
                LogWriter.log("📈 Raw Output: \(lastLine)")

                let pattern = #"SampleRate: ([^,]+), BitDepth: ([^,]+), Quality: ([^,]+)"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: lastLine, range: NSRange(lastLine.startIndex..., in: lastLine)) {

                    let sampleRateRange = Range(match.range(at: 1), in: lastLine)
                    let bitDepthRange = Range(match.range(at: 2), in: lastLine)
                    let qualityRange = Range(match.range(at: 3), in: lastLine)

                    if let sampleRateStr = sampleRateRange.map({ String(lastLine[$0]) })?.replacingOccurrences(of: "khz", with: ""),
                       let sampleRateKhz = Double(sampleRateStr) {

                        let rateHz = sampleRateKhz
                        let bitDepth = bitDepthRange.map { String(lastLine[$0]) } ?? "?"
                        let quality = qualityRange.map { String(lastLine[$0]) } ?? "?"
                        let description = "\(quality) \(bitDepth)"
                        LogWriter.log("🎧 Audio Format: \(description)")

                        LogWriter.log("📛 Track Name: \(trackName)")
                        completion(rateHz, trackName)
                        return
                    }
                }
            }

            LogWriter.log("⚠️ Unexpected format from log output: \(output)")
            completion(44100.0, trackName)
        }
    }
}
