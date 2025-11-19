import MusicKit
import Foundation

// AudioVariant POC - Simple test script
print("🎵 MAC4MAC AudioVariant POC")
print("Testing MusicKit AudioVariant API")
print("=================================")

// Ensure LocalTriageDetails directory exists
let logDirectory = "LocalTriageDetails"
do {
    try FileManager.default.createDirectory(atPath: logDirectory, withIntermediateDirectories: true, attributes: nil)
} catch {
    print("❌ Failed to create log directory: \(error)")
}

// Logging utility
func logToFile(_ message: String, filename: String) {
    let fileURL = URL(fileURLWithPath: "\(logDirectory)/\(filename)")
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
    let logEntry = "[\(timestamp)] \(message)\n"
    
    do {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            fileHandle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try logEntry.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    } catch {
        print("❌ Failed to write to log file \(filename): \(error)")
    }
}

Task {
    // Create LocalTriageDetails directory if it doesn't exist
    let triageDir = "LocalTriageDetails"
    do {
        try FileManager.default.createDirectory(atPath: triageDir, withIntermediateDirectories: true, attributes: nil)
        print("📁 Created/verified LocalTriageDetails directory")
    } catch {
        print("⚠️ Could not create LocalTriageDetails directory: \(error)")
    }
    
    // Request authorization
    print("\n🔐 Requesting MusicKit authorization...")
    let status = await MusicAuthorization.request()
    print("Authorization status: \(status)")

    guard status == .authorized else {
        print("❌ MusicKit authorization failed. Status: \(status)")
        exit(1)
    }

    print("✅ MusicKit authorized successfully!")

    // Test with library tracks
    await testLibraryTracks()

    // Test with Apple Music catalog tracks
    await testAppleMusicTracks()

    print("\n🎉 AudioVariant POC completed!")

    // Summary of findings
    print("\n📋 AudioVariant POC Summary")
    print("===========================")
    print("🎵 AudioVariant is an enum representing different audio quality options:")
    print("   • .lossless - ALAC up to 24-bit/48 kHz")
    print("   • .highResolutionLossless - ALAC up to 24-bit/192 kHz")
    print("   • .dolbyAtmos - Immersive surround sound")
    print("   • .dolbyAudio - 5.1/7.1 surround sound")
    print("   • .spatialAudio - Spatial fallback for Dolby content")
    print("   • .lossyStereo - Compressed stereo audio")
    print("")
    print("🔍 Key Findings:")
    print("   • Local library tracks show limited variant info")
    print("   • Apple Music streaming tracks likely have richer variant data")
    print("   • AudioVariant enables bit-perfect audio quality detection")
    print("   • Perfect for MAC4MAC's sample rate switching needs!")
    print("")
    print("🚀 Next Steps for MAC4MAC:")
    print("   • Use AudioVariant to detect available quality options")
    print("   • Switch sample rates based on selected variant")
    print("   • Show users available audio quality choices")
}

func testAppleMusicTracks() async {
    print("\n🍎 Apple Music Catalog Search")
    print("-----------------------------")
    print("ℹ️ Skipping catalog search due to permission requirements")
    print("💡 AudioVariant data is primarily available for Apple Music streaming content")
    print("💡 Local library tracks may have limited variant information")
}

func testLibraryTracks() async {
    print("\n📚 Testing Library Tracks AudioVariants")
    print("---------------------------------------")

    do {
        // Fetch all songs from library using pagination
        var allSongs: [Song] = []
        var offset = 0
        let batchSize = 100

        print("📊 Fetching songs from library...")

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

            print("   📥 Retrieved \(allSongs.count) songs so far...")

            // Safety check: prevent infinite loops or excessive memory usage
            if allSongs.count > 50000 {
                print("⚠️  Reached 50,000 songs limit for safety. Use a more targeted approach for larger libraries.")
                break
            }
        }

        print("✅ Total songs retrieved: \(allSongs.count)")

        // Now process AudioVariants in chunks
        let chunkSize = 50
        var songVariants: [(song: Song, variants: SongVariants)] = []
        var tableContent = """
📋 AudioVariant Analysis Table
==============================

| Track | Lossless | High Res | Atmos | Spatial |
|-------|----------|----------|-------|---------|

"""

        print("\n🔍 Processing AudioVariants in chunks of \(chunkSize)...")

        for chunkStart in stride(from: 0, to: allSongs.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, allSongs.count)
            let chunk = Array(allSongs[chunkStart..<chunkEnd])

            print("   📊 Processing songs \(chunkStart + 1)-\(chunkEnd) of \(allSongs.count)...")

            for song in chunk {
                let variants = await getSongAudioVariants(song)
                songVariants.append((song: song, variants: variants))

                let trackName = "\(song.title) - \(song.artistName) - \(song.albumTitle ?? "Unknown Album")"
                let lossless = variants.lossless ? "✅" : "❌"
                let highRes = variants.highRes ? "✅" : "❌"
                let atmos = variants.atmos ? "✅" : "❌"
                let spatial = variants.spatial ? "✅" : "❌"
                tableContent += "| \(trackName) | \(lossless) | \(highRes) | \(atmos) | \(spatial) |\n"
            }
        }

        // Create playlists
        print("\n🎵 Creating playlists based on AudioVariants...")

        let highResSongs = songVariants.filter { $0.variants.highRes }.map { $0.song }
        let atmosSongs = songVariants.filter { $0.variants.atmos }.map { $0.song }

        print("   📊 Found \(highResSongs.count) High Res songs and \(atmosSongs.count) Atmos songs")

        // Debug: log the counts
        logToFile("Found \(highResSongs.count) High Res songs and \(atmosSongs.count) Atmos songs", filename: "mac4mac_playlist_debug.log")

        if !highResSongs.isEmpty {
            print("   📊 Creating playlist 'High Resolution Songs' with \(highResSongs.count) tracks...")
            await createPlaylistAndAddTracks(name: "High Resolution Songs", description: "Songs available in High Resolution Lossless format (24-bit/192 kHz)", songs: highResSongs)
        } else {
            print("   ℹ️ No High Resolution songs found, skipping playlist creation")
        }

        if !atmosSongs.isEmpty {
            print("   📊 Creating playlist 'Dolby Atmos Tracks' with \(atmosSongs.count) tracks...")
            await createPlaylistAndAddTracks(name: "Dolby Atmos Tracks", description: "Songs available in Dolby Atmos immersive audio format", songs: atmosSongs)
        } else {
            print("   ℹ️ No Dolby Atmos tracks found, skipping playlist creation")
        }

        // Validate playlist counts
        print("\n🔍 Validating playlist counts...")
        await validatePlaylistCounts(highResCount: highResSongs.count, atmosCount: atmosSongs.count)

        // Calculate counts for validation and summary
        let losslessCount = songVariants.filter { $0.variants.lossless }.count
        let highResCount = songVariants.filter { $0.variants.highRes }.count
        let atmosCount = songVariants.filter { $0.variants.atmos }.count
        let spatialCount = songVariants.filter { $0.variants.spatial }.count

        // Validation: Check playlist counts against expected counts
        print("\n🔍 Validating playlist counts...")
        await validatePlaylistCounts(highResCount: highResCount, atmosCount: atmosCount)

        tableContent += """

📊 Summary:
   • Total songs analyzed: \(songVariants.count)
   • Songs with Lossless: \(losslessCount)
   • Songs with High Res Lossless: \(highResCount)
   • Songs with Dolby Atmos: \(atmosCount)
   • Songs with Spatial Audio: \(spatialCount)

"""

        // Write to file
        let fileURL = URL(fileURLWithPath: "\(logDirectory)/AudioVariantAnalysis.md")
        try tableContent.write(to: fileURL, atomically: true, encoding: .utf8)
        print("\n✅ Analysis complete! Output written to \(logDirectory)/AudioVariantAnalysis.md")

    } catch {
        print("❌ Failed to access music library: \(error.localizedDescription)")
    }
}

struct SongVariants {
    let lossless: Bool
    let highRes: Bool
    let atmos: Bool
    let spatial: Bool
}

func getSongAudioVariants(_ song: Song) async -> SongVariants {
    do {
        let detailedSong = try await song.with([.audioVariants])
        if let audioVariants = detailedSong.audioVariants {
            let lossless = audioVariants.contains(.lossless)
            let highRes = audioVariants.contains(.highResolutionLossless)
            let atmos = audioVariants.contains(.dolbyAtmos)
            let spatial = audioVariants.contains(.spatialAudio)

            // Debug logging for ALL songs processed
            let sanitizedTitle = song.title.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "\\", with: "")
            let sanitizedArtist = song.artistName.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "\\", with: "")
            let debugMsg = "Song '\(sanitizedTitle)' by '\(sanitizedArtist)' has variants: lossless=\(lossless), highRes=\(highRes), atmos=\(atmos), spatial=\(spatial)"
            logToFile(debugMsg, filename: "mac4mac_variant_debug.log")

            return SongVariants(lossless: lossless, highRes: highRes, atmos: atmos, spatial: spatial)
        } else {
            // Debug: log when no variants are available
            let sanitizedTitle = song.title.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "\\", with: "")
            let sanitizedArtist = song.artistName.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "\\", with: "")
            let debugMsg = "Song '\(sanitizedTitle)' by '\(sanitizedArtist)' has NO audio variants available"
            logToFile(debugMsg, filename: "mac4mac_variant_debug.log")
            return SongVariants(lossless: false, highRes: false, atmos: false, spatial: false)
        }
    } catch {
        // Debug: log errors in variant loading
        let sanitizedTitle = song.title.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        let sanitizedArtist = song.artistName.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
        let debugMsg = "ERROR loading variants for '\(sanitizedTitle)' by '\(sanitizedArtist)': \(error.localizedDescription)"
        logToFile(debugMsg, filename: "mac4mac_variant_debug.log")
        return SongVariants(lossless: false, highRes: false, atmos: false, spatial: false)
    }
}

func createPlaylistAndAddTracks(name: String, description: String, songs: [Song]) async {
    print("   📝 Creating playlist '\(name)' using improved multi-strategy approach...")

    // First, create the playlist if it doesn't exist
    let createScript = """
    tell application "Music"
        if not (exists playlist "\(name)") then
            make new playlist with properties {name:"\(name)", description:"\(description)"}
        end if
    end tell
    """
    runAppleScript(createScript)

    // Use improved batch processing with better error handling
    let batchSize = 20 // Smaller batches for more control
    var totalProcessed = 0
    var totalAdded = 0
    var totalSkipped = 0

    print("   📤 Adding \(songs.count) tracks to playlist in batches of \(batchSize)...")

    for batchStart in stride(from: 0, to: songs.count, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, songs.count)
        let batch = Array(songs[batchStart..<batchEnd])

        print("   📦 Processing batch \(batchStart/batchSize + 1) (\(batchStart + 1)-\(batchEnd) of \(songs.count))...")

        var batchAdded = 0
        var batchSkipped = 0

        // Process each song individually with detailed error handling
        for song in batch {
            let result = await addSongToPlaylist(song, playlistName: name)
            if result {
                batchAdded += 1
            } else {
                batchSkipped += 1
            }
        }

        totalProcessed += batch.count
        totalAdded += batchAdded
        totalSkipped += batchSkipped

        print("   📊 Batch \(batchStart/batchSize + 1) complete: \(batchAdded) added, \(batchSkipped) skipped")
        logToFile("Batch \(batchStart/batchSize + 1): \(batchAdded) added, \(batchSkipped) skipped", filename: "mac4mac_playlist_debug.log")
    }

    print("   🎯 Playlist operation complete: \(totalAdded)/\(songs.count) tracks added (\(String(format: "%.1f", Double(totalAdded)/Double(songs.count)*100))% success rate)")
    logToFile("Playlist '\(name)' complete: \(totalAdded)/\(songs.count) added, \(totalSkipped) skipped", filename: "mac4mac_playlist_debug.log")
}

// Improved individual song addition with duplicate-first, add-fallback approach
func addSongToPlaylist(_ song: Song, playlistName: String) async -> Bool {
    // Mild sanitization like the original working version
    let title = song.title.replacingOccurrences(of: "\"", with: "")
        .replacingOccurrences(of: "'", with: "")
        .replacingOccurrences(of: "&", with: "and")
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "\\", with: "")
    let artist = song.artistName.replacingOccurrences(of: "\"", with: "")
        .replacingOccurrences(of: "'", with: "")
        .replacingOccurrences(of: "&", with: "and")
        .replacingOccurrences(of: "/", with: "")
        .replacingOccurrences(of: "\\", with: "")

    // Debug log the sanitization
    logToFile("DEBUG: Original title: '\(song.title)', Sanitized: '\(title)'", filename: "mac4mac_playlist_debug.log")
    logToFile("DEBUG: Original artist: '\(song.artistName)', Sanitized: '\(artist)'", filename: "mac4mac_playlist_debug.log")

    // Try multiple matching strategies with duplicate-first, add-fallback approach
    let addScript = """
    tell application "Music"
        if not (exists playlist "\(playlistName)") then
            make new playlist with properties {name:"\(playlistName)"}
        end if

        set targetPlaylist to playlist "\(playlistName)"

        -- FIRST: Check if song is already in playlist BEFORE doing anything else
        try
            set existingTracks to (tracks of targetPlaylist whose name contains "\(title)" and artist contains "\(artist)")
            if (count of existingTracks) > 0 then
                return "ALREADY_EXISTS"
            end if
        end try

        set trackAdded to false
        set errorMessage to ""

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
            logToFile("Song '\(title)' by '\(artist)' added to playlist (duplicate)", filename: "mac4mac_playlist_debug.log")
            return true
        } else if result.contains("SUCCESS_ADD") {
            logToFile("Song '\(title)' by '\(artist)' added to playlist (add)", filename: "mac4mac_playlist_debug.log")
            return true
        } else if result.contains("ALREADY_EXISTS") {
            logToFile("Song '\(title)' by '\(artist)' already exists in playlist", filename: "mac4mac_playlist_debug.log")
            return true // Count as success
        } else if result.contains("LOCAL_FILE") || result.contains("LOCAL_FILE_CANNOT_ADD") {
            logToFile("Song '\(title)' by '\(artist)' is a local file track - cannot add to playlist", filename: "mac4mac_playlist_debug.log")
            return false
        } else if result.contains("NOT_FOUND") {
            logToFile("Song '\(title)' by '\(artist)' has no tracks available at all", filename: "mac4mac_playlist_debug.log")
            return false
        } else if result.contains("DUPLICATE_ERROR") || result.contains("ADD_ERROR") {
            // Log the specific AppleScript error
            logToFile("ERROR: Song '\(title)' by '\(artist)' failed - \(result)", filename: "mac4mac_playlist_debug.log")
            return false
        } else {
            logToFile("UNKNOWN: Song '\(title)' by '\(artist)' result: \(result)", filename: "mac4mac_playlist_debug.log")
            return false
        }
    }

    return false
}

func runAppleScript(_ source: String) {
    print("Running AppleScript: \(source)")
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
        let output = String(data: data, encoding: .utf8) ?? ""
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        print("AppleScript result: '\(trimmedOutput)'")
    } catch {
        print("AppleScript error: \(error.localizedDescription)")
    }
}

func runAppleScriptWithResult(_ source: String) -> String? {
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
        print("AppleScript error: \(error.localizedDescription)")
        return nil
    }
}

func validatePlaylistCounts(highResCount: Int, atmosCount: Int) async {
    print("   📊 Expected: High Res = \(highResCount), Atmos = \(atmosCount)")
    
    // Get actual counts from playlists
    let highResCountScript = """
    tell application "Music"
        if exists playlist "High Resolution Songs" then
            return count of tracks of playlist "High Resolution Songs"
        else
            return 0
        end if
    end tell
    """
    
    let atmosCountScript = """
    tell application "Music"
        if exists playlist "Dolby Atmos Tracks" then
            return count of tracks of playlist "Dolby Atmos Tracks"
        else
            return 0
        end if
    end tell
    """
    
    let actualHighRes = runAppleScriptWithResult(highResCountScript).flatMap { Int($0) } ?? 0
    let actualAtmos = runAppleScriptWithResult(atmosCountScript).flatMap { Int($0) } ?? 0
    
    print("   📊 Actual: High Res = \(actualHighRes), Atmos = \(actualAtmos)")
    
    let highResMatch = actualHighRes == highResCount
    let atmosMatch = actualAtmos == atmosCount
    
    if highResMatch && atmosMatch {
        print("   ✅ Validation PASSED: All counts match!")
        logToFile("VALIDATION PASSED: High Res (\(actualHighRes)/\(highResCount)), Atmos (\(actualAtmos)/\(atmosCount))", filename: "mac4mac_playlist_debug.log")
    } else {
        print("   ❌ Validation FAILED: Counts don't match!")
        logToFile("VALIDATION FAILED: High Res (\(actualHighRes)/\(highResCount)), Atmos (\(actualAtmos)/\(atmosCount))", filename: "mac4mac_playlist_debug.log")
    }
}

// Keep the script running until the async task completes
RunLoop.main.run()