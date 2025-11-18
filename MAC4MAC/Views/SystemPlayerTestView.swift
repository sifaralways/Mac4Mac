import SwiftUI
import MusicKit

struct SystemPlayerTestView: View {
    @State private var isPlaying: Bool = false
    @State private var shuffleMode: Bool = false
    @State private var repeatModeIndex: Int = 0 // 0=none,1=one,2=all
    @State private var lastMessage: String = ""
    @State private var queueTracks: [[String: Any]] = []
    @State private var historyTracks: [[String: Any]] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("System Music Player Test")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Button(action: previous) {
                    Label("Previous", systemImage: "backward.fill")
                }

                Button(action: playPause) {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }

                Button(action: next) {
                    Label("Next", systemImage: "forward.fill")
                }
            }

            HStack(spacing: 12) {
                Button(action: toggleShuffle) {
                    Label("Shuffle", systemImage: shuffleMode ? "shuffle.circle.fill" : "shuffle")
                }

                Menu {
                    Button("None") { setRepeatIndex(0) }
                    Button("One") { setRepeatIndex(1) }
                    Button("All") { setRepeatIndex(2) }
                } label: {
                    Label("Repeat", systemImage: "repeat")
                }
            }

            Text(lastMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await refreshPlayerState()
                await fetchQueue()
                await fetchHistory()
            }
        }
    }

    // MARK: - Actions
    func playPause() {
        Task {
            do {
                if isPlaying {
                    try await MusicPlayerAdapter.shared.pause()
                    isPlaying = false
                    lastMessage = "Paused via adapter"
                } else {
                    try await MusicPlayerAdapter.shared.play()
                    isPlaying = true
                    lastMessage = "Played via adapter"
                }
            } catch {
                lastMessage = "Play/pause (adapter) error: \(error)"
            }
        }
    }

    func next() {
        Task {
            do {
                try await MusicPlayerAdapter.shared.skipToNext()
                lastMessage = "Skipped to next entry (adapter)"
            } catch {
                lastMessage = "Skip to next (adapter) error: \(error)"
            }
        }
    }

    func previous() {
        Task {
            do {
                try await MusicPlayerAdapter.shared.skipToPrevious()
                lastMessage = "Skipped to previous entry (adapter)"
            } catch {
                lastMessage = "Skip to previous (adapter) error: \(error)"
            }
        }
    }

    func toggleShuffle() {
        Task {
            // Adapter currently doesn't expose shuffle/repeat controls; toggle locally for test UI.
            shuffleMode.toggle()
            lastMessage = "(local) Shuffle set to \(shuffleMode ? "on" : "off")"
        }
    }

    // MARK: - Queue / History Fetching
    func fetchQueue() async {
        let urlString = "http://localhost:8989/queue?offset=0&limit=50"
        guard let url = URL(string: urlString) else { lastMessage = "Invalid queue URL"; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tracks = obj["tracks"] as? [[String: Any]] {
                queueTracks = tracks
                lastMessage = "Fetched queue: \(tracks.count) items"
            } else {
                lastMessage = "Unexpected queue response"
            }
        } catch {
            lastMessage = "Failed to fetch queue: \(error)"
        }
    }

    func fetchHistory() async {
        let urlString = "http://localhost:8989/history?limit=50"
        guard let url = URL(string: urlString) else { lastMessage = "Invalid history URL"; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = obj["items"] as? [[String: Any]] {
                historyTracks = items
                lastMessage = "Fetched history: \(items.count) items"
            } else {
                lastMessage = "Unexpected history response"
            }
        } catch {
            lastMessage = "Failed to fetch history: \(error)"
        }
    }

    func setRepeatIndex(_ idx: Int) {
        Task {
            repeatModeIndex = idx
            lastMessage = "(local) Repeat mode set (index=\(idx))"
        }
    }

    func refreshPlayerState() async {
    // No-op: adapter doesn't currently provide a state snapshot API. Inform user.
    lastMessage = "Adapter test view ready (no state snapshot)"
    }
}

#Preview {
    SystemPlayerTestView()
}
