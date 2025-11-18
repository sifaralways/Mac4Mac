import Foundation
import MusicKit

class MusicKitInspector {
    static let shared = MusicKitInspector()
    
    private init() {}
    
    func dumpAllAvailableInfo() async -> String {
        var dump = ""
        dump += "=== MusicKit Inspector - Complete Data Dump ===\n\n"
        
        // Check authorization
        let authStatus = await MusicAuthorization.request()
        dump += "Authorization Status: \(authStatus)\n\n"
        
        guard authStatus == .authorized else {
            dump += "❌ Not authorized - cannot access MusicKit data\n"
            return dump
        }
        
        // Get the player instance
        let player = ApplicationMusicPlayer.shared
        dump += "=== Application Music Player ===\n"
        dump += "Playback Status: \(player.state.playbackStatus)\n"
        dump += "Playback Time: \(player.playbackTime)\n"
        dump += "Repeat Mode: \(player.state.repeatMode.map(String.init(describing:)) ?? "nil")\n"
        dump += "Shuffle Mode: \(player.state.shuffleMode.map(String.init(describing:)) ?? "nil")\n\n"
        
        // Get queue information
        dump += "=== Queue Information ===\n"
        let queue = player.queue
        dump += "Queue entries count: \(queue.entries.count)\n"
        
        // Current entry
        if let currentEntry = queue.currentEntry {
            dump += "\n--- Current Entry ---\n"
            dump += await dumpQueueEntry(currentEntry, label: "CURRENT")
        } else {
            dump += "No current entry in queue\n"
        }
        
        // Get entries (up to 10 for performance)
        let entries = queue.entries.prefix(10)
        dump += "\n--- Queue Entries (first 10) ---\n"
        for (index, entry) in entries.enumerated() {
            dump += await dumpQueueEntry(entry, label: "Entry \(index)")
            dump += "\n"
        }
        
        return dump
    }
    
    private func dumpQueueEntry(_ entry: ApplicationMusicPlayer.Queue.Entry, label: String) async -> String {
        var dump = ""
        dump += "[\(label)]\n"
        
        // Use reflection to dump all available properties
        let mirror = Mirror(reflecting: entry)
        dump += "Entry Type: \(type(of: entry))\n"
        dump += "Entry Properties:\n"
        
        for (propertyName, value) in mirror.children {
            if let name = propertyName {
                dump += "  \(name): \(value)\n"
            }
        }
        
        // Try to access specific properties we know about
        dump += "\nDirect Property Access:\n"
        
        // Check if entry has item property (this varies by MusicKit version)
        if let item = extractItem(from: entry) {
            dump += await dumpMusicItem(item)
        } else {
            dump += "  No accessible item found in entry\n"
        }
        
        return dump
    }
    
    private func extractItem(from entry: ApplicationMusicPlayer.Queue.Entry) -> (any MusicItem)? {
        // Use reflection to find any MusicItem
        let mirror = Mirror(reflecting: entry)
        
        for (_, value) in mirror.children {
            // Check if this value conforms to MusicItem
            if let musicItem = value as? (any MusicItem) {
                return musicItem
            }
            
            // Also check nested objects
            let nestedMirror = Mirror(reflecting: value)
            for (_, nestedValue) in nestedMirror.children {
                if let musicItem = nestedValue as? (any MusicItem) {
                    return musicItem
                }
            }
        }
        
        return nil
    }
    
    private func dumpMusicItem(_ item: any MusicItem) async -> String {
        var dump = ""
        dump += "=== Music Item Details ===\n"
        dump += "Item Type: \(type(of: item))\n"
        dump += "ID: \(item.id)\n"
        
        // Use reflection to get all properties
        let mirror = Mirror(reflecting: item)
        for (propertyName, value) in mirror.children {
            if let name = propertyName {
                dump += "  \(name): \(value)\n"
            }
        }
        
        // Try common MusicItem properties
        if let song = item as? Song {
            dump += await dumpSong(song)
        } else {
            dump += "Item is not a Song type\n"
        }
        
        return dump
    }
    
    private func dumpSong(_ song: Song) async -> String {
        var dump = ""
        dump += "\n=== Song-Specific Properties ===\n"
        dump += "Title: \(song.title)\n"
        dump += "Artist Name: \(song.artistName)\n"
        dump += "Album Title: \(song.albumTitle ?? "nil")\n"
        dump += "Duration: \(song.duration ?? 0) seconds\n"
        dump += "Release Date: \(song.releaseDate?.description ?? "nil")\n"
        dump += "Genre Names: \(song.genreNames.joined(separator: ", "))\n"
        dump += "Composer Name: \(song.composerName ?? "nil")\n"
        dump += "Disc Number: \(song.discNumber ?? 0)\n"
        dump += "Track Number: \(song.trackNumber ?? 0)\n"
        
        // Artwork information
        if let artwork = song.artwork {
            dump += "Artwork Width: \(artwork.maximumWidth)\n"
            dump += "Artwork Height: \(artwork.maximumHeight)\n"
            dump += "Artwork Background Color: \(artwork.backgroundColor.map(String.init(describing:)) ?? "nil")\n"
            dump += "Artwork Primary Text Color: \(artwork.primaryTextColor.map(String.init(describing:)) ?? "nil")\n"
            dump += "Artwork Secondary Text Color: \(artwork.secondaryTextColor.map(String.init(describing:)) ?? "nil")\n"
            dump += "Artwork Tertiary Text Color: \(artwork.tertiaryTextColor.map(String.init(describing:)) ?? "nil")\n"
        } else {
            dump += "No artwork available\n"
        }
        
        // Use reflection to catch any additional properties
        dump += "\n=== All Song Properties (Reflection) ===\n"
        let mirror = Mirror(reflecting: song)
        for (propertyName, value) in mirror.children {
            if let name = propertyName {
                dump += "  \(name): \(value)\n"
            }
        }
        
        return dump
    }
}
