# Song ID Mapping Database

## Overview

Implemented a persistent database system that maps between three different song identifier formats:

1. **MusicItemID** (`i.AWP4A35iL22qKbv`) - Universal, MusicKit format
2. **CatalogID** (`1234567890`) - Apple Music Store ID (universal for catalog songs)
3. **Legacy Persistent ID** (`A3B4C5D6E7F8G9H0`) - Device-specific iTunes/Music.app ID

## Implementation

### Core Components

#### `SongIDMapper.swift` (`MAC4MAC/Core/`)
- **Singleton class** managing all ID mapping operations
- **In-memory cache** with three dictionaries for fast lookups by any ID type
- **Disk persistence** using JSON format in Application Support directory
- **Thread-safe** using concurrent dispatch queue with barrier for writes

### Key Features

1. **Database Building**
   - Scans entire Music library using `MusicLibraryRequest<Song>()`
   - Extracts MusicItemID directly from `song.id.rawValue`
   - Checks `song.playParameters` to identify catalog songs (no API calls needed!)
   - Uses AppleScript to retrieve legacy persistent IDs by metadata matching
   - Progress logging every 100 songs
   - Safety limit of 50,000 songs
   - **Optimized**: No network requests during scan - all data from local library

2. **Fast Lookups**
   - `lookupByMusicItemID(_ id:)` - Find by universal MusicKit ID
   - `lookupByCatalogID(_ id:)` - Find by Apple Music Store ID
   - `lookupByLegacyID(_ id:)` - Find by device-specific iTunes ID
   - All O(1) constant time lookups from in-memory cache

3. **Persistence**
   - Automatic load on initialization
   - JSON format with metadata (version, timestamps)
   - Location: `~/Library/Application Support/MAC4MAC/SongIDMappings.json`
   - Pretty-printed and sorted for readability

4. **Statistics**
   - Total mappings count
   - Count with catalog IDs
   - Count with legacy IDs
   - Last updated timestamp

### UI Integration

Added two new functions to **MusicKitTestZoneView**:

#### `🗄️ Build Song ID Mapping Database`
- Triggers full library scan
- Shows progress in logs
- Displays statistics when complete
- ⚠️ Warning: May take 10-30 minutes for large libraries

#### `🔍 Query ID Mapping Database`
- Lookup song by MusicItemID
- Returns all three ID formats plus metadata
- Shows database statistics if no match found

## Usage

### Build Database
```swift
try await SongIDMapper.shared.buildDatabase()
```

### Query Database
```swift
// By MusicItemID
if let mapping = SongIDMapper.shared.lookupByMusicItemID("i.AWP4A35iL22qKbv") {
    print("Catalog ID: \(mapping.catalogID ?? "N/A")")
    print("Legacy ID: \(mapping.legacyPersistentID ?? "N/A")")
}

// By Catalog ID
if let mapping = SongIDMapper.shared.lookupByCatalogID("1234567890") {
    print("MusicItemID: \(mapping.musicItemID)")
}

// By Legacy ID
if let mapping = SongIDMapper.shared.lookupByLegacyID("A3B4C5D6E7F8G9H0") {
    print("MusicItemID: \(mapping.musicItemID)")
}
```

### Statistics
```swift
let stats = SongIDMapper.shared.getStatistics()
print("Total: \(stats.totalMappings)")
print("With Catalog: \(stats.withCatalogID)")
print("With Legacy: \(stats.withLegacyID)")
```

## Use Cases

### 1. AppleScript Playback
Convert universal MusicItemID to legacy ID for Music.app control:

```swift
if let mapping = SongIDMapper.shared.lookupByMusicItemID(musicItemID),
   let legacyID = mapping.legacyPersistentID {
    // Use AppleScript to play in Music.app
    let script = "tell application \"Music\" to play track id \(legacyID)"
    executeAppleScript(script)
}
```

### 2. Cross-Platform Sync
iOS app sends MusicItemID → Mac translates to legacy ID → Plays in Music.app

### 3. Catalog Lookup
Quickly find catalog ID for songs already in library without network request

### 4. Library Analysis
Identify which songs have catalog IDs (Apple Music) vs local-only

## Data Structure

```swift
struct SongIDMapping {
    let musicItemID: String        // Universal: i.AWP4A35iL22qKbv
    let catalogID: String?         // Apple Music: 1234567890 (if available)
    let legacyPersistentID: String? // Device-specific: A3B4C5D6E7F8G9H0
    let title: String?
    let artist: String?
    let album: String?
    let timestamp: Date            // When mapping was created
}
```

## Limitations

1. **Legacy IDs are device-specific** - Cannot share across Macs
2. **AppleScript matching by metadata** - May miss songs if metadata doesn't match exactly
3. **Large library scan time** - Initial build can take 10-30 minutes for 10,000+ songs
4. **Local songs without catalog IDs** - YouTube covers, imports, etc. won't have catalogID
5. **Requires rebuild after library changes** - Adding/removing songs needs DB refresh

## Future Enhancements

1. **Incremental updates** - Only scan changed songs instead of full rebuild
2. **Background refresh** - Automatic periodic DB updates
3. **Better AppleScript matching** - Fuzzy matching for difficult metadata
4. **Catalog ID extraction** - Improved detection from MusicKit song properties
5. **Export/Import** - Share mappings between devices (excluding legacy IDs)

## Files Modified

- **Created**: `MAC4MAC/Core/SongIDMapper.swift` (358 lines)
- **Modified**: `MAC4MAC/MusicIntegration/MusicKitTestZoneView.swift`
  - Added two new enum cases
  - Added UI elements for database operations
  - Added case handlers in switch statement

## Testing

Use MusicKitTestZoneView (⌘T in app):
1. Select "🗄️ Build Song ID Mapping Database"
2. Click "Invoke" and wait for completion
3. Select "🔍 Query ID Mapping Database"
4. Enter a MusicItemID (e.g., from your logs)
5. View all three ID formats for that song

## Performance

- **Build time**: ~0.1-0.3 seconds per song (AppleScript lookup only, no network calls)
- **Lookup time**: O(1) constant time from in-memory cache
- **Memory usage**: ~200 bytes per mapping × song count
- **Disk usage**: ~300-500 bytes per mapping in JSON
- **Network**: Zero API calls - all data from local library + AppleScript

For 10,000 songs:
- Build time: ~15-30 minutes (AppleScript is the bottleneck)
- Memory: ~2 MB
- Disk: ~3-5 MB
