import Foundation
import AppKit

class TrackChangeMonitor {
    private var lastTrackID: String?
    private var timer: Timer?

    struct TrackInfo {
        let name: String
        let album: String
        let persistentID: String
    }

    var onTrackChange: ((TrackInfo) -> Void)?  // now passes full track info

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let script = """
            tell application "Music"
                if it is running then
                    try
                        delay 0.2
                        if exists current track then
                            set t to current track
                            set trackName to name of t
                            set albumName to album of t
                            if persistent ID of t is not missing value then
                                set trackID to persistent ID of t
                            else
                                set trackID to "MISSING_ID"
                            end if
                            return trackName & "||" & albumName & "||" & trackID
                        else
                            return "NO_TRACK"
                        end if
                    on error errMsg
                        return "ERROR: " & errMsg
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
               !output.isEmpty,
               !output.hasPrefix("ERROR"),
               output != "NOT_RUNNING",
               output != "NO_TRACK" {

                let components = output.components(separatedBy: "||")
                guard components.count == 3 else {
                    LogWriter.log("⚠️ Unexpected script output: \(output)")
                    return
                }

                let name = components[0]
                let album = components[1]
                let id = components[2]

                if self.lastTrackID != id {
                    self.lastTrackID = id
                    let trackInfo = TrackInfo(name: name, album: album, persistentID: id)
                    LogWriter.log("🎶 Track changed to \(name) from album \(album), ID \(id)")
                    self.onTrackChange?(trackInfo)
                }
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
