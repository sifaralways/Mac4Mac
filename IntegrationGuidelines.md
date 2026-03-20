# Mac4Mac Server Extension Guidelines

This document describes what the iOS app (Mac4Mac Remote) is adding, what we expect from the macOS host (Mac4Mac server), and how to extend the existing Mac app so it can handle full library playback control.

## Goal
- Surface the user’s entire Apple Music library (Songs, Playlists, Albums, Artists) in the iOS client.
- Let the user tap any song/playlist/album and ask the Mac host to play it immediately on the system player.
- Keep the existing WebSocket command channel as the transport layer.
- Provide enough metadata (catalog ID, play parameters, persistent library ID) so the Mac can resolve and queue the correct track even if only a library ID exists.

## What the iOS app does
1. Exposes detail views for Songs, Playlists, and Albums inside `LibraryRootView`. Each song row uses `SongPlaybackCoordinator` to:
   - Derive the most precise identifier it can (candidate catalog ID, play parameters, persistent ID).
   - Build a `play_song` command payload with optional `catalogID`, `persistentID`, `playParametersID`, plus title/artist/album. It also emits a friendly Apple Music URL for debugging.
2. Sends the command over `EnhancedWebSocketPushManager.playSong(...)`, which creates a payload:

```json
{
  "type": "remote_command",
  "data": {
    "command": "play_song",
    "catalogID": "",              // optional
    "playParametersID": "",      // optional, often metadata hidden in the Song struct
    "persistentID": "",           // library ID from Music.app (if present)
    "title": "",
    "artist": "",
    "album": "",
    "appleMusicURL": ""
  },
  "timestamp": "2025-12-06T...Z"
}
```

## What Mac4Mac server needs to add
You already have a `RemoteCommand` handler for transport-level actions. Extend it with a handler for `play_song`:

1. Inspect the `data` payload for available identifiers. Prefer the catalog ID first, then `playParametersID`, and finally the persistent library ID.
2. Resolve the identifier to a `Song` (or `MusicKit` item) and instruct the system player to begin playback.
3. Respond with an acknowledgement that indicates success or failure so the iOS UI can show feedback.

### Suggested handler signature (Swift pseudocode)
```swift
struct RemoteCommandData: Codable {
    let command: String
    let catalogID: String?
    let playParametersID: String?
    let persistentID: String?
    let title: String?
    let artist: String?
    let album: String?
    let appleMusicURL: String?
}

func handlePlaySongCommand(_ data: RemoteCommandData) async throws -> RemoteCommandResponse {
    // 1. Resolve identifier
    let identifierToUse = data.catalogID ?? data.playParametersID ?? data.persistentID
    let queueDescriptor = try await createQueueDescriptor(for: identifierToUse)
    try await SystemMusicPlayer.shared.play(queueDescriptor)
    return .success(description: "Playing \(data.title ?? "song")")
}
```

## Resolution strategy on macOS
- If a catalog ID is provided (`catalogID`), use `MusicCatalogResourceRequest<Song>` or `MusicCatalogResourceRequest<Track>` to fetch the song and get its `playParams`.
- If only `playParametersID` exists, create `MusicPlayerQueueDescriptor` from that ID (since it often contains the PlayParameters needed for playback).
- As a last resort, open the user’s Music library via `MusicLibraryRequest`, match the `persistentID` (converted to `MusicItemID`), and build a queue descriptor from the library song.

## Response contract
- Emit a confirmation back to the iOS app through the same WebSocket protocol, for example:
  ```json
  {
    "type": "remote_command_ack",
    "data": {
      "command": "play_song",
      "success": true,
      "details": "Now playing: <title>"
    },
    "timestamp": "..."
  }
  ```
- If playback fails, set `success` to `false` and include an error message.

## Expected behaviors
- Maintain the existing rate-limited queue design so multiple taps during discovery or scans do not flood MusicKit.
- If the Mac cannot resolve the ID, return a failure reason so the iOS UI may surface `Try another song`.
- Continue streaming track/queue updates over the current `trackUpdate` channel so the player UI remains in sync.

## Next steps for the macOS developer
1. Extend the remote command parser/factory (`RemoteCommand` enum or equivalent) with the `play_song` type.
2. Implement the `handlePlaySongCommand` function that resolves identifiers and invokes MusicKit playback (using `SystemMusicPlayer` or `ApplicationMusicPlayer` depending on your architecture).
3. Return structured acknowledgements/errors for iOS to show.
4. Optionally add instrumentation logs (`playSong` requests received, identifier resolved, queue descriptor created).
5. Confirm that the existing WebSocket handshake/authentication still covers these commands and that `EnhancedWebSocketPushManager` on iOS receives the acknowledgment.

Let me know if you’d like a sample macOS handler stub or test payloads to verify the flow.