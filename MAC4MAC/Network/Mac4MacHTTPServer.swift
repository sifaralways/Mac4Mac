import Foundation
import Network
import MusicKit

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
            LogWriter.logEssential("HTTP server started on port \(port)")
        } catch {
            LogWriter.logEssential("Failed to start HTTP server: \(error)")
        }
    }
    
    func stopServer() {
        listener?.cancel()
        listener = nil
        LogWriter.logEssential("HTTP server stopped")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            
            if let error = error {
                LogWriter.logDebug("HTTP connection error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                let request = String(data: data, encoding: .utf8) ?? ""
                
                if request.contains("GET /track") {
                    self.sendTrackData(connection: connection)
                } else if request.contains("GET /artwork") {
                    self.sendArtwork(connection: connection)
                } else if request.contains("GET /status") {
                    self.sendStatus(connection: connection)
                } else if request.contains("GET /audio") {
                    self.sendAudioInfo(connection: connection)
                } else if request.contains("GET /progress") {
                    self.sendProgress(connection: connection)
                } else if request.contains("GET /control") {
                    self.sendControlInfo(connection: connection)
                } else if request.contains("GET /queue") {
                    self.sendQueueData(connection: connection, request: request)
                } else if request.contains("GET /history") {
                    self.sendHistoryData(connection: connection, request: request)
                } else if request.contains("POST /control") {
                    self.handleControlCommand(connection: connection, request: request)
                } else if request.contains("GET /") {
                    self.sendWelcome(connection: connection)
                } else {
                    self.sendNotFound(connection: connection)
                }
            } else {
                // No data received, close connection
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
                "/control": "Remote control commands",
                "/queue": "Current playlist queue with pagination"
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
    
    private func sendQueueData(connection: NWConnection, request: String) {
        // Parse query parameters for pagination
        let offset = extractQueryParameter(from: request, parameter: "offset") ?? "0"
        let limit = extractQueryParameter(from: request, parameter: "limit") ?? "50"
        
        guard let offsetInt = Int(offset), let limitInt = Int(limit) else {
            sendError(connection: connection, error: "Invalid offset or limit parameters")
            return
        }
        
        // Clamp values for safety
        let safeOffset = max(0, offsetInt)
        let safeLimit = max(1, min(100, limitInt)) // Max 100 items per request
        let endIndex = safeOffset + safeLimit
        
        let script = """
        tell application "Music"
            if it is running then
                try
                    if exists current playlist then
                        set queueTracks to {}
                        set totalCount to count of tracks of current playlist

                        -- Calculate end index without min function
                        set endIndex to \(endIndex)
                        if totalCount < endIndex then set endIndex to totalCount

                        -- Get requested range of tracks
                        repeat with i from \(safeOffset + 1) to endIndex
                            set currentTrack to track i of current playlist
                            set trackInfo to (name of currentTrack) & "|" & (artist of currentTrack) & "|" & (album of currentTrack) & "|" & (persistent ID of currentTrack)
                            set end of queueTracks to trackInfo
                        end repeat

                        -- Format response: totalCount,trackInfo1,trackInfo2,...
                        set result to (totalCount as string)
                        repeat with trackInfo in queueTracks
                            set result to result & "," & trackInfo
                        end repeat

                        return result
                    else
                        return "NO_PLAYLIST"
                    end if
                on error
                    return "ERROR"
                end try
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        // Run AppleScript and parse its comma-separated result
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if output == "NO_PLAYLIST" {
                sendNotFound(connection: connection, message: "No current playlist")
                return
            } else if output == "NOT_RUNNING" {
                sendError(connection: connection, error: "Music.app is not running")
                return
            } else if output == "ERROR" {
                sendError(connection: connection, error: "AppleScript error when fetching queue")
                return
            }

            // Output format: totalCount,track1Name|artist|album|persistentID,track2Name|...
            let components = output.components(separatedBy: ",")
            var tracks: [[String: Any]] = []
            var totalCount = 0
            if components.count > 0, let tc = Int(components[0]) {
                totalCount = tc
            }

            // Parse track data (skip first component which is totalCount)
            for i in 1..<components.count {
                let trackParts = components[i].components(separatedBy: "|")
                if trackParts.count >= 4 {
                    let track: [String: Any] = [
                        "name": trackParts[0],
                        "artist": trackParts[1],
                        "album": trackParts[2],
                        "persistentID": trackParts[3],
                        "queueIndex": safeOffset + (i - 1)
                    ]
                    tracks.append(track)
                }
            }

            let queueData = [
                "tracks": tracks,
                "pagination": [
                    "offset": safeOffset,
                    "limit": safeLimit,
                    "total": totalCount,
                    "hasMore": endIndex < totalCount
                ],
                "queueInfo": [
                    "currentPlaylistName": "Current Playlist",
                    "totalTracks": totalCount
                ]
            ] as [String: Any]

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: queueData)
                let response = createHTTPResponse(data: jsonData, contentType: "application/json")
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } catch {
                sendError(connection: connection, error: "Failed to create queue response")
            }
        } catch {
            sendError(connection: connection, error: "Failed to fetch queue data")
        }
    }

    private func sendHistoryData(connection: NWConnection, request: String) {
        // For POC purposes, return the last N items from the current playlist as history.
        // Accept a `limit` query parameter; default to 50.
        let limit = extractQueryParameter(from: request, parameter: "limit") ?? "50"
        guard let limitInt = Int(limit) else { sendError(connection: connection, error: "Invalid limit"); return }
        let safeLimit = max(1, min(200, limitInt))

        // AppleScript to read last N tracks from current playlist
        let script = """
        tell application "Music"
            if it is running then
                try
                    if exists current playlist then
                        set totalCount to count of tracks of current playlist
                        set startIndex to totalCount - \(safeLimit) + 1
                        if startIndex < 1 then set startIndex to 1
                        set historyTracks to {}
                        repeat with i from startIndex to totalCount
                            set t to track i of current playlist
                            set end of historyTracks to (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & (persistent ID of t)
                        end repeat
                        set result to (totalCount as string)
                        repeat with ti in historyTracks
                            set result to result & "," & ti
                        end repeat
                        return result
                    else
                        return "NO_PLAYLIST"
                    end if
                on error
                    return "ERROR"
                end try
            else
                return "NOT_RUNNING"
            end if
        end tell
        """

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if output == "NO_PLAYLIST" {
                sendNotFound(connection: connection, message: "No current playlist")
                return
            } else if output == "NOT_RUNNING" {
                sendError(connection: connection, error: "Music.app is not running")
                return
            } else if output == "ERROR" {
                sendError(connection: connection, error: "AppleScript error when fetching history")
                return
            }

            let components = output.components(separatedBy: ",")
            var tracks: [[String: Any]] = []
            var totalCount = 0
            if components.count > 0, let tc = Int(components[0]) { totalCount = tc }
            for i in 1..<components.count {
                let parts = components[i].components(separatedBy: "|")
                if parts.count >= 4 {
                    tracks.append([
                        "name": parts[0],
                        "artist": parts[1],
                        "album": parts[2],
                        "persistentID": parts[3]
                    ])
                }
            }

            let respObj: [String: Any] = [
                "total": totalCount,
                "items": tracks,
                "limit": safeLimit
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: respObj)
            let response = createHTTPResponse(data: jsonData, contentType: "application/json")
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        } catch {
            sendError(connection: connection, error: "Failed to fetch history data")
        }
    }
    
    private func extractQueryParameter(from request: String, parameter: String) -> String? {
        let lines = request.components(separatedBy: .newlines)
        guard let firstLine = lines.first else { return nil }
        
        let urlPattern = "GET /queue\\?([^ ]+)"
        let regex = try? NSRegularExpression(pattern: urlPattern)
        let range = NSRange(firstLine.startIndex..<firstLine.endIndex, in: firstLine)
        
        guard let match = regex?.firstMatch(in: firstLine, range: range),
              let queryRange = Range(match.range(at: 1), in: firstLine) else {
            return nil
        }
        
        let queryString = String(firstLine[queryRange])
        let parameters = queryString.components(separatedBy: "&")
        
        for param in parameters {
            let keyValue = param.components(separatedBy: "=")
            if keyValue.count == 2 && keyValue[0] == parameter {
                return keyValue[1].removingPercentEncoding
            }
        }
        
        return nil
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
            LogWriter.logDebug("Failed to fetch progress: \(error)")
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
                "stop": "Stop playbook",
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
        
    LogWriter.logNormal("HTTP remote command: \(command)")
        
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
        // Handle a small set of simple control commands via AppleScript.
        // For the new `play_persistent` command we directly attempt to find a track
        // in the local Music library by its persistent ID and play it.
        switch command {
        case "play_pause":
            let script = "tell application \"Music\" to playpause"
            return runAppleScript(script)
        case "next_track":
            let script = "tell application \"Music\" to next track"
            return runAppleScript(script)
        case "previous_track":
            let script = "tell application \"Music\" to previous track"
            return runAppleScript(script)
        case "stop":
            let script = "tell application \"Music\" to stop"
            return runAppleScript(script)
        case "seek":
            guard let position = parameters["position"] as? Double else {
                return (false, "Missing or invalid position parameter")
            }
            let script = "tell application \"Music\" to set player position to \(position)"
            return runAppleScript(script)
        case "volume":
            guard let volume = parameters["volume"] as? Int else {
                return (false, "Missing or invalid volume parameter")
            }
            let clampedVolume = max(0, min(100, volume))
            let script = "tell application \"Music\" to set sound volume to \(clampedVolume)"
            return runAppleScript(script)

        case "play_persistent", "play_by_persistent_id":
            // Accept either `persistentID` or `persistentId` keys for flexibility
            let pid = (parameters["persistentID"] as? String) ?? (parameters["persistentId"] as? String)
            guard let persistentID = pid, !persistentID.isEmpty else {
                return (false, "Missing persistentID parameter")
            }

            // Use a more descriptive AppleScript that returns a short result string we can inspect
            let script = """
            tell application "Music"
                if it is running then
                    try
                        set theTrack to (first track of library playlist 1 whose persistent ID is "\(persistentID)")
                        play theTrack
                        return "FOUND_AND_PLAYED"
                    on error errMsg number errNum
                        return "ERROR: " & errNum & " - " & errMsg
                    end try
                else
                    return "NOT_RUNNING"
                end if
            end tell
            """

            // Run script and examine result text to determine success
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if output.contains("FOUND_AND_PLAYED") {
                    return (true, "Played track with persistentID \(persistentID)")
                } else if output.contains("NOT_RUNNING") {
                    return (false, "Music.app is not running on this Mac")
                } else if output.starts(with: "ERROR:") {
                    return (false, "AppleScript error: \(output)")
                } else if task.terminationStatus == 0 {
                    // AppleScript returned something unexpected but exited 0
                    return (true, "AppleScript ran, result: \(output)")
                } else {
                    return (false, "Failed to run AppleScript: \(output)")
                }
            } catch {
                return (false, "Failed to execute AppleScript: \(error.localizedDescription)")
            }

        case "play_song":
            // Accept catalogID (preferred) and persistentID (fallback). Also accept additional metadata.
            let catalogID = parameters["catalogID"] as? String
            let playParametersID = parameters["playParametersID"] as? String
            let pid = (parameters["persistentID"] as? String) ?? (parameters["persistentId"] as? String)
            let title = parameters["title"] as? String
            let artist = parameters["artist"] as? String

            LogWriter.logNormal("HTTP play_song request: catalogID=\(catalogID ?? "(nil)") playParametersID=\(playParametersID ?? "(nil)") persistentID=\(pid ?? "(nil)") title=\(title ?? "(nil)") artist=\(artist ?? "(nil)")")

            // Centralized resolve-and-play via the adapter
            let sem = DispatchSemaphore(value: 0)
            var finalResult: (Bool, String?, String) = (false, nil, "not attempted")
            Task {
                finalResult = await MusicPlayerAdapter.shared.resolveAndPlay(catalogID: catalogID, playParametersID: playParametersID, persistentID: pid, title: title, artist: artist, album: parameters["album"] as? String)
                sem.signal()
            }
            let _ = sem.wait(timeout: .now() + 10)
            if finalResult.0 {
                return (true, finalResult.2)
            }

            // If adapter couldn't play, fallback to opening URL (non-blocking) and short AppleScript probe
            if let cat = catalogID, !cat.isEmpty {
                let appleMusicURLString = "https://music.apple.com/us/song/\(cat)"
                LogWriter.logNormal("Adapter failed to play; attempting non-blocking open URL fallback: \(appleMusicURLString) adapterMsg=\(finalResult.2)")
                let openProc = Process()
                openProc.launchPath = "/usr/bin/open"
                openProc.arguments = [appleMusicURLString]
                do {
                    try openProc.run()
                    return (true, "Opened URL via open command for id=\(cat) (adapterMsg=\(finalResult.2))")
                } catch {
                    LogWriter.logNormal("Failed to run open command: \(error). Falling back to limited-time AppleScript.")
                }
                // limited-time AppleScript probe (same safeScript as before)
                let safeScript = """
                with timeout of 5 seconds
                    tell application "Music"
                        try
                            open location "\(appleMusicURLString)"
                            delay 0.5
                            return "OPENED_URL"
                        on error errMsg
                            return "ERROR: " & errMsg
                        end try
                    end tell
                end timeout
                """
                let task2 = Process()
                task2.launchPath = "/usr/bin/osascript"
                task2.arguments = ["-e", safeScript]
                let pipe2 = Pipe()
                task2.standardOutput = pipe2
                task2.standardError = pipe2
                do {
                    try task2.run()
                    task2.waitUntilExit()
                    let out = String(data: pipe2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if task2.terminationStatus == 0 && out.trimmingCharacters(in: .whitespacesAndNewlines).contains("OPENED_URL") {
                        return (true, "Opened URL via AppleScript (short timeout) for id=\(cat)")
                    } else {
                        return (false, "Adapter failed and AppleScript fallback failed: \(finalResult.2) / \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }
                } catch {
                    return (false, "Adapter failed and AppleScript fallback exception: \(error) / adapterMsg=\(finalResult.2)")
                }
            }

            // If no catalogID or catalog play failed, fall back to persistentID AppleScript route
            if let persistentID = pid, !persistentID.isEmpty {
                // Reuse existing AppleScript-based play_persistent logic by delegating
                return executeControlCommand(command: "play_persistent", parameters: ["persistentID": persistentID])
            }

            // Last resort: attempt metadata fuzzy search if title+artist provided
            if let t = title, let a = artist {
                let sem = DispatchSemaphore(value: 0)
                var resultTuple: (Bool, String) = (false, "")
                Task {
                    do {
                        var searchReq = MusicCatalogSearchRequest(term: "\(t) \(a)", types: [Song.self])
                        searchReq.limit = 10
                        let resp = try await searchReq.response()
                        if let first = resp.songs.first {
                            do {
                                try await MusicPlayerAdapter.shared.insertAndPlaySong(first)
                                resultTuple = (true, "Played via metadata search: id=\(first.id.rawValue) via MusicPlayerAdapter")
                            } catch {
                                resultTuple = (false, "Metadata search/play error (Adapter): \(error)")
                            }
                        } else {
                            resultTuple = (false, "Metadata search returned no matches")
                        }
                    } catch {
                        resultTuple = (false, "Metadata search/play error: \(error)")
                    }
                    sem.signal()
                }
                let _ = sem.wait(timeout: .now() + 8)
                return resultTuple
            }

            return (false, "Missing catalogID and persistentID; cannot play")

        case "debug_song":
            // Collect provided fields
            let catalogID = parameters["catalogID"] as? String
            let pid = (parameters["persistentID"] as? String) ?? (parameters["persistentId"] as? String)
            let title = parameters["title"] as? String
            let artist = parameters["artist"] as? String

            print("HTTP debug_song request: catalogID=\(catalogID ?? "(nil)") persistentID=\(pid ?? "(nil)") title=\(title ?? "(nil)") artist=\(artist ?? "(nil)")")

            var responsePayload: [String: Any] = ["provided": parameters]

            // Helper for Mirror dump
            func mirrorDump(_ value: Any) -> String {
                var out = ""
                func recurse(_ val: Any, _ indent: String) {
                    let m = Mirror(reflecting: val)
                    out += "\(indent)Type: \(m.subjectType)\n"
                    for child in m.children {
                        let label = child.label ?? "?"
                        out += "\(indent)- \(label): \(child.value)\n"
                        recurse(child.value, indent + "  ")
                    }
                }
                recurse(value, "")
                return out
            }

            // Catalog lookup (if provided)
            if let cat = catalogID, !cat.isEmpty {
                let sem = DispatchSemaphore(value: 0)
                Task {
                    do {
                        let req = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(cat))
                        let resp = try await req.response()
                        var catalogInfo: [String: Any] = ["count": resp.items.count]
                        if let fetched = resp.items.first {
                            // Safe-ish extraction of common fields
                            let fetchedId = fetched.id.rawValue
                            let fetchedTitle = (fetched.title)
                            let fetchedArtist = (fetched.artistName)
                            catalogInfo["fetched_id"] = fetchedId
                            catalogInfo["fetched_title"] = fetchedTitle
                            catalogInfo["fetched_artist"] = fetchedArtist
                            catalogInfo["mirror"] = mirrorDump(fetched)
                            // Simple comparisons
                            catalogInfo["title_matches_provided"] = (title != nil) ? (title == fetchedTitle) : NSNull()
                            catalogInfo["artist_matches_provided"] = (artist != nil) ? (artist == fetchedArtist) : NSNull()
                        }
                        responsePayload["catalog_lookup"] = catalogInfo
                    } catch {
                        responsePayload["catalog_error"] = String(describing: error)
                    }
                    sem.signal()
                }
                _ = sem.wait(timeout: .now() + 8)
            }

            // Persistent ID lookup via AppleScript (if provided)
            if let persistent = pid, !persistent.isEmpty {
                let script = """
                tell application \"Music\"
                    if it is running then
                        try
                            set theTrack to (first track of library playlist 1 whose persistent ID is \"\(persistent)\")
                            set n to (name of theTrack)
                            set a to (artist of theTrack)
                            set al to (album of theTrack)
                            return n & "|" & a & "|" & al & "|" & (persistent ID of theTrack)
                        on error
                            return "ERROR: not found"
                        end try
                    else
                        return "NOT_RUNNING"
                    end if
                end tell
                """

                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = ["-e", script]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    responsePayload["persistent_lookup"] = out
                } catch {
                    responsePayload["persistent_error"] = String(describing: error)
                }
            }

            // Compare provided vs discovered at a high level
            var comparison: [String: Any] = [:]
            if let catalog = responsePayload["catalog_lookup"] as? [String: Any], let fetchedTitle = catalog["fetched_title"] as? String {
                comparison["title_match"] = (title != nil) ? (title == fetchedTitle) : NSNull()
            }
            if let catalog = responsePayload["catalog_lookup"] as? [String: Any], let fetchedArtist = catalog["fetched_artist"] as? String {
                comparison["artist_match"] = (artist != nil) ? (artist == fetchedArtist) : NSNull()
            }
            responsePayload["comparison"] = comparison

            // Serialize payload into JSON message string for return
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: responsePayload, options: [.prettyPrinted])
                let jsonStr = String(data: jsonData, encoding: .utf8) ?? "{}"
                return (true, jsonStr)
            } catch {
                return (false, "Failed to serialize debug payload: \(error)")
            }

        default:
            return (false, "Unknown command: \(command)")
        }
    }

    // Helper that runs a simple one-liner AppleScript and returns (success, message)
    private func runAppleScript(_ script: String) -> (Bool, String) {
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
                "/control": "Remote control commands (GET for info, POST for execution)",
                "/queue": "Current playlist queue with pagination (supports ?offset=0&limit=50)"
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
        let notFoundMessage = message ?? "Available endpoints: /track, /artwork, /status, /audio, /progress, /control, /queue"
        let notFound = """
        {
            "error": "Not Found",
            "message": "\(notFoundMessage)",
            "availableEndpoints": ["/track", "/artwork", "/status", "/audio", "/progress", "/control", "/queue"]
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
        
    print("HTTP server updated track: \(trackName) by \(artist)")
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
        
    print("HTTP server updated audio config: \(String(format: "%.1f", sampleRate / 1000.0)) kHz")
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
    }
    
    /// Get current track data - useful for debugging
    func getCurrentTrackData() -> TrackData {
        return currentTrackData
    }
}
