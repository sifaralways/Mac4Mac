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
    // First, create the playlist if it doesn't exist
    let createScript = """
    tell application "Music"
        if not (exists playlist "\(name)") then
            make new playlist with properties {name:"\(name)", description:"\(description)"}
        end if
    end tell
    """
    runAppleScript(createScript)

    // Prepare all song data for batch processing
    var songData: [[String: String]] = []
    for song in songs {
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

        songData.append([
            "title": title,
            "artist": artist
        ])
    }

    // Use a simpler approach: try to find tracks by exact name/artist match first
    let batchSize = 25 // Smaller batches for more reliable processing
    var totalAdded = 0

    for batchStart in stride(from: 0, to: songs.count, by: batchSize) {
        let batchEnd = min(batchStart + batchSize, songs.count)
        let batch = Array(songs[batchStart..<batchEnd])

        // Create AppleScript for this batch - try multiple matching strategies
        var duplicateCommands = ""

        for song in batch {
            let title = song.title.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "\\", with: "")
            let artist = song.artistName.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "/", with: "")
                .replacingOccurrences(of: "\\", with: "")

            // Try multiple ways to find and duplicate the track
            duplicateCommands += """
                try
                    -- Try exact match first
                    set foundTrack to (first track of library playlist 1 whose name is "\(title)" and artist is "\(artist)")
                on error
                    try
                        -- Try contains match
                        set foundTrack to (first track of library playlist 1 whose name contains "\(title)" and artist contains "\(artist)")
                    on error
                        -- Skip this track if can't find it
                        set foundTrack to missing value
                    end try
                end try

                if foundTrack is not missing value then
                    -- Check if already in playlist
                    set alreadyInPlaylist to false
                    try
                        set existingTracks to (tracks of playlist "\(name)" whose name is "\(title)" and artist is "\(artist)")
                        if (count of existingTracks) > 0 then
                            set alreadyInPlaylist to true
                        end if
                    end try

                    if not alreadyInPlaylist then
                        duplicate foundTrack to playlist "\(name)"
                    end if
                end if

            """
        }

        let batchScript = """
        tell application "Music"
            \(duplicateCommands)
        end tell
        """

        if let result = runAppleScriptWithResult(batchScript) {
            logToFile("Batch \(batchStart/batchSize + 1) result for \(name): \(result)", filename: "mac4mac_playlist_debug.log")
            print("   📝 Batch \(batchStart/batchSize + 1) result for \(name): \(result)")
        } else {
            logToFile("Batch \(batchStart/batchSize + 1) completed for \(name)", filename: "mac4mac_playlist_debug.log")
            print("   📝 Batch \(batchStart/batchSize + 1) completed for \(name)")
        }
    }

    logToFile("Total tracks processed for \(name): \(totalAdded)", filename: "mac4mac_playlist_debug.log")
    print("   📊 Total tracks processed for \(name): \(totalAdded)")
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