import Foundation

class PlaylistManager {

    /// Add track to playlist named by sample rate string, creating playlist if needed
    static func addTrack(persistentID: String, sampleRate: Double) {
        let playlistName = String(format: "MAC4MAC %.1f kHz", sampleRate / 1000.0)
        let script = """
        tell application "Music"
            if not (exists playlist "\(playlistName)") then
                make new playlist with properties {name:"\(playlistName)"}
            end if

            set targetPlaylist to playlist "\(playlistName)"
            set trackExists to false

            repeat with t in tracks of targetPlaylist
                if persistent ID of t is "\(persistentID)" then
                    set trackExists to true
                    exit repeat
                end if
            end repeat

            if not trackExists then
                try
                    set theTrack to some track of library playlist 1 whose persistent ID is "\(persistentID)"
                    duplicate theTrack to targetPlaylist
                on error
                    -- Track not found in library, maybe removed
                end try
            end if
        end tell
        """

        runAppleScript(script)
    }

    /// Helper to run AppleScript code synchronously
    private static func runAppleScript(_ source: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", source]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                LogWriter.log("📂 AppleScript output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                LogWriter.log("⚠️ AppleScript ran but returned no output.")
            }
        } catch {
            LogWriter.log("❌ AppleScript error: \(error.localizedDescription)")
        }
    }
}
