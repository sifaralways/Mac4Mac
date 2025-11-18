import Foundation
import MusicKit

/// MusicPlayerAdapter centralizes playback calls so we can swap the underlying
/// MusicKit player implementation (ApplicationMusicPlayer vs SystemMusicPlayer)
/// in one place. This version prefers SystemMusicPlayer on macOS 12+ when available,
/// and falls back to ApplicationMusicPlayer otherwise.
actor MusicPlayerAdapter {
    static let shared = MusicPlayerAdapter()

    enum AdapterError: Error {
        case insertFailed(Error)
        case playFailed(Error)
    }

    /// Insert a Song into the player's queue and attempt to play it.
    /// Prefers SystemMusicPlayer when available (controls Music.app), otherwise
    /// falls back to ApplicationMusicPlayer which only plays in-process.
    func insertAndPlaySong(_ song: Song) async throws {
        // NOTE: SystemMusicPlayer is the documented API to control the Music app.
        // In environments where SystemMusicPlayer isn't available at compile/runtime,
        // fall back to ApplicationMusicPlayer so the project remains buildable.
        // When you have an SDK that exposes SystemMusicPlayer, replace the
        // ApplicationMusicPlayer usage below with a guarded SystemMusicPlayer path.
        do {
            let player = ApplicationMusicPlayer.shared
            try await player.queue.insert(song, position: .afterCurrentEntry)
            try await player.play()
            return
        } catch {
            throw AdapterError.playFailed(error)
        }
    }

    // Basic transport controls implemented against the in-process ApplicationMusicPlayer.
    // Replace these with SystemMusicPlayer equivalents when available in your build.
    func play() async throws {
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            try await player.play()
            return
        }

        // Fallback to AppleScript when SystemMusicPlayer not available
        let script = "tell application \"Music\" to play"
        let (ok, out) = runAppleScript(script)
        if !ok {
            throw AdapterError.playFailed(NSError(domain: "MusicPlayerAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript play failed: \(out)"]))
        }
    }

    func pause() async throws {
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            try await player.pause()
            return
        }

        let script = "tell application \"Music\" to pause"
        let (ok, out) = runAppleScript(script)
        if !ok {
            throw AdapterError.playFailed(NSError(domain: "MusicPlayerAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript pause failed: \(out)"]))
        }
    }

    func skipToNext() async throws {
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            try await player.skipToNext()
            return
        }

        let script = "tell application \"Music\" to next track"
        let (ok, out) = runAppleScript(script)
        if !ok {
            throw AdapterError.playFailed(NSError(domain: "MusicPlayerAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript next failed: \(out)"]))
        }
    }

    func skipToPrevious() async throws {
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            try await player.skipToPrevious()
            return
        }

        let script = "tell application \"Music\" to previous track"
        let (ok, out) = runAppleScript(script)
        if !ok {
            throw AdapterError.playFailed(NSError(domain: "MusicPlayerAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript previous failed: \(out)"]))
        }
    }

    // Shuffle and repeat controls
    func setShuffle(_ enabled: Bool) async throws {
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            player.shuffleMode = enabled ? .songs : .off
            return
        }

        // AppleScript fallback
        let script = "tell application \"Music\" to set shuffle enabled to \(enabled ? "true" : "false")"
        let (ok, out) = runAppleScript(script)
        if !ok {
            throw AdapterError.playFailed(NSError(domain: "MusicPlayerAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript setShuffle failed: \(out)"]))
        }
    }

    func setRepeat(mode: Int) async throws {
        // mode: 0=none,1=one,2=all
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            switch mode {
            case 1: player.repeatMode = .one
            case 2: player.repeatMode = .all
            default: player.repeatMode = .none
            }
            return
        }

        // AppleScript fallback: use song repeat for one/all
        var script = ""
        switch mode {
        case 1:
            script = "tell application \"Music\" to set song repeat to one"
        case 2:
            script = "tell application \"Music\" to set song repeat to all"
        default:
            script = "tell application \"Music\" to set song repeat to off"
        }
        let (ok, out) = runAppleScript(script)
        if !ok {
            throw AdapterError.playFailed(NSError(domain: "MusicPlayerAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AppleScript setRepeat failed: \(out)"]))
        }
    }

    // Now-playing / progress
    func nowPlayingInfo() async -> (isPlaying: Bool, position: Double, duration: Double, title: String?, artist: String?) {
        if #available(macOS 12, *) {
            let player = SystemMusicPlayer.shared
            let isPlaying = (player.playbackState == .playing)
            let position = player.playbackTime
            let duration = player.currentEntry?.item?.playbackDuration ?? 0
            let title = player.currentEntry?.item?.title
            let artist = player.currentEntry?.item?.artistName
            return (isPlaying, position, duration, title, artist)
        }

        // Fallback to AppleScript probe (quick)
        let script = """
        tell application "Music"
            if it is running then
                try
                    set isPlaying to (player state is playing)
                    if exists current track then
                        set pos to player position
                        set dur to duration of current track
                        set t to name of current track
                        set a to artist of current track
                        return pos & "," & dur & "," & (isPlaying as string) & "," & t & "|" & a
                    else
                        return "0,0,false,|"
                    end if
                on error
                    return "0,0,false,|"
                end try
            else
                return "0,0,false,|"
            end if
        end tell
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            let parts = out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ",")
            if parts.count >= 4 {
                let pos = Double(parts[0]) ?? 0
                let dur = Double(parts[1]) ?? 0
                let isPlay = parts[2] == "true"
                let titleArtist = parts[3]
                let taParts = titleArtist.components(separatedBy: "|")
                let t = taParts.first
                let a = taParts.count > 1 ? taParts[1] : nil
                return (isPlay, pos, dur, t, a)
            }
        } catch {
            // ignore
        }
        return (false, 0, 0, nil, nil)
    }

    // Run an AppleScript command using osascript; returns (success, outputOrError)
    private func runAppleScript(_ script: String) -> (Bool, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return (false, "Failed to run osascript: \(error.localizedDescription)")
        }

        task.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        if task.terminationStatus == 0 {
            let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (true, outStr)
        } else {
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            return (false, errStr)
        }
    }

    func insertAndPlayPlayParameters(_ playParametersID: String) async throws {
        // If caller supplies an opaque playParameters token, attempt a catalog resource
        // lookup for that id and play the resolved Song.
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(playParametersID))
        do {
            let resp = try await request.response()
            if let song = resp.items.first {
                try await insertAndPlaySong(song)
                return
            } else {
                throw AdapterError.insertFailed(NSError(domain: "MusicPlayerAdapter", code: 404, userInfo: [NSLocalizedDescriptionKey: "PlayParameters id not found in catalog"]))
            }
        } catch {
            throw AdapterError.insertFailed(error)
        }
    }

    /// Resolve a set of candidate identifiers (playParametersID, catalogID variants, persistentID) and/or metadata
    /// and attempt to play the best match. Returns (played, resolvedID, message).
    func resolveAndPlay(catalogID: String?, playParametersID: String?, persistentID: String?, title: String?, artist: String?, album: String?) async -> (Bool, String?, String) {
        var lastMessage = ""

        // Helper to attempt a resource request for a candidate id
        func tryCandidate(_ candidate: String) async -> (Bool, String) {
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(candidate))
                let response = try await request.response()
                if let song = response.items.first {
                    do {
                        try await insertAndPlaySong(song)
                        return (true, "Played candidate id=\(candidate)")
                    } catch {
                        return (false, "Adapter play failed for id=\(candidate): \(error)")
                    }
                } else {
                    return (false, "No catalog item for id=\(candidate)")
                }
            } catch {
                return (false, "Catalog lookup error for id=\(candidate): \(error)")
            }
        }

        // 1) try explicit playParametersID first
        if let pp = playParametersID, !pp.isEmpty {
            let (ok, msg) = await tryCandidate(pp)
            if ok { return (true, pp, msg) }
            lastMessage = msg
        }

        // 2) try catalogID and common variants
        if let cat = catalogID, !cat.isEmpty {
            let candidates = [cat, "i.\(cat)"]
            for c in candidates {
                let (ok, msg) = await tryCandidate(c)
                if ok { return (true, c, msg) }
                lastMessage = msg
            }
        }

        // 3) try persistentID variants if present
        if let pid = persistentID, !pid.isEmpty {
            let (ok, msg) = await tryCandidate(pid)
            if ok { return (true, pid, msg) }
            lastMessage = msg
        }

        // 4) as a last attempt, perform catalog search by metadata
        if let t = title, !t.isEmpty, let a = artist, !a.isEmpty {
            do {
                var searchReq = MusicCatalogSearchRequest(term: "\(t) \(a)", types: [Song.self])
                searchReq.limit = 10
                let resp = try await searchReq.response()
                if let first = resp.songs.first {
                    do {
                        try await insertAndPlaySong(first)
                        return (true, first.id.rawValue, "Played via metadata search: id=\(first.id.rawValue)")
                    } catch {
                        lastMessage = "Metadata search play error: \(error)"
                    }
                } else {
                    lastMessage = "Metadata search returned no matches"
                }
            } catch {
                lastMessage = "Metadata search error: \(error)"
            }
        }

        return (false, nil, lastMessage)
    }
}
