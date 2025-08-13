import MusicKit
import Foundation

@main
struct MusicKitTest {
    static func main() async {
        // Request authorization
        let status = await MusicAuthorization.request()
        print("Authorization status: \(status)")
        
        if status == .authorized {
            print("MusicKit authorized!")
            
            // Try to access current queue/player state
            let player = ApplicationMusicPlayer.shared
            print("Player state: \(player.state)")
            
            // Check if we can access queue
            if player.queue.currentEntry != nil {
                print("Current track available")
                print("Current entry: \(String(describing: player.queue.currentEntry))")
            } else {
                print("No current track")
            }
            
            // Try to get queue entries
            let entries = player.queue.entries
            print("Queue entries count: \(entries.count)")
            
            // List some queue entries if available
            for (index, entry) in entries.prefix(5).enumerated() {
                print("Entry \(index): \(String(describing: entry))")
            }
            
        } else {
            print("MusicKit not authorized: \(status)")
        }
    }
}
