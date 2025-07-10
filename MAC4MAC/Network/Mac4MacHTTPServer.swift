import Foundation
import Network

class Mac4MacHTTPServer {
    private var listener: NWListener?
    private let port: UInt16 = 8989
    
    // Enhanced track data structure matching Mac4Mac's capabilities
    private var currentTrackData = TrackData(
        trackName: "No Track Playing",
        artist: "Unknown Artist",
        album: "Unknown Album",
        persistentID: nil,
        sampleRate: 44100.0,
        bitDepth: 32,
        isPlaying: false,
        audioDevice: "Unknown Device",
        artworkBase64: nil
    )
    
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
        
        // Computed properties for convenience
        var sampleRateDisplay: String {
            return String(format: "%.1f kHz", sampleRate / 1000.0)
        }
        
        var bitDepthDisplay: String {
            return "\(bitDepth)-bit"
        }
        
        var hasArtwork: Bool {
            return artworkBase64 != nil
        }
        
        init(trackName: String, artist: String, album: String, persistentID: String?,
             sampleRate: Double, bitDepth: Int, isPlaying: Bool, audioDevice: String, artworkBase64: String?) {
            self.trackName = trackName
            self.artist = artist
            self.album = album
            self.persistentID = persistentID
            self.sampleRate = sampleRate
            self.bitDepth = bitDepth
            self.isPlaying = isPlaying
            self.audioDevice = audioDevice
            self.artworkBase64 = artworkBase64
            self.timestamp = Date()
        }
    }
    
    func startServer() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global())
            print("[Mac4Mac HTTP Server] Started on port \(port)")
        } catch {
            print("[Mac4Mac HTTP Server] Failed to start: \(error)")
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        print("[Mac4Mac HTTP Server] Stopped")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                let request = String(data: data, encoding: .utf8) ?? ""
                
                if request.contains("GET /track") {
                    self?.sendTrackData(connection: connection)
                } else if request.contains("GET /artwork") {
                    self?.sendArtwork(connection: connection)
                } else if request.contains("GET /status") {
                    self?.sendStatus(connection: connection)
                } else if request.contains("GET /audio") {
                    self?.sendAudioInfo(connection: connection)
                } else if request.contains("GET /progress") {
                    self?.sendProgress(connection: connection)
                } else if request.contains("GET /control") {
                    self?.sendControlInfo(connection: connection)
                } else if request.contains("POST /control") {
                    self?.handleControlCommand(connection: connection, request: request)
                } else if request.contains("GET /") {
                    self?.sendWelcome(connection: connection)
                } else {
                    self?.sendNotFound(connection: connection)
                }
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func sendTrackData(connection: NWConnection) {
        do {
            let jsonData = try JSONEncoder().encode(currentTrackData)
            let response = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendError(connection: connection, error: "Failed to encode track data")
        }
    }
    
    private func sendArtwork(connection: NWConnection) {
        if let artworkBase64 = currentTrackData.artworkBase64,
           let artworkData = Data(base64Encoded: artworkBase64) {
            
            // Try to determine the image format
            let contentType: String
            if artworkData.starts(with: [0xFF, 0xD8, 0xFF]) {
                contentType = "image/jpeg"
            } else if artworkData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                contentType = "image/png"
            } else {
                contentType = "application/octet-stream"
            }
            
            let response = createHTTPResponse(data: artworkData, contentType: contentType)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            sendNotFound(connection: connection, message: "No artwork available for current track")
        }
    }
    
    private func sendStatus(connection: NWConnection) {
        let status = [
            "status": "Mac4Mac Server Running",
            "port": port,
            "version": "1.0",
            "computerName": Host.current().localizedName ?? "Unknown Mac",
            "endpoints": [
                "/track": "Current track information with artwork",
                "/artwork": "Current track artwork (binary image data)",
                "/status": "Server status and capabilities",
                "/audio": "Audio device information",
                "/progress": "Current playback progress and volume",
                "/control": "Remote control commands"
            ],
            "capabilities": [
                "track_updates": true,
                "audio_config": true,
                "remote_control": true,
                "artwork": true,
                "progress_tracking": true,
                "seek_control": true,
                "volume_control": true,
                "bonjour_discovery": true
            ]
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: status)
            let response = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendError(connection: connection, error: "Failed to create status")
        }
    }
    
    private func sendAudioInfo(connection: NWConnection) {
        let audioInfo = [
            "currentDevice": currentTrackData.audioDevice,
            "sampleRate": currentTrackData.sampleRate,
            "bitDepth": currentTrackData.bitDepth,
            "sampleRateDisplay": currentTrackData.sampleRateDisplay,
            "bitDepthDisplay": currentTrackData.bitDepthDisplay,
            "availableSampleRates": AudioManager.getAvailableSampleRates()
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: audioInfo)
            let response = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendError(connection: connection, error: "Failed to create audio info")
        }
    }
    
    private func sendProgress(connection: NWConnection) {
        let script = """
        tell application "Music"
            if it is running then
                try
                    set isPlaying to (player state is playing)
                    if exists current track then
                        set pos to player position
                        set dur to duration of current track
                        set vol to sound volume
                        return (pos as string) & "," & (dur as string) & "," & (vol as string) & "," & (isPlaying as string)
                    else
                        return "0,0,50,false"
                    end if
                on error
                    return "0,0,50,false"
                end try
            else
                return "0,0,50,false"
            end if
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) {
                
                let components = output.components(separatedBy: ",")
                if components.count >= 4,
                   let position = Double(components[0]),
                   let duration = Double(components[1]),
                   let volume = Int(components[2]) {
                    
                    let isPlaying = components[3] == "true"
                    
                    let progressInfo = [
                        "position": position,
                        "duration": duration,
                        "volume": volume,
                        "isPlaying": isPlaying,
                        "percentage": duration > 0 ? (position / duration) * 100 : 0,
                        "positionDisplay": formatTime(position),
                        "durationDisplay": formatTime(duration)
                    ] as [String : Any]
                    
                    let jsonData = try JSONSerialization.data(withJSONObject: progressInfo)
                    let response = createHTTPResponse(data: jsonData, contentType: "application/json")
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }
            }
        } catch {
            print("[Mac4Mac HTTP Server] ❌ Failed to fetch progress: \(error)")
        }
        
        // Fallback response
        let fallback = [
            "position": 0,
            "duration": 0,
            "volume": 50,
            "isPlaying": false,
            "percentage": 0,
            "positionDisplay": "0:00",
            "durationDisplay": "0:00"
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: fallback)
            let response = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendError(connection: connection, error: "Failed to create progress response")
        }
    }
    
    private func sendControlInfo(connection: NWConnection) {
        let controlInfo = [
            "availableCommands": [
                "play_pause": "Toggle play/pause state",
                "next_track": "Skip to next track",
                "previous_track": "Go to previous track",
                "stop": "Stop playback",
                "seek": "Seek to position (requires position parameter)",
                "volume": "Set volume (requires volume parameter 0-100)"
            ],
            "usage": [
                "method": "POST",
                "content-type": "application/json",
                "body": "{'command': 'play_pause'} or {'command': 'seek', 'position': 30.5} or {'command': 'volume', 'volume': 75}"
            ]
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: controlInfo)
            let response = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendError(connection: connection, error: "Failed to create control info")
        }
    }
    
    private func handleControlCommand(connection: NWConnection, request: String) {
        // Extract JSON body from POST request
        let lines = request.components(separatedBy: "\r\n")
        guard let bodyStartIndex = lines.firstIndex(where: { $0.isEmpty }) else {
            sendError(connection: connection, error: "Invalid POST request format")
            return
        }
        
        let bodyLines = Array(lines.dropFirst(bodyStartIndex + 1))
        let body = bodyLines.joined(separator: "\r\n")
        
        guard let bodyData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let command = json["command"] as? String else {
            sendError(connection: connection, error: "Invalid JSON body or missing command")
            return
        }
        
        print("[Mac4Mac HTTP Server] 🎮 Received control command: \(command)")
        
        let result = executeControlCommand(command: command, parameters: json)
        
        let response = [
            "command": command,
            "result": result.success ? "success" : "error",
            "message": result.message,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: response)
            let httpResponse = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: httpResponse, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            sendError(connection: connection, error: "Failed to create response")
        }
    }
    
    private func executeControlCommand(command: String, parameters: [String: Any]) -> (success: Bool, message: String) {
        let script: String
        
        switch command {
        case "play_pause":
            script = "tell application \"Music\" to playpause"
        case "next_track":
            script = "tell application \"Music\" to next track"
        case "previous_track":
            script = "tell application \"Music\" to previous track"
        case "stop":
            script = "tell application \"Music\" to stop"
        case "seek":
            guard let position = parameters["position"] as? Double else {
                return (false, "Missing or invalid position parameter")
            }
            script = "tell application \"Music\" to set player position to \(position)"
        case "volume":
            guard let volume = parameters["volume"] as? Int else {
                return (false, "Missing or invalid volume parameter")
            }
            let clampedVolume = max(0, min(100, volume))
            script = "tell application \"Music\" to set sound volume to \(clampedVolume)"
        default:
            return (false, "Unknown command: \(command)")
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                return (true, "Command executed successfully")
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return (false, "AppleScript error: \(errorMessage)")
            }
        } catch {
            return (false, "Failed to execute command: \(error.localizedDescription)")
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private func sendWelcome(connection: NWConnection) {
        let computerName = Host.current().localizedName ?? "Unknown Mac"
        let welcome = """
        {
            "message": "Mac4Mac HTTP Server",
            "description": "Provides real-time Apple Music track and audio information with remote control capabilities",
            "computerName": "\(computerName)",
            "version": "1.0",
            "endpoints": {
                "/track": "Current track information including base64 artwork",
                "/artwork": "Current track artwork as binary image data",
                "/status": "Server status and capabilities",
                "/audio": "Audio device information",
                "/progress": "Current playback progress and volume",
                "/control": "Remote control commands (GET for info, POST for execution)"
            },
            "capabilities": {
                "track_updates": "Real-time track change detection",
                "audio_config": "Sample rate and device management",
                "remote_control": "Play/pause/next/previous commands",
                "artwork": "Album artwork extraction and delivery",
                "progress_tracking": "Real-time playback position",
                "seek_control": "Position scrubbing support",
                "volume_control": "Remote volume adjustment",
                "http_control": "REST API for remote commands"
            },
            "usage": {
                "get_requests": "All endpoints except /control support GET for information retrieval",
                "post_requests": "/control endpoint accepts POST with JSON body for command execution",
                "websocket": "Real-time updates available on port 8990",
                "bonjour": "Service discoverable as _mac4mac._tcp"
            },
            "websocket_port": 8990,
            "bonjour_service": "_mac4mac._tcp"
        }
        """
        
        let response = createHTTPResponse(data: welcome.data(using: .utf8) ?? Data(), contentType: "application/json")
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendNotFound(connection: NWConnection, message: String? = nil) {
        let notFoundMessage = message ?? "Available endpoints: /track, /artwork, /status, /audio, /progress, /control"
        let notFound = """
        {
            "error": "Not Found",
            "message": "\(notFoundMessage)",
            "availableEndpoints": ["/track", "/artwork", "/status", "/audio", "/progress", "/control"]
        }
        """
        
        let response = createHTTPResponse(data: notFound.data(using: .utf8) ?? Data(),
                                        contentType: "application/json", statusCode: "404 Not Found")
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendError(connection: NWConnection, error: String) {
        let errorResponse = """
        {
            "error": "Internal Server Error",
            "message": "\(error)",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """
        
        let response = createHTTPResponse(data: errorResponse.data(using: .utf8) ?? Data(),
                                        contentType: "application/json", statusCode: "500 Internal Server Error")
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func createHTTPResponse(data: Data, contentType: String, statusCode: String = "200 OK") -> Data {
        let response = """
        HTTP/1.1 \(statusCode)\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Cache-Control: no-cache\r
        Server: Mac4Mac/1.0\r
        \r
        
        """
        var responseData = response.data(using: .utf8) ?? Data()
        responseData.append(data)
        return responseData
    }
    
    // MARK: - Public Update Methods
    
    /// Update track information - call this from TrackChangeMonitor
    func updateTrackData(trackName: String, artist: String, album: String = "Unknown Album",
                        persistentID: String?, isPlaying: Bool, artworkBase64: String? = nil) {
        currentTrackData = TrackData(
            trackName: trackName,
            artist: artist,
            album: album,
            persistentID: persistentID,
            sampleRate: currentTrackData.sampleRate, // Keep existing sample rate
            bitDepth: currentTrackData.bitDepth,     // Keep existing bit depth
            isPlaying: isPlaying,
            audioDevice: currentTrackData.audioDevice, // Keep existing device
            artworkBase64: artworkBase64
        )
        
        let artworkStatus = artworkBase64 != nil ? "with artwork" : "without artwork"
        print("[Mac4Mac HTTP Server] Updated track: \(trackName) by \(artist) \(artworkStatus)")
    }
    
    /// Update audio configuration - call this from AudioManager
    func updateAudioConfig(sampleRate: Double, bitDepth: Int = 32, deviceName: String) {
        currentTrackData = TrackData(
            trackName: currentTrackData.trackName,
            artist: currentTrackData.artist,
            album: currentTrackData.album,
            persistentID: currentTrackData.persistentID,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            isPlaying: currentTrackData.isPlaying,
            audioDevice: deviceName,
            artworkBase64: currentTrackData.artworkBase64 // Keep existing artwork
        )
        
        print("[Mac4Mac HTTP Server] Updated audio config: \(String(format: "%.1f", sampleRate / 1000.0)) kHz, \(bitDepth)-bit, \(deviceName)")
    }
    
    /// Update only the playing state - useful for play/pause detection
    func updatePlayingState(isPlaying: Bool) {
        currentTrackData = TrackData(
            trackName: currentTrackData.trackName,
            artist: currentTrackData.artist,
            album: currentTrackData.album,
            persistentID: currentTrackData.persistentID,
            sampleRate: currentTrackData.sampleRate,
            bitDepth: currentTrackData.bitDepth,
            isPlaying: isPlaying,
            audioDevice: currentTrackData.audioDevice,
            artworkBase64: currentTrackData.artworkBase64 // Keep existing artwork
        )
        
        print("[Mac4Mac HTTP Server] Updated playing state: \(isPlaying ? "Playing" : "Paused")")
    }
    
    /// Get current track data - useful for debugging
    func getCurrentTrackData() -> TrackData {
        return currentTrackData
    }
}
