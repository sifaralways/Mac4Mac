import MusicKit
import Foundation
// Note: LogWriter is available as part of the same module

/// Audio Variant Scanner - Scans Music library for High Res and Atmos tracks
class AudioVariantScanner {
    /// Song variants structure
    struct SongVariants {
        let lossless: Bool
        let highRes: Bool
        let atmos: Bool
        let spatial: Bool
    }

    /// Scans the Music library for audio variants and creates playlists
    func performScan() async {
        LogWriter.logEssential("🎵 Starting Audio Variant scan of Music library...")

        // Request MusicKit authorization
        LogWriter.logNormal("🔐 Requesting MusicKit authorization...")
        let status = await MusicAuthorization.request()

        guard status == .authorized else {
            LogWriter.logEssential("❌ MusicKit authorization failed. Status: \(status)")
            return
        }

        LogWriter.logEssential("✅ MusicKit authorized successfully!")

        do {
            // Fetch all songs from library using pagination
            var allSongs: [Song] = []
            var offset = 0
            let batchSize = 100

            LogWriter.logNormal("📊 Fetching songs from library...")

            while true {
                var songsRequest = MusicLibraryRequest<Song>()
                songsRequest.limit = batchSize
                songsRequest.offset = offset

                let songsResponse = try await songsRequest.response()

                if songsResponse.items.isEmpty {
                    break
                }

                allSongs.append(contentsOf: songsResponse.items)
                offset += batchSize

                LogWriter.logNormal("   📥 Retrieved \(allSongs.count) songs so far...")

                // Safety check: prevent infinite loops or excessive memory usage
                if allSongs.count > 50000 {
                    LogWriter.logEssential("⚠️ Reached 50,000 songs limit for safety. Use a more targeted approach for larger libraries.")
                    break
                }
            }

            LogWriter.logEssential("✅ Total songs retrieved: \(allSongs.count)")

            // Process AudioVariants in chunks
            let chunkSize = 50
            var songVariants: [(song: Song, variants: SongVariants)] = []

            LogWriter.logNormal("🔍 Processing AudioVariants in chunks of \(chunkSize)...")

            for chunkStart in stride(from: 0, to: allSongs.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, allSongs.count)
                let chunk = Array(allSongs[chunkStart..<chunkEnd])

                LogWriter.logDebug("   📊 Processing songs \(chunkStart + 1)-\(chunkEnd) of \(allSongs.count)...")

                for song in chunk {
                    let variants = await getSongAudioVariants(song)
                    songVariants.append((song: song, variants: variants))
                }
            }

            // Create playlists
            LogWriter.logEssential("🎵 Creating playlists based on AudioVariants...")

            let highResSongs = songVariants.filter { $0.variants.highRes }.map { $0.song }
            let atmosSongs = songVariants.filter { $0.variants.atmos }.map { $0.song }

            LogWriter.logNormal("   📊 Found \(highResSongs.count) High Res songs and \(atmosSongs.count) Atmos songs")

            if !highResSongs.isEmpty {
                LogWriter.logNormal("   📊 Creating playlist 'High Resolution Songs' with \(highResSongs.count) tracks...")
                await createPlaylistAndAddTracks(name: "High Resolution Songs",
                                               description: "Songs available in High Resolution Lossless format (24-bit/192 kHz)",
                                               songs: highResSongs)
            } else {
                LogWriter.logNormal("   ℹ️ No High Resolution songs found, skipping playlist creation")
            }

            if !atmosSongs.isEmpty {
                LogWriter.logNormal("   📊 Creating playlist 'Dolby Atmos Tracks' with \(atmosSongs.count) tracks...")
                await createPlaylistAndAddTracks(name: "Dolby Atmos Tracks",
                                               description: "Songs available in Dolby Atmos immersive audio format",
                                               songs: atmosSongs)
            } else {
                LogWriter.logNormal("   ℹ️ No Dolby Atmos tracks found, skipping playlist creation")
            }

            // Calculate summary
            let losslessCount = songVariants.filter { $0.variants.lossless }.count
            let highResCount = songVariants.filter { $0.variants.highRes }.count
            let atmosCount = songVariants.filter { $0.variants.atmos }.count
            let spatialCount = songVariants.filter { $0.variants.spatial }.count

            LogWriter.logEssential("🎉 Audio Variant scan completed!")
            LogWriter.logNormal("📊 Summary: \(songVariants.count) songs analyzed")
            LogWriter.logNormal("   • Lossless: \(losslessCount)")
            LogWriter.logNormal("   • High Res Lossless: \(highResCount)")
            LogWriter.logNormal("   • Dolby Atmos: \(atmosCount)")
            LogWriter.logNormal("   • Spatial Audio: \(spatialCount)")

        } catch {
            LogWriter.logEssential("❌ Failed to access music library: \(error.localizedDescription)")
        }
    }

    private func getSongAudioVariants(_ song: Song) async -> SongVariants {
        do {
            let detailedSong = try await song.with([.audioVariants])
            if let audioVariants = detailedSong.audioVariants {
                let lossless = audioVariants.contains(.lossless)
                let highRes = audioVariants.contains(.highResolutionLossless)
                let atmos = audioVariants.contains(.dolbyAtmos)
                let spatial = audioVariants.contains(.spatialAudio)

                // Debug logging for variant detection
                let sanitizedTitle = song.title.replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                    .replacingOccurrences(of: "&", with: "and")
                    .replacingOccurrences(of: "/", with: "")
                    .replacingOccurrences(of: "\\", with: "")
                let sanitizedArtist = song.artistName.replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "&", with: "and")
                    .replacingOccurrences(of: "/", with: "")
                    .replacingOccurrences(of: "\\", with: "")

                if lossless || highRes || atmos || spatial {
                    LogWriter.logDebug("Song '\(sanitizedTitle)' by '\(sanitizedArtist)' has variants: lossless=\(lossless), highRes=\(highRes), atmos=\(atmos), spatial=\(spatial)")
                }

                return SongVariants(lossless: lossless, highRes: highRes, atmos: atmos, spatial: spatial)
            } else {
                return SongVariants(lossless: false, highRes: false, atmos: false, spatial: false)
            }
        } catch {
            LogWriter.logDebug("ERROR loading variants for '\(song.title)' by '\(song.artistName)': \(error.localizedDescription)")
            return SongVariants(lossless: false, highRes: false, atmos: false, spatial: false)
        }
    }

    private func createPlaylistAndAddTracks(name: String, description: String, songs: [Song]) async {
        // First, create the playlist if it doesn't exist
        let createScript = """
        tell application "Music"
            if not (exists playlist "\(name)") then
                make new playlist with properties {name:"\(name)", description:"\(description)"}
            end if
        end tell
        """
        runAppleScript(createScript)

        // Use batch processing with better error handling
        let batchSize = 20
        var totalProcessed = 0
        var totalAdded = 0

        LogWriter.logNormal("   📤 Adding \(songs.count) tracks to playlist in batches of \(batchSize)...")

        for batchStart in stride(from: 0, to: songs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, songs.count)
            let batch = Array(songs[batchStart..<batchEnd])

            LogWriter.logDebug("   📦 Processing batch \(batchStart/batchSize + 1) (\(batchStart + 1)-\(batchEnd) of \(songs.count))...")

            var batchAdded = 0

            // Process each song individually
            for song in batch {
                let result = await addSongToPlaylist(song, playlistName: name)
                if result {
                    batchAdded += 1
                }
            }

            totalProcessed += batch.count
            totalAdded += batchAdded

            LogWriter.logDebug("   📊 Batch \(batchStart/batchSize + 1) complete: \(batchAdded) added")
        }

        LogWriter.logNormal("   🎯 Playlist operation complete: \(totalAdded)/\(songs.count) tracks added (\(String(format: "%.1f", Double(totalAdded)/Double(songs.count)*100))% success rate)")
    }

    private func addSongToPlaylist(_ song: Song, playlistName: String) async -> Bool {
        // Mild sanitization
        let title = song.title.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        let artist = song.artistName.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")

        // Try multiple matching strategies with duplicate-first, add-fallback approach
        let addScript = """
        tell application "Music"
            if not (exists playlist "\(playlistName)") then
                make new playlist with properties {name:"\(playlistName)"}
            end if

            set targetPlaylist to playlist "\(playlistName)"

            -- FIRST: Check if song is already in playlist
            try
                set existingTracks to (tracks of targetPlaylist whose name contains "\(title)" and artist contains "\(artist)")
                if (count of existingTracks) > 0 then
                    return "ALREADY_EXISTS"
                end if
            end try

            set trackAdded to false

            try
                -- Strategy 1: Try exact match first
                set foundTrack to (first track of library playlist 1 whose name is "\(title)" and artist is "\(artist)")
                set trackAdded to true
            on error
                try
                    -- Strategy 2: Try contains match for both title and artist
                    set foundTrack to (first track of library playlist 1 whose name contains "\(title)" and artist contains "\(artist)")
                    set trackAdded to true
                on error
                    try
                        -- Strategy 3: Try contains match for title only (more lenient)
                        set foundTrack to (first track of library playlist 1 whose name contains "\(title)")
                        set trackAdded to true
                    on error
                        -- Strategy 4: Check if it's a local file track that can't be duplicated
                        set localTracks to (tracks whose name contains "\(title)" and kind contains "MPEG" or kind contains "AAC" or kind contains "Apple Lossless")
                        if (count of localTracks) > 0 then
                            return "LOCAL_FILE"
                        else
                            return "NOT_FOUND"
                        end if
                    end try
                end try
            end try

            if trackAdded then
                -- Check if it's a local file track BEFORE trying duplicate/add
                try
                    -- Check if the track has a location (local file) or is a streaming track
                    set trackLocation to location of foundTrack
                    -- If we get here, it's a local file track
                    return "LOCAL_FILE_CANNOT_ADD"
                on error
                    -- No location property means it's likely a streaming track, proceed with duplicate/add
                end try

                try
                    -- First try: duplicate (works better for some tracks)
                    duplicate foundTrack to targetPlaylist
                    return "SUCCESS_DUPLICATE"
                on error duplicateError
                    try
                        -- Second try: add (fallback method)
                        add foundTrack to targetPlaylist
                        return "SUCCESS_ADD"
                    on error addError
                        -- Both methods failed, return the error
                        return "DUPLICATE_ERROR: " & duplicateError & " | ADD_ERROR: " & addError
                    end try
                end try
            end if
        end tell
        """

        if let result = runAppleScriptWithResult(addScript) {
            if result.contains("SUCCESS_DUPLICATE") {
                LogWriter.logDebug("Song '\(title)' by '\(artist)' added to playlist (duplicate)")
                return true
            } else if result.contains("SUCCESS_ADD") {
                LogWriter.logDebug("Song '\(title)' by '\(artist)' added to playlist (add)")
                return true
            } else if result.contains("ALREADY_EXISTS") {
                LogWriter.logDebug("Song '\(title)' by '\(artist)' already exists in playlist")
                return true // Count as success
            } else if result.contains("LOCAL_FILE") || result.contains("LOCAL_FILE_CANNOT_ADD") {
                LogWriter.logDebug("Song '\(title)' by '\(artist)' is a local file track - cannot add to playlist")
                return false
            } else if result.contains("NOT_FOUND") {
                LogWriter.logDebug("Song '\(title)' by '\(artist)' has no tracks available at all")
                return false
            } else if result.contains("DUPLICATE_ERROR") || result.contains("ADD_ERROR") {
                LogWriter.logDebug("ERROR: Song '\(title)' by '\(artist)' failed - \(result)")
                return false
            } else {
                LogWriter.logDebug("UNKNOWN: Song '\(title)' by '\(artist)' result: \(result)")
                return false
            }
        }

        return false
    }

    private func runAppleScript(_ source: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", source]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            LogWriter.logEssential("AppleScript error: \(error.localizedDescription)")
        }
    }

    private func runAppleScriptWithResult(_ source: String) -> String? {
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
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output
        } catch {
            LogWriter.logEssential("AppleScript error: \(error.localizedDescription)")
            return nil
        }
    }
}