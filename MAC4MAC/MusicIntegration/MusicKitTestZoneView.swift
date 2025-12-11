import SwiftUI
import MusicKit

enum MusicKitFunction: String, CaseIterable, Identifiable {
    case requestAuthorization
    case fetchSongs
    case fetchAlbums
    case fetchPlaylists
    case fetchAllPlaylists
    case fetchPlaylistDetails
    case search
    case fetchAudioVariants
    case lookupByMusicItemID
    case lookupByPersistentID
    case playByMusicItemID
    case buildIDMappingDB
    case queryIDMappingDB
    case customAPICall

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .requestAuthorization: return "Request Authorization"
        case .fetchSongs: return "Fetch Songs"
        case .fetchAlbums: return "Fetch Albums"
        case .fetchPlaylists: return "Fetch Playlists (Legacy)"
        case .fetchAllPlaylists: return "Fetch All Playlists"
        case .fetchPlaylistDetails: return "Fetch Playlist Details by Name"
        case .search: return "Search"
        case .fetchAudioVariants: return "Fetch Audio Variants"
        case .lookupByMusicItemID: return "Lookup by MusicItemID"
        case .lookupByPersistentID: return "Lookup by PersistentID (Library Scan)"
        case .playByMusicItemID: return "Play by MusicItemID"
        case .buildIDMappingDB: return "🗄️ Build Song ID Mapping Database"
        case .queryIDMappingDB: return "🔍 Query ID Mapping Database"
        case .customAPICall: return "Custom API Call"
        }
    }
}

struct MusicKitTestZoneView: View {
    @State private var selectedFunction: MusicKitFunction = .fetchSongs
    @State private var searchTerm: String = ""
    @State private var jsonResult: String = ""
    @State private var error: String?
    @State private var isLoading: Bool = false
    @State private var musicKitID: String = ""
    @State private var customAPIName: String = ""
    @State private var customAPIRequest: String = "{\n  \"exampleKey\": \"exampleValue\"\n}"
    @State private var playlistName: String = ""
    @State private var forceRebuildDB: Bool = false
    @State private var savedFilePath: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MusicKit Testing Zone")
                .font(.title)
                .bold()
            Picker("Select Test", selection: $selectedFunction) {
                ForEach(MusicKitFunction.allCases) { function in
                    Text(function.displayName).tag(function)
                }
            }
            .pickerStyle(MenuPickerStyle())

            if selectedFunction == .search {
                TextField("Search Term", text: $searchTerm)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            if selectedFunction == .fetchPlaylistDetails {
                TextField("Playlist Name", text: $playlistName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            if selectedFunction == .fetchAudioVariants || selectedFunction == .lookupByMusicItemID || selectedFunction == .lookupByPersistentID || selectedFunction == .playByMusicItemID || selectedFunction == .queryIDMappingDB {
                TextField(selectedFunction == .lookupByPersistentID ? "PersistentID (e.g., i.ZOMRB6Lc488daYM)" : "MusicKit ID (e.g., i.qQdgg1mUAKKo9x5)", text: $musicKitID)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            if selectedFunction == .buildIDMappingDB {
                Toggle("Force Rebuild (ignore existing data)", isOn: $forceRebuildDB)
                    .toggleStyle(.switch)
                Text("⚠️ This will scan your entire library and may take 10-30 minutes.")
                    .font(.caption)
                    .foregroundColor(.orange)
                if !forceRebuildDB {
                    Text("💡 Will resume from existing checkpoint if available.")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            if selectedFunction == .customAPICall {
                TextField("API Endpoint or Function Name", text: $customAPIName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("JSON Request Body/Parameters:")
                TextEditor(text: $customAPIRequest)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Color.gray.opacity(0.3))
            }

            Button(action: invokeSelectedFunction) {
                Text(isLoading ? "Loading..." : "Invoke")
            }
            .disabled(isLoading)

            if let error = error {
                Text("Error: \(error)").foregroundColor(.red)
            }
            
            if let filePath = savedFilePath {
                HStack {
                    Text("Response saved to file")
                        .foregroundColor(.green)
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(filePath.path, inFileViewerRootedAtPath: filePath.deletingLastPathComponent().path)
                    }
                }
                .padding(.vertical, 4)
            }
            
            ScrollView {
                Text(jsonResult)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }

    func invokeSelectedFunction() {
        isLoading = true
        error = nil
        jsonResult = ""
        savedFilePath = nil
        Task {
            do {
                switch selectedFunction {
                                                case .fetchAllPlaylists:
                                                    let request = MusicLibraryRequest<Playlist>()
                                                    let response = try await request.response()
                                                    jsonResult = try encodeToJson(response.items.map { ["id": $0.id.rawValue, "name": $0.name] })
                                                case .fetchPlaylistDetails:
                                                    guard !playlistName.isEmpty else {
                                                        error = "Please enter a playlist name."
                                                        isLoading = false
                                                        return
                                                    }
                                                    let request = MusicLibraryRequest<Playlist>()
                                                    let response = try await request.response()
                                                    guard let playlist = response.items.first(where: { $0.name.lowercased() == playlistName.lowercased() }) else {
                                                        error = "Playlist not found."
                                                        isLoading = false
                                                        return
                                                    }
                                                    let detailed = try await playlist.with([.tracks])
                                                    struct PlaylistDetails: Encodable {
                                                        let id: String
                                                        let name: String
                                                        let tracks: [String]
                                                    }
                                                    let details = PlaylistDetails(
                                                        id: detailed.id.rawValue,
                                                        name: detailed.name,
                                                        tracks: detailed.tracks?.map { $0.title } ?? []
                                                    )
                                                    jsonResult = try encodeToJson(details)
                                case .customAPICall:
                                    // Try to parse the JSON request
                                    guard !customAPIName.isEmpty else {
                                        error = "Please enter an API endpoint or function name."
                                        isLoading = false
                                        return
                                    }
                                    guard let data = customAPIRequest.data(using: .utf8) else {
                                        error = "Invalid JSON encoding."
                                        isLoading = false
                                        return
                                    }
                                    do {
                                        _ = try JSONSerialization.jsonObject(with: data, options: [])
                                        // For demonstration, just echo the input. Real implementation would require custom MusicKit API logic.
                                        jsonResult = "API: \(customAPIName)\nRequest: \(customAPIRequest)\n\n(Simulated call. Implement actual MusicKit API logic here.)"
                                    } catch {
                                        self.error = "Invalid JSON: \(error.localizedDescription)"
                                    }
                                    isLoading = false
                                    return
                case .requestAuthorization:
                    let status = await MusicAuthorization.request()
                    jsonResult = try encodeToJson(["authorizationStatus": "\(status)"])
                case .fetchSongs:
                    let request = MusicLibraryRequest<Song>()
                    let response = try await request.response()
                    jsonResult = try encodeToJson(response.items.map { $0 })
                case .fetchAlbums:
                    let request = MusicLibraryRequest<Album>()
                    let response = try await request.response()
                    jsonResult = try encodeToJson(response.items.map { $0 })
                case .fetchPlaylists:
                    let request = MusicLibraryRequest<Playlist>()
                    let response = try await request.response()
                    jsonResult = try encodeToJson(response.items.map { $0 })
                case .search:
                    let request = MusicCatalogSearchRequest(term: searchTerm, types: [Song.self, Album.self, Playlist.self])
                    let response = try await request.response()
                    // Show MusicKit IDs in output
                    struct SearchResult: Encodable {
                        let id: String
                        let title: String
                        let artist: String?
                        let type: String
                    }
                    var results: [SearchResult] = []
                    for song in response.songs {
                        results.append(SearchResult(id: song.id.rawValue, title: song.title, artist: song.artistName, type: "Song"))
                    }
                    for album in response.albums {
                        results.append(SearchResult(id: album.id.rawValue, title: album.title, artist: album.artistName, type: "Album"))
                    }
                    for playlist in response.playlists {
                        results.append(SearchResult(id: playlist.id.rawValue, title: playlist.name, artist: nil, type: "Playlist"))
                    }
                    let simplified = try encodeToJson(["results": results])
                    let fullJson = try encodeToJson(response)
                    jsonResult = "Simplified Results:\n\(simplified)\n\nFull MusicKit Response:\n\(fullJson)"
                case .fetchAudioVariants:
                    struct AudioVariantResult: Encodable {
                        let title: String
                        let artist: String
                        let audioVariants: [String]
                    }
                    guard !musicKitID.isEmpty else {
                        error = "Please enter a MusicKit Song ID."
                        isLoading = false
                        return
                    }
                    let songID = MusicItemID(musicKitID)
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: songID)
                    let response = try await request.response()
                    guard let song = response.items.first else {
                        error = "Song not found for ID: \(musicKitID)"
                        isLoading = false
                        return
                    }
                    let detailed = try await song.with([.audioVariants])
                    let result = AudioVariantResult(
                        title: detailed.title,
                        artist: detailed.artistName,
                        audioVariants: detailed.audioVariants?.map { "\($0)" } ?? []
                    )
                    jsonResult = try encodeToJson(result)
                    
                case .lookupByMusicItemID:
                    guard !musicKitID.isEmpty else {
                        error = "Please enter a MusicKit ID."
                        isLoading = false
                        return
                    }
                    let identifier = MusicItemID(musicKitID)
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: identifier)
                    let response = try await request.response()
                    guard let song = response.items.first else {
                        error = "Song not found for ID: \(musicKitID)"
                        isLoading = false
                        return
                    }
                    // Fetch with all available properties
                    let detailed = try await song.with([.albums, .artists, .audioVariants, .genres])
                    
                    // Full dump of the MusicKit response
                    let fullJson = try encodeToJson(detailed)
                    
                    // Save to file if response is large (> 5KB)
                    if fullJson.count > 5000 {
                        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                        let fileName = "MusicKit_Lookup_\(musicKitID)_\(Date().timeIntervalSince1970).json"
                        let fileURL = downloadsURL.appendingPathComponent(fileName)
                        
                        try fullJson.write(to: fileURL, atomically: true, encoding: .utf8)
                        savedFilePath = fileURL
                        jsonResult = "Response saved to: \(fileURL.path)\n\nFile size: \(fullJson.count) bytes\n\nPreview (first 1000 characters):\n\(String(fullJson.prefix(1000)))..."
                    } else {
                        jsonResult = fullJson
                    }
                    
                case .lookupByPersistentID:
                    guard !musicKitID.isEmpty else {
                        error = "Please enter a PersistentID."
                        isLoading = false
                        return
                    }
                    
                    // Fetch entire library
                    let request = MusicLibraryRequest<Song>()
                    let startTime = Date()
                    let response = try await request.response()
                    let fetchDuration = Date().timeIntervalSince(startTime)
                    
                    // Search for the song
                    let searchStart = Date()
                    guard let song = response.items.first(where: { $0.id.rawValue == musicKitID }) else {
                        error = "Song not found in library with PersistentID: \(musicKitID)\nLibrary size: \(response.items.count) songs\nFetch time: \(String(format: "%.2f", fetchDuration))s"
                        isLoading = false
                        return
                    }
                    let searchDuration = Date().timeIntervalSince(searchStart)
                    
                    // Build full response with timing info
                    struct LibraryLookupResult: Encodable {
                        let timings: TimingInfo
                        let library: LibraryInfo
                        let song: SongInfo
                        
                        struct TimingInfo: Encodable {
                            let fetchLibrarySeconds: Double
                            let searchSeconds: Double
                            let totalSeconds: Double
                        }
                        
                        struct LibraryInfo: Encodable {
                            let totalSongs: Int
                            let searchedID: String
                        }
                        
                        struct SongInfo: Encodable {
                            let id: String
                            let title: String
                            let artist: String
                            let album: String?
                            let duration: Double?
                            let hasPlayParameters: Bool
                            let playParameters: String?
                            let genreNames: [String]
                        }
                    }
                    
                    let result = LibraryLookupResult(
                        timings: LibraryLookupResult.TimingInfo(
                            fetchLibrarySeconds: fetchDuration,
                            searchSeconds: searchDuration,
                            totalSeconds: fetchDuration + searchDuration
                        ),
                        library: LibraryLookupResult.LibraryInfo(
                            totalSongs: response.items.count,
                            searchedID: musicKitID
                        ),
                        song: LibraryLookupResult.SongInfo(
                            id: song.id.rawValue,
                            title: song.title,
                            artist: song.artistName,
                            album: song.albumTitle,
                            duration: song.duration,
                            hasPlayParameters: song.playParameters != nil,
                            playParameters: song.playParameters != nil ? String(describing: song.playParameters!) : nil,
                            genreNames: song.genreNames
                        )
                    )
                    
                    let fullJson = try encodeToJson(result)
                    
                    // Save to file if response is large (> 5KB)
                    if fullJson.count > 5000 {
                        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                        let fileName = "MusicKit_LibraryLookup_\(musicKitID)_\(Date().timeIntervalSince1970).json"
                        let fileURL = downloadsURL.appendingPathComponent(fileName)
                        
                        try fullJson.write(to: fileURL, atomically: true, encoding: .utf8)
                        savedFilePath = fileURL
                        jsonResult = "⏱️ Performance:\n  Library fetch: \(String(format: "%.2f", fetchDuration))s\n  Search: \(String(format: "%.2f", searchDuration))s\n  Total: \(String(format: "%.2f", fetchDuration + searchDuration))s\n\n📚 Library: \(response.items.count) songs scanned\n\n✅ Found: '\(song.title)' by '\(song.artistName)'\n\nFull response saved to: \(fileURL.path)\nFile size: \(fullJson.count) bytes\n\nPreview (first 1000 characters):\n\(String(fullJson.prefix(1000)))..."
                    } else {
                        jsonResult = "⏱️ Performance:\n  Library fetch: \(String(format: "%.2f", fetchDuration))s\n  Search: \(String(format: "%.2f", searchDuration))s\n  Total: \(String(format: "%.2f", fetchDuration + searchDuration))s\n\n📚 Library: \(response.items.count) songs scanned\n\n✅ Found: '\(song.title)' by '\(song.artistName)'\n\n" + fullJson
                    }
                    
                case .playByMusicItemID:
                    guard !musicKitID.isEmpty else {
                        error = "Please enter a MusicKit ID."
                        isLoading = false
                        return
                    }
                    let identifier = MusicItemID(musicKitID)
                    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: identifier)
                    let response = try await request.response()
                    guard let song = response.items.first else {
                        error = "Song not found for ID: \(musicKitID)"
                        isLoading = false
                        return
                    }
                    
                    // Play the song using ApplicationMusicPlayer (in-app playback)
                    // This is the only reliable way to play by catalog ID on macOS
                    // SystemMusicPlayer (Music.app control) is iOS-only
                    let player = ApplicationMusicPlayer.shared
                    player.queue = [song]
                    try await player.play()
                    
                    jsonResult = try encodeToJson([
                        "status": "Playing",
                        "id": song.id.rawValue,
                        "title": song.title,
                        "artist": song.artistName
                    ])
                    
                case .buildIDMappingDB:
                    let mode = forceRebuildDB ? "from scratch" : "with resume capability"
                    jsonResult = "Building Song ID Mapping Database \(mode)...\nThis may take several minutes depending on library size.\nCheck logs for progress.\n"
                    
                    try await SongIDMapper.shared.buildDatabase(forceRebuild: forceRebuildDB)
                    
                    let stats = SongIDMapper.shared.getStatistics()
                    jsonResult += "\n✅ Database Build Complete!\n\n"
                    jsonResult += "Statistics:\n"
                    jsonResult += "  Total Mappings: \(stats.totalMappings)\n"
                    jsonResult += "  Complete Records: \(stats.complete)\n"
                    jsonResult += "  Healthy Records: \(stats.healthy)\n"
                    jsonResult += "  With Catalog ID: \(stats.withCatalogID)\n"
                    jsonResult += "  With Legacy ID: \(stats.withLegacyID)\n"
                    if let lastUpdate = stats.lastUpdated {
                        jsonResult += "  Last Updated: \(lastUpdate)\n"
                    }
                    
                case .queryIDMappingDB:
                    guard !musicKitID.isEmpty else {
                        error = "Please enter a MusicKit ID to lookup."
                        isLoading = false
                        return
                    }
                    
                    let stats = SongIDMapper.shared.getStatistics()
                    if stats.totalMappings == 0 {
                        error = "Database is empty. Please build it first using '🗄️ Build Song ID Mapping Database'."
                        isLoading = false
                        return
                    }
                    
                    if let mapping = SongIDMapper.shared.lookupByMusicItemID(musicKitID) {
                        struct MappingResult: Encodable {
                            let musicItemID: String
                            let catalogID: String?
                            let legacyPersistentID: String?
                            let title: String?
                            let artist: String?
                            let album: String?
                            let isComplete: Bool
                            let isHealthy: Bool
                            let createdAt: Date
                            let updatedAt: Date
                        }
                        
                        let result = MappingResult(
                            musicItemID: mapping.musicItemID,
                            catalogID: mapping.catalogID,
                            legacyPersistentID: mapping.legacyPersistentID,
                            title: mapping.title,
                            artist: mapping.artist,
                            album: mapping.album,
                            isComplete: mapping.isComplete,
                            isHealthy: mapping.isHealthy,
                            createdAt: mapping.createdAt,
                            updatedAt: mapping.updatedAt
                        )
                        
                        jsonResult = try encodeToJson(result)
                    } else {
                        error = "No mapping found for ID: \(musicKitID)\n\nDatabase contains \(stats.totalMappings) mappings."
                        isLoading = false
                        return
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func encodeToJson<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "<encoding error>"
    }
}

// For preview/testing
struct MusicKitTestZoneView_Previews: PreviewProvider {
    static var previews: some View {
        MusicKitTestZoneView()
    }
}
