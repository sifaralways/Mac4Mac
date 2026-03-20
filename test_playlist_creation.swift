import MusicKit
import Foundation

Task {
    let status = await MusicAuthorization.request()
    guard status == .authorized else {
        print("❌ MusicKit not authorized")
        exit(1)
    }
    
    print("🔍 Testing MusicKit playlist creation capabilities...")
    
    // Try to create a playlist (this will likely fail)
    do {
        // MusicKit doesn't have playlist creation APIs
        // This is just to demonstrate the limitation
        print("❌ MusicKit cannot create user playlists")
        print("💡 Need Apple Music API for playlist creation")
    }
    
    // Check what we CAN do with existing playlists
    do {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 1
        let response = try await request.response()
        
        if let playlist = response.items.first {
            print("✅ Can read playlist: \(playlist.name)")
            
            // Try to get detailed playlist info
            let detailed = try await playlist.with([.tracks])
            print("✅ Can access playlist tracks: \(detailed.tracks?.count ?? 0) tracks")
        }
    } catch {
        print("❌ Error accessing playlists: \(error)")
    }
    
    exit(0)
}
RunLoop.main.run()
