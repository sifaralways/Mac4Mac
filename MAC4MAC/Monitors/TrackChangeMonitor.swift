import Foundation

class TrackChangeMonitor {
    private var lastTrackID: String?
    private var timer: Timer?

    var onTrackChange: ((String) -> Void)?  // persistentID passed

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let script = """
            tell application "Music"
                if it is running then
                    try
                        set currentID to the persistent ID of current track
                        return currentID
                    on error
                        return "ERROR"
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
                .trimmingCharacters(in: .whitespacesAndNewlines),
               output != "ERROR", output != "NOT_RUNNING", !output.isEmpty {

                if self.lastTrackID != nil && self.lastTrackID != output {
                    LogWriter.log("🎶 Track changed to \(output)")
                    self.onTrackChange?(output)
                }
                self.lastTrackID = output
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
