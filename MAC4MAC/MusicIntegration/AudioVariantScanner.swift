import MusicKit
import Foundation

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
            var songsWithVariants = 0

            LogWriter.logEssential("🔍 Processing AudioVariants in chunks of \(chunkSize)...")

            for chunkStart in stride(from: 0, to: allSongs.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, allSongs.count)
                let chunk = Array(allSongs[chunkStart..<chunkEnd])

                LogWriter.logEssential("   📊 Processing songs \(chunkStart + 1)-\(chunkEnd) of \(allSongs.count)...")

                for song in chunk {
                    let variants = await getSongAudioVariants(song)
                    songVariants.append((song: song, variants: variants))
                    
                    if variants.lossless || variants.highRes || variants.atmos || variants.spatial {
                        songsWithVariants += 1
                    }
                }
                
                LogWriter.logEssential("   📊 Chunk complete: \(songsWithVariants) songs with variants found so far")
            }

            LogWriter.logEssential("✅ Variant processing complete: \(songsWithVariants)/\(allSongs.count) songs have audio variants")

            // Create playlists
            LogWriter.logEssential("🎵 Creating playlists based on AudioVariants...")

            let highResSongs = songVariants.filter { $0.variants.highRes }.map { $0.song }
            let atmosSongs = songVariants.filter { $0.variants.atmos }.map { $0.song }

            LogWriter.logEssential("📊 Found \(highResSongs.count) High Res songs and \(atmosSongs.count) Atmos songs")

            if !highResSongs.isEmpty {
                LogWriter.logEssential("📊 Creating playlist 'High Resolution Songs' with \(highResSongs.count) tracks...")
                await createPlaylistAndAddTracks(name: "High Resolution Songs",
                                               description: "Songs available in High Resolution Lossless format (24-bit/192 kHz)",
                                               songs: highResSongs)
            } else {
                LogWriter.logEssential("ℹ️ No High Resolution songs found, skipping playlist creation")
            }

            if !atmosSongs.isEmpty {
                LogWriter.logEssential("📊 Creating playlist 'Dolby Atmos Tracks' with \(atmosSongs.count) tracks...")
                await createPlaylistAndAddTracks(name: "Dolby Atmos Tracks",
                                               description: "Songs available in Dolby Atmos immersive audio format",
                                               songs: atmosSongs)
            } else {
                LogWriter.logEssential("ℹ️ No Dolby Atmos tracks found, skipping playlist creation")
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
        LogWriter.logEssential("🔧 Creating/verifying playlist '\(name)'...")
        let createScript = """
        tell application "Music"
            if not (exists playlist "\(name)") then
                make new playlist with properties {name:"\(name)", description:"\(description)"}
                return "PLAYLIST_CREATED"
            else
                return "PLAYLIST_EXISTS"
            end if
        end tell
        """
        if let createResult = runAppleScriptWithResult(createScript) {
            LogWriter.logEssential("📁 Playlist '\(name)' creation result: \(createResult)")
        } else {
            LogWriter.logEssential("❌ Failed to create/verify playlist '\(name)'")
            return
        }

        // Use batch processing with better error handling
        let batchSize = 20
        var totalProcessed = 0
        var totalAdded = 0

        LogWriter.logEssential("📤 Adding \(songs.count) tracks to playlist '\(name)' in batches of \(batchSize)...")

        for batchStart in stride(from: 0, to: songs.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, songs.count)
            let batch = Array(songs[batchStart..<batchEnd])

            LogWriter.logEssential("📦 Processing batch \(batchStart/batchSize + 1) (\(batchStart + 1)-\(batchEnd) of \(songs.count))...")

            var batchAdded = 0

            // Process each song individually
            for song in batch {
                LogWriter.logEssential("🎵 Processing song: '\(song.title)' by '\(song.artistName)'")
                let result = await addSongToPlaylist(song, playlistName: name)
                if result {
                    batchAdded += 1
                    LogWriter.logEssential("✅ Successfully processed '\(song.title)' by '\(song.artistName)'")
                } else {
                    LogWriter.logEssential("❌ Failed to process '\(song.title)' by '\(song.artistName)'")
                }
            }

            totalProcessed += batch.count
            totalAdded += batchAdded

            LogWriter.logEssential("📊 Batch \(batchStart/batchSize + 1) complete: \(batchAdded)/\(batch.count) added")
        }

        LogWriter.logEssential("🎯 Playlist '\(name)' operation complete: \(totalAdded)/\(songs.count) tracks added (\(String(format: "%.1f", Double(totalAdded)/Double(songs.count)*100))% success rate)")
    }

    private func addSongToPlaylist(_ song: Song, playlistName: String) async -> Bool {
        // Mild sanitization for fallback matching
        let title = song.title.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        let artist = song.artistName.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        
        // First, check if song already exists in playlist
        let duplicateCheckScript = """
        tell application "Music"
            try
                if not (exists playlist "\(playlistName)") then
                    return "PLAYLIST_NOT_EXISTS"
                end if
                
                set targetPlaylist to playlist "\(playlistName)"
                set allTracks to tracks of targetPlaylist
                
                repeat with aTrack in allTracks
                    if (name of aTrack is "\(title)") and (artist of aTrack is "\(artist)") then
                        return "ALREADY_EXISTS"
                    end if
                end repeat
                
                return "NOT_EXISTS"
            on error errMsg
                return "DUPLICATE_CHECK_ERROR: " & errMsg
            end try
        end tell
        """
        
        if let duplicateResult = runAppleScriptWithResult(duplicateCheckScript) {
            LogWriter.logEssential("🔍 Duplicate check for '\(title)' by '\(artist)': \(duplicateResult)")
            
            if duplicateResult.contains("ALREADY_EXISTS") {
                LogWriter.logEssential("✅ Song '\(title)' by '\(artist)' already exists in playlist - skipping")
                return true // Count as success since it's already there
            } else if duplicateResult.contains("PLAYLIST_NOT_EXISTS") {
                LogWriter.logEssential("ℹ️ Playlist '\(playlistName)' doesn't exist yet - will create and add")
                // Continue to add logic below
            } else if !duplicateResult.contains("NOT_EXISTS") {
                LogWriter.logEssential("⚠️ Unexpected duplicate check result: \(duplicateResult) - proceeding with add")
                // Continue to add logic below
            }
        } else {
            LogWriter.logEssential("❌ Duplicate check failed for '\(title)' by '\(artist)' - proceeding with add")
            // Continue to add logic below
        }
        
        // If we get here, either duplicate check failed or song doesn't exist - try to add it
        let addScript = """
        tell application "Music"
            if not (exists playlist "\(playlistName)") then
                make new playlist with properties {name:"\(playlistName)"}
            end if

            set targetPlaylist to playlist "\(playlistName)"

            set trackAdded to false
            set searchTitle to "\(title)"
            set searchArtist to "\(artist)"

            -- Log what we're searching for
            log "Searching for: " & searchTitle & " by " & searchArtist

            try
                -- Try exact match for title and artist
                set foundTrack to (first track of library playlist 1 whose name is searchTitle and artist is searchArtist)
                set trackAdded to true
                log "Found exact match"
            on error
                try
                    -- Try contains match for both title and artist (more lenient)
                    set foundTrack to (first track of library playlist 1 whose name contains searchTitle and artist contains searchArtist)
                    set trackAdded to true
                    log "Found contains match for title+artist"
                on error
                    try
                        -- Try contains match for title only (most lenient)
                        set foundTrack to (first track of library playlist 1 whose name contains searchTitle)
                        set trackAdded to true
                        log "Found contains match for title only"
                    on error
                        -- Try to find any track with similar title (very lenient fallback)
                        tell library playlist 1
                            set allTracks to tracks
                            repeat with aTrack in allTracks
                                if name of aTrack contains searchTitle then
                                    set foundTrack to aTrack
                                    set trackAdded to true
                                    log "Found track with manual search: " & (name of aTrack) & " by " & (artist of aTrack)
                                    exit repeat
                                end if
                            end repeat
                        end tell
                        if not trackAdded then
                            log "No tracks found with any search method"
                            return "NOT_FOUND"
                        end if
                    end try
                end try
            end try

            if trackAdded then
                -- Always try to add the track regardless of local/streaming status
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
            LogWriter.logEssential("📤 Add result for '\(title)' by '\(artist)': \(result)")
            
            if result.contains("SUCCESS_DUPLICATE") {
                LogWriter.logEssential("✅ Song '\(title)' by '\(artist)' added to playlist (duplicate)")
                return true
            } else if result.contains("SUCCESS_ADD") {
                LogWriter.logEssential("✅ Song '\(title)' by '\(artist)' added to playlist (add)")
                return true
            } else if result.contains("LOCAL_FILE") {
                LogWriter.logEssential("⚠️ Song '\(title)' by '\(artist)' is a local file track - cannot add to playlist")
                return false
            } else if result.contains("NOT_FOUND") {
                LogWriter.logEssential("❌ Song '\(title)' by '\(artist)' has no tracks available at all")
                return false
            } else if result.contains("DUPLICATE_ERROR") || result.contains("ADD_ERROR") {
                LogWriter.logEssential("❌ ERROR: Song '\(title)' by '\(artist)' failed - \(result)")
                return false
            } else {
                LogWriter.logEssential("❓ UNKNOWN: Song '\(title)' by '\(artist)' result: \(result)")
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