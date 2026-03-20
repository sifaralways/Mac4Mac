# Mac4Mac Server API Specification
**Version:** 1.0  
**Last Updated:** December 11, 2025  
**Server:** Mac4Mac macOS Host Application

---

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [WebSocket API](#websocket-api)
4. [HTTP REST API](#http-rest-api)
5. [Service Discovery](#service-discovery)
6. [Authentication & Security](#authentication--security)
7. [Data Models](#data-models)
8. [Error Handling](#error-handling)
9. [Code Examples](#code-examples)

---

## Overview

Mac4Mac provides a comprehensive server infrastructure for remote control of macOS Music playback and audio monitoring. The system exposes two primary interfaces:

- **WebSocket Server (Port 8990)**: Real-time bidirectional communication for commands, track updates, and live audio configuration changes
- **HTTP Server (Port 8989)**: RESTful API for polling current state, artwork retrieval, and queue management

Both servers are automatically discovered via **Bonjour/mDNS** on the local network.

### Core Capabilities
- Real-time track change notifications with artwork
- Audio configuration monitoring (sample rate, bit depth, device)
- Remote playback control (play/pause, next/previous, seek, volume)
- Progress tracking with configurable update intervals
- Library-based song playback via MusicKit identifiers
- Queue/playlist retrieval with pagination
- Heartbeat/keepalive mechanism

---

## Architecture

### Components
```
┌─────────────────────────────────────────────────┐
│          Mac4Mac macOS Server                    │
├─────────────────────────────────────────────────┤
│                                                  │
│  ┌──────────────────┐    ┌──────────────────┐  │
│  │  WebSocket       │    │  HTTP REST       │  │
│  │  Server          │    │  Server          │  │
│  │  (Port 8990)     │    │  (Port 8989)     │  │
│  └────────┬─────────┘    └────────┬─────────┘  │
│           │                       │             │
│  ┌────────▼───────────────────────▼─────────┐  │
│  │     Mac4MacWebSocketServer               │  │
│  │     Mac4MacHTTPServer                    │  │
│  └────────┬─────────────────────────────────┘  │
│           │                                     │
│  ┌────────▼─────────────────────────────────┐  │
│  │   TrackChangeMonitor                     │  │
│  │   AudioManager                           │  │
│  │   MusicKit Integration                   │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Transport Layer
- **WebSocket**: Full-duplex, persistent connection for real-time events
- **HTTP**: Request-response for stateless queries and command execution
- **Bonjour**: Service advertisement as `_mac4mac._tcp` on local network

---

## WebSocket API

**Endpoint:** `ws://<server-ip>:8990`  
**Protocol:** WebSocket (RFC 6455)  
**Upgrade:** Standard HTTP WebSocket handshake

### Connection Flow
1. Client opens TCP connection to port 8990
2. Client sends WebSocket upgrade request with `Sec-WebSocket-Key`
3. Server responds with HTTP 101 Switching Protocols
4. Server sends initial `server_info` and `heartbeat` messages
5. Bidirectional message exchange begins

### Message Format
All WebSocket messages use JSON with the following structure:

```json
{
  "type": "message_type",
  "data": { /* type-specific payload */ },
  "timestamp": "2025-12-11T20:50:54.877Z"
}
```

---

### Message Types

#### 1. Server → Client Messages

##### `server_info`
**Description:** Sent immediately after WebSocket upgrade. Provides server capabilities and identity.

**Payload:**
```json
{
  "type": "server_info",
  "data": {
    "name": "John's MacBook Pro",
    "app": "Mac4Mac",
    "version": "1.0",
    "wsPort": 8990,
    "httpPort": 8989,
    "capabilities": [
      "track_updates",
      "audio_config",
      "remote_control",
      "artwork",
      "progress_tracking",
      "seek_control",
      "volume_control"
    ]
  },
  "timestamp": "2025-12-11T20:50:54.877Z"
}
```

**Fields:**
- `name` (string): macOS computer hostname
- `app` (string): Application identifier
- `version` (string): Server version
- `wsPort` (number): WebSocket port
- `httpPort` (number): HTTP REST port
- `capabilities` (array): List of supported features

---

##### `track_update`
**Description:** Broadcast when the current track changes. Includes full metadata and optional Base64-encoded artwork.

**Payload:**
```json
{
  "type": "track_update",
  "data": {
    "trackName": "Bohemian Rhapsody",
    "artist": "Queen",
    "album": "A Night at the Opera",
    "persistentID": "1234567890ABCDEF",
    "isPlaying": true,
    "hasArtwork": true,
    "artworkBase64": "/9j/4AAQSkZJRgABAQAA..."
  },
  "timestamp": "2025-12-11T20:50:54.877Z"
}
```

**Fields:**
- `trackName` (string): Track title
- `artist` (string): Artist name
- `album` (string): Album name
- `persistentID` (string|null): Music.app persistent library ID
- `isPlaying` (boolean): Current playback state
- `hasArtwork` (boolean): Indicates if artwork is included
- `artworkBase64` (string|null): Base64-encoded JPEG/PNG artwork (up to ~500KB)

**Notes:**
- Artwork is automatically included when track changes
- If artwork is unavailable, `artworkBase64` is `null`
- Persistent ID can be used for library-based song lookup

---

##### `audio_config_update`
**Description:** Sent when audio device configuration changes (sample rate, bit depth, or device switch).

**Payload:**
```json
{
  "type": "audio_config_update",
  "data": {
    "sampleRate": 192000.0,
    "bitDepth": 24,
    "deviceName": "Focusrite Scarlett 2i2",
    "sampleRateDisplay": "192.0 kHz",
    "bitDepthDisplay": "24-bit"
  },
  "timestamp": "2025-12-11T20:50:55.123Z"
}
```

**Fields:**
- `sampleRate` (number): Sample rate in Hz (44100, 48000, 96000, 192000, etc.)
- `bitDepth` (number): Bit depth (16, 24, 32)
- `deviceName` (string): Audio output device name
- `sampleRateDisplay` (string): Human-readable sample rate
- `bitDepthDisplay` (string): Human-readable bit depth

---

##### `play_state_update`
**Description:** Broadcast when playback state changes (play/pause/stop).

**Payload:**
```json
{
  "type": "play_state_update",
  "data": {
    "isPlaying": false
  },
  "timestamp": "2025-12-11T20:51:00.000Z"
}
```

**Fields:**
- `isPlaying` (boolean): Current playback state

---

##### `progress_update`
**Description:** Periodic updates of playback position, duration, and volume. Sent when progress tracking is enabled.

**Payload:**
```json
{
  "type": "progress_update",
  "data": {
    "position": 142.5,
    "duration": 354.0,
    "volume": 75,
    "isPlaying": true,
    "percentage": 40.25
  },
  "timestamp": "2025-12-11T20:51:01.500Z"
}
```

**Fields:**
- `position` (number): Current playback position in seconds
- `duration` (number): Total track duration in seconds
- `volume` (number): System volume (0-100)
- `isPlaying` (boolean): Playback state
- `percentage` (number): Playback progress percentage (0-100)

**Update Intervals:**
- **Playing:** 1 second
- **Paused:** 5 seconds (reduced frequency)

---

##### `remote_command_ack`
**Description:** Acknowledgment response for remote commands (especially `play_song`). Indicates success or failure.

**Payload (Success):**
```json
{
  "type": "remote_command_ack",
  "data": {
    "command": "play_song",
    "success": true,
    "details": "Now playing: Bohemian Rhapsody"
  },
  "timestamp": "2025-12-11T20:51:05.000Z"
}
```

**Payload (Failure):**
```json
{
  "type": "remote_command_ack",
  "data": {
    "command": "play_song",
    "success": false,
    "details": "Unable to resolve catalog ID: i.qQdgg1mUAKKo9x5"
  },
  "timestamp": "2025-12-11T20:51:05.123Z"
}
```

**Fields:**
- `command` (string): The command that was executed
- `success` (boolean): Whether the command succeeded
- `details` (string): Human-readable result or error message

---

##### `heartbeat`
**Description:** Server keepalive response. Echoes client heartbeat with server status.

**Payload:**
```json
{
  "type": "heartbeat",
  "data": {
    "status": "alive",
    "connections": 2,
    "serverTime": "2025-12-11T20:51:10.000Z",
    "progressTracking": true
  },
  "timestamp": "2025-12-11T20:51:10.000Z"
}
```

**Fields:**
- `status` (string): Server status ("alive")
- `connections` (number): Active WebSocket connections
- `serverTime` (string): ISO8601 server timestamp
- `progressTracking` (boolean): Whether progress tracking is active

---

#### 2. Client → Server Messages

##### `remote_command`
**Description:** Execute playback control commands.

**Supported Commands:**

###### `play_song`
**Purpose:** Play a specific song using MusicKit identifiers.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "play_song",
    "catalogID": "i.qQdgg1mUAKKo9x5",
    "playParametersID": "i.qQdgg1mUAKKo9x5",
    "persistentID": "1234567890ABCDEF",
    "title": "Å kom, å kom, Immanuel",
    "artist": "Iver Kleive & Knut Reiersrud",
    "album": "Natt i desember",
    "appleMusicURL": "https://music.apple.com/us/song/i.qQdgg1mUAKKo9x5"
  },
  "timestamp": "2025-12-11T20:51:15.000Z"
}
```

**Fields:**
- `command` (string): "play_song"
- `catalogID` (string|null): MusicKit catalog ID (preferred)
- `playParametersID` (string|null): MusicKit play parameters ID
- `persistentID` (string|null): Music.app library persistent ID
- `title` (string|null): Song title (fallback metadata)
- `artist` (string|null): Artist name
- `album` (string|null): Album name
- `appleMusicURL` (string|null): Apple Music URL for debugging

**Resolution Priority:**
1. `catalogID` → MusicKit catalog lookup
2. `playParametersID` → MusicKit identifier lookup
3. `persistentID` → Music.app library search
4. Error if no valid identifier

**Response:** `remote_command_ack` with success/failure

---

###### `play_pause`
**Purpose:** Toggle play/pause state.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "play_pause"
  }
}
```

---

###### `next_track`
**Purpose:** Skip to next track.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "next_track"
  }
}
```

---

###### `previous_track`
**Purpose:** Go to previous track.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "previous_track"
  }
}
```

---

###### `stop`
**Purpose:** Stop playback.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "stop"
  }
}
```

---

###### `start_progress_tracking`
**Purpose:** Enable periodic progress updates.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "start_progress_tracking"
  }
}
```

**Effect:** Server begins sending `progress_update` messages at configured interval.

---

###### `stop_progress_tracking`
**Purpose:** Disable progress updates.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "stop_progress_tracking"
  }
}
```

---

###### `set_progress_interval`
**Purpose:** Adjust progress update frequency.

**Payload:**
```json
{
  "type": "remote_command",
  "data": {
    "command": "set_progress_interval",
    "interval": 2.0
  }
}
```

**Fields:**
- `interval` (number): Update interval in seconds (0.1 - 5.0)

---

##### `seek_command`
**Description:** Seek to a specific playback position.

**Payload:**
```json
{
  "type": "seek_command",
  "data": {
    "position": 120.5
  }
}
```

**Fields:**
- `position` (number): Target position in seconds

**Effect:** Immediately seeks to position and broadcasts updated `progress_update`.

---

##### `volume_command`
**Description:** Set system volume.

**Payload:**
```json
{
  "type": "volume_command",
  "data": {
    "volume": 75
  }
}
```

**Fields:**
- `volume` (number): Target volume (0-100)

**Effect:** Sets Music.app sound volume (clamped to 0-100).

---

##### `heartbeat`
**Description:** Client keepalive ping. Server responds with `heartbeat` message.

**Payload:**
```json
{
  "type": "heartbeat",
  "data": {}
}
```

**Response:** Server `heartbeat` with status information.

---

## HTTP REST API

**Base URL:** `http://<server-ip>:8989`  
**Protocol:** HTTP/1.1

All endpoints return JSON unless otherwise specified. CORS is not configured (local network use only).

---

### Endpoints

#### `GET /`
**Description:** Welcome message and API overview.

**Response:**
```json
{
  "message": "Mac4Mac Server",
  "version": "1.0",
  "endpoints": [
    "/track",
    "/artwork",
    "/status",
    "/audio",
    "/progress",
    "/control",
    "/queue"
  ]
}
```

---

#### `GET /status`
**Description:** Server status and capabilities.

**Response:**
```json
{
  "status": "Mac4Mac Server Running",
  "port": 8989,
  "version": "1.0",
  "computerName": "John's MacBook Pro",
  "endpoints": {
    "/track": "Current track information with artwork",
    "/artwork": "Current track artwork (binary image data)",
    "/status": "Server status and capabilities",
    "/audio": "Audio device information",
    "/progress": "Current playback progress and volume",
    "/control": "Remote control commands",
    "/queue": "Current playlist queue with pagination"
  },
  "capabilities": {
    "track_updates": true,
    "audio_config": true,
    "remote_control": true,
    "artwork": true,
    "progress_tracking": true,
    "seek_control": true,
    "volume_control": true,
    "bonjour_discovery": true
  }
}
```

---

#### `GET /track`
**Description:** Current track metadata with artwork.

**Response:**
```json
{
  "trackName": "Bohemian Rhapsody",
  "artist": "Queen",
  "album": "A Night at the Opera",
  "persistentID": "1234567890ABCDEF",
  "sampleRate": 96000.0,
  "bitDepth": 24,
  "isPlaying": true,
  "audioDevice": "Focusrite Scarlett 2i2",
  "artworkBase64": "/9j/4AAQSkZJRgABAQAA...",
  "timestamp": "2025-12-11T20:51:20.000Z",
  "sampleRateDisplay": "96.0 kHz",
  "bitDepthDisplay": "24-bit",
  "hasArtwork": true
}
```

**Fields:** Same as WebSocket `track_update` plus audio configuration.

---

#### `GET /artwork`
**Description:** Binary artwork image for current track.

**Response:** JPEG or PNG image data (binary)  
**Content-Type:** `image/jpeg` or `image/png`

**Error (404):**
```json
{
  "error": "No artwork available for current track"
}
```

**Usage:** Suitable for `<img src="http://server:8989/artwork">` tags.

---

#### `GET /audio`
**Description:** Audio device configuration.

**Response:**
```json
{
  "currentDevice": "Focusrite Scarlett 2i2",
  "sampleRate": 96000.0,
  "bitDepth": 24,
  "sampleRateDisplay": "96.0 kHz",
  "bitDepthDisplay": "24-bit",
  "availableSampleRates": [44100, 48000, 96000, 192000]
}
```

---

#### `GET /progress`
**Description:** Current playback position and volume.

**Response:**
```json
{
  "position": 142.5,
  "duration": 354.0,
  "volume": 75,
  "isPlaying": true,
  "percentage": 40.25
}
```

---

#### `GET /control`
**Description:** Available remote control commands.

**Response:**
```json
{
  "commands": [
    "play_pause",
    "next_track",
    "previous_track",
    "stop"
  ],
  "seekSupported": true,
  "volumeSupported": true
}
```

---

#### `GET /queue?offset=0&limit=50`
**Description:** Current playlist queue with pagination.

**Query Parameters:**
- `offset` (number, default: 0): Starting index
- `limit` (number, default: 50, max: 100): Number of items to return

**Response:**
```json
{
  "totalCount": 200,
  "offset": 0,
  "limit": 50,
  "tracks": [
    {
      "index": 1,
      "name": "Bohemian Rhapsody",
      "artist": "Queen",
      "album": "A Night at the Opera",
      "persistentID": "1234567890ABCDEF"
    },
    {
      "index": 2,
      "name": "Another One Bites the Dust",
      "artist": "Queen",
      "album": "The Game",
      "persistentID": "FEDCBA0987654321"
    }
  ]
}
```

**Pagination Example:**
- Page 1: `?offset=0&limit=50`
- Page 2: `?offset=50&limit=50`
- Page 3: `?offset=100&limit=50`

---

#### `POST /control`
**Description:** Execute remote control commands via HTTP.

**Request Body:**
```json
{
  "command": "play_pause"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Command executed"
}
```

**Supported Commands:**
- `play_pause`
- `next_track`
- `previous_track`
- `stop`

---

## Service Discovery

Mac4Mac advertises its services via **Bonjour (mDNS/DNS-SD)** for automatic discovery on the local network.

### Service Type
- **Type:** `_mac4mac._tcp`
- **Domain:** `local.`

### Published Information
```
Service Name: Mac4Mac - <ComputerName>
Type: _mac4mac._tcp
Port: 8989 (HTTP) / 8990 (WebSocket)
TXT Record:
  - version=1.0
  - ws_port=8990
  - http_port=8989
  - capabilities=track_updates,audio_config,remote_control
```

### Discovery (Swift Example)
```swift
import Network

let browser = NWBrowser(for: .bonjour(type: "_mac4mac._tcp", domain: nil), using: .tcp)
browser.browseResultsChangedHandler = { results, changes in
    for result in results {
        if case .service(let name, let type, let domain, _) = result.endpoint {
            print("Found Mac4Mac server: \(name)")
        }
    }
}
browser.start(queue: .main)
```

---

## Authentication & Security

**Current Implementation:** No authentication is required. The server is designed for use on trusted local networks only.

**Security Considerations:**
- Server listens on all interfaces (`0.0.0.0`)
- No TLS/SSL encryption (plain HTTP/WebSocket)
- No API keys or tokens
- Suitable for home networks behind a firewall

**Recommendations for Production:**
- Implement token-based authentication
- Use TLS/WSS for encrypted transport
- Restrict to `localhost` or specific interfaces
- Add rate limiting for command endpoints

---

## Data Models

### TrackData
```swift
struct TrackData: Codable {
    let trackName: String
    let artist: String
    let album: String
    let persistentID: String?
    let sampleRate: Double
    let bitDepth: Int
    let isPlaying: Bool
    let audioDevice: String
    let artworkBase64: String?
    let timestamp: Date
}
```

### RemoteCommandData
```swift
struct RemoteCommandData {
    let command: String
    let catalogID: String?
    let playParametersID: String?
    let persistentID: String?
    let title: String?
    let artist: String?
    let album: String?
    let appleMusicURL: String?
}
```

### WebSocketMessage
```swift
struct WebSocketMessage {
    let type: MessageType
    let data: [String: Any]
    let timestamp: Date
}
```

---

## Error Handling

### HTTP Error Responses
All HTTP errors return JSON with the following structure:

```json
{
  "error": "Error description",
  "code": 404
}
```

**Common HTTP Status Codes:**
- `200 OK`: Request succeeded
- `400 Bad Request`: Invalid parameters
- `404 Not Found`: Resource unavailable
- `500 Internal Server Error`: Server failure

### WebSocket Error Responses
Errors are returned via `remote_command_ack` with `success: false`:

```json
{
  "type": "remote_command_ack",
  "data": {
    "command": "play_song",
    "success": false,
    "details": "Unable to resolve catalog ID: i.qQdgg1mUAKKo9x5"
  }
}
```

### MusicKit Resolution Errors
- `missingIdentifier`: No valid identifier provided
- `catalogLookupFailed`: Catalog ID not found
- `identifierLookupFailed`: Play parameters ID invalid
- `libraryLookupFailed`: Persistent ID not in library

**Common Causes:**
- Song not available in user's storefront
- Library item removed or unavailable
- Invalid MusicKit authorization
- Network connectivity issues

---

## Code Examples

### Swift WebSocket Client
```swift
import Foundation
import Network

class Mac4MacClient {
    private var connection: NWConnection?
    
    func connect(to host: String, port: UInt16 = 8990) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        
        connection = NWConnection(
            to: endpoint,
            using: .tcp
        )
        
        connection?.start(queue: .main)
        receiveMessages()
    }
    
    func sendCommand(_ command: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: command) else {
            return
        }
        
        let frame = createWebSocketFrame(data: jsonData)
        connection?.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
    
    func playSong(catalogID: String, title: String) {
        let command: [String: Any] = [
            "type": "remote_command",
            "data": [
                "command": "play_song",
                "catalogID": catalogID,
                "title": title
            ],
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        sendCommand(command)
    }
    
    private func receiveMessages() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data = data {
                self?.handleWebSocketFrame(data: data)
            }
            self?.receiveMessages()
        }
    }
    
    private func handleWebSocketFrame(data: Data) {
        // Parse WebSocket frame and extract JSON payload
        // Handle different message types
    }
}
```

### JavaScript WebSocket Client
```javascript
class Mac4MacClient {
    constructor(host, port = 8990) {
        this.ws = new WebSocket(`ws://${host}:${port}`);
        this.setupEventHandlers();
    }
    
    setupEventHandlers() {
        this.ws.onopen = () => {
            console.log('Connected to Mac4Mac server');
        };
        
        this.ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            this.handleMessage(message);
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }
    
    handleMessage(message) {
        switch(message.type) {
            case 'track_update':
                this.onTrackUpdate(message.data);
                break;
            case 'progress_update':
                this.onProgressUpdate(message.data);
                break;
            case 'remote_command_ack':
                this.onCommandAck(message.data);
                break;
        }
    }
    
    playSong(catalogID, title) {
        this.send({
            type: 'remote_command',
            data: {
                command: 'play_song',
                catalogID: catalogID,
                title: title
            },
            timestamp: new Date().toISOString()
        });
    }
    
    playPause() {
        this.send({
            type: 'remote_command',
            data: { command: 'play_pause' }
        });
    }
    
    seek(position) {
        this.send({
            type: 'seek_command',
            data: { position: position }
        });
    }
    
    send(message) {
        this.ws.send(JSON.stringify(message));
    }
}

// Usage
const client = new Mac4MacClient('192.168.1.100');
client.playSong('i.qQdgg1mUAKKo9x5', 'Bohemian Rhapsody');
```

### HTTP REST Client (cURL)
```bash
# Get current track
curl http://192.168.1.100:8989/track

# Get artwork
curl http://192.168.1.100:8989/artwork --output artwork.jpg

# Get queue (paginated)
curl "http://192.168.1.100:8989/queue?offset=0&limit=50"

# Execute command
curl -X POST http://192.168.1.100:8989/control \
  -H "Content-Type: application/json" \
  -d '{"command": "play_pause"}'
```

---

## Appendix

### MusicKit Identifier Types
- **Catalog ID:** MusicKit song identifier (e.g., `i.qQdgg1mUAKKo9x5`)
- **Play Parameters ID:** Alternative MusicKit identifier
- **Persistent ID:** Music.app library identifier (hexadecimal)

### Sample Rates Supported
- 44.1 kHz (CD quality)
- 48 kHz (DVD quality)
- 96 kHz (High-resolution)
- 192 kHz (Ultra high-resolution)

### Bit Depths Supported
- 16-bit (CD quality)
- 24-bit (High-resolution)
- 32-bit (Floating-point)

### Logging Levels
Mac4Mac uses a three-tier logging system:
- **Essential:** Critical events (track changes, errors)
- **Normal:** Important events (commands, updates)
- **Debug:** Detailed diagnostics

---

**End of Specification**
