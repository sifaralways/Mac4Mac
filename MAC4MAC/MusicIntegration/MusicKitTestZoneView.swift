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
            if selectedFunction == .fetchAudioVariants {
                TextField("MusicKit Song ID", text: $musicKitID)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
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
                                        let json = try JSONSerialization.jsonObject(with: data, options: [])
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
