import Foundation
// Fix: Import LogWriter from Core
// Ensure LogWriter is in the same target. If not, use the correct import or move LogWriter to a shared location.
// If LogWriter is in the same target, just use:
// import LogWriter (if it's a module)
// Otherwise, no import is needed if it's in the same target.
import Network
import CommonCrypto
import MusicKit

// Use the project's `LogWriter` (it's a source file in the same target). Do not import a module here.

class Mac4MacWebSocketServer {
    // Helper to get AppleScript result as String
    private func executeAppleScriptWithResult(_ script: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            LogWriter.logEssential("Failed to execute AppleScript with result: \(error)")
            return nil
        }
    }
    private var listener: NWListener?
    
    // CRASH FIX: Thread-safe connections
    private let connectionsQueue = DispatchQueue(label: "com.mac4mac.connections", attributes: .concurrent)
    private var _connections: [WebSocketConnection] = []
    
    private let port: UInt16 = 8990
    private var progressTracker = ProgressTracker()
    static weak var shared: Mac4MacWebSocketServer?
    
    // Message types for communication
    enum MessageType: String, CaseIterable {
        case trackUpdate = "track_update"
        case audioConfigUpdate = "audio_config_update"
        case playStateUpdate = "play_state_update"
        case remoteCommand = "remote_command"
    case ack = "ack"
        case heartbeat = "heartbeat"
        case serverInfo = "server_info"
        case progressUpdate = "progress_update"
        case seekCommand = "seek_command"
        case volumeCommand = "volume_command"
    }
    
    class WebSocketConnection {
        let connection: NWConnection
        var isWebSocketUpgraded = false
        let id = UUID()
        
        init(connection: NWConnection) {
            self.connection = connection
        }
    }
    
    class ProgressTracker {
        private var isTracking = false
        private var lastPosition: Double = 0
        private var trackDuration: Double = 0
        private var timer: Timer?
        private var updateInterval: TimeInterval = 1.0
        private let timerQueue = DispatchQueue(label: "com.mac4mac.timer", qos: .utility)
        
        func startTracking() {
            timerQueue.sync {
                stopTrackingInternal() // Stop existing timer safely
                isTracking = true
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // CRASH FIX: Remove retain cycle
                    self.timer = Timer.scheduledTimer(withTimeInterval: self.updateInterval, repeats: true) { [weak self] _ in
                        self?.fetchAndBroadcastProgress()
                    }
                }
            }
            
                LogWriter.logNormal("Progress tracking started with \(updateInterval)s interval")
        }
        
        func stopTracking() {
            timerQueue.sync {
                stopTrackingInternal()
            }
        }
        
        private func stopTrackingInternal() {
            if let currentTimer = timer {
                DispatchQueue.main.async {
                    currentTimer.invalidate()
                }
                timer = nil
            }
            isTracking = false
        }
        
        func setUpdateInterval(_ interval: TimeInterval) {
            timerQueue.sync {
                updateInterval = max(0.1, min(5.0, interval)) // Clamp between 0.1 and 5 seconds
                if isTracking {
                    stopTrackingInternal()
                    DispatchQueue.main.async { [weak self] in
                        self?.startTracking()
                    }
                }
            }
        }
        
        var trackingStatus: Bool {
            return timerQueue.sync { isTracking }
        }
        
        var currentUpdateInterval: TimeInterval {
            return timerQueue.sync { updateInterval }
        }
        
        // CRASH FIX: Add fetchAndBroadcastProgress method to avoid external dependency
        private func fetchAndBroadcastProgress() {
            Mac4MacWebSocketServer.shared?.fetchAndBroadcastProgress()
        }
    }
    
    struct WebSocketMessage {
        let type: MessageType
        let data: [String: Any]
        let timestamp: Date
        
        init(type: MessageType, data: [String: Any] = [:]) {
            self.type = type
            self.data = data
            self.timestamp = Date()
        }
        
        func toJSON() -> Data? {
            do {
                var dict: [String: Any] = [
                    "type": type.rawValue,
                    "timestamp": ISO8601DateFormatter().string(from: timestamp)
                ]
                dict["data"] = data
                return try JSONSerialization.data(withJSONObject: dict)
            } catch {
                LogWriter.logEssential("Failed to serialize WebSocket message: \(error)")
                return nil
            }
        }
    }

    // MARK: - Metadata matching helpers
    private func normalizeString(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove parenthesis content: (From "..."), (Live), etc.
        out = out.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        // Replace common conjunction symbols
        out = out.replacingOccurrences(of: "&", with: "and")
        // Remove punctuation
        out = out.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: " ")
        // Remove duplicate whitespace
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Diacritic insensitive
        out = out.folding(options: .diacriticInsensitive, locale: .current)
        return out.lowercased()
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }
        var v0 = Array(0...m)
        var v1 = Array(repeating: 0, count: m + 1)
        for i in 0..<n {
            v1[0] = i + 1
            for j in 0..<m {
                let cost = aChars[i] == bChars[j] ? 0 : 1
                v1[j+1] = min(v1[j] + 1, v0[j+1] + 1, v0[j] + cost)
            }
            v0 = v1
        }
        return v0[m]
    }

    private func similarityScore(_ s1: String, _ s2: String) -> Double {
        let a = normalizeString(s1)
        let b = normalizeString(s2)
        if a.isEmpty && b.isEmpty { return 1.0 }
        let d = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        if maxLen == 0 { return 1.0 }
        return 1.0 - (Double(d) / Double(maxLen))
    }

    private func metadataSearchAndPlay(title: String, artist: String, album: String?, wsConnection: WebSocketConnection) async throws -> (played: Bool, resolvedID: String?, confidence: Double) {
        // Build search term candidates (prefer more specific terms first)
        var terms: [String] = []
        let base = "\(title) \(artist)"
        terms.append(base)
        if let album = album, !album.isEmpty {
            terms.append("\(title) \(artist) \(album)")
            terms.append("\(title) \(album)")
        }
        terms.append(title)
        terms.append(artist)

        var best: (song: Song, confidence: Double)? = nil
        let maxPerTerm = 25

        for term in terms {
                LogWriter.logDebug("metadataSearchAndPlay: searching term='\(term)'")
            var searchReq = MusicCatalogSearchRequest(term: term, types: [Song.self])
            searchReq.limit = maxPerTerm
            let resp = try await searchReq.response()
            LogWriter.logDebug("metadataSearchAndPlay: term='\(term)' -> returned candidates=\(resp.songs.count)")

            var bestForThisTerm: (song: Song, confidence: Double)? = nil
            var idx = 0
            for candidate in resp.songs {
                idx += 1
                // Compute matching heuristics
                let titleScore = similarityScore(title, candidate.title)
                let artistScore = similarityScore(artist, candidate.artistName)
                var albumScore: Double = 0.0
                if let album = album {
                    albumScore = similarityScore(album, candidate.albumTitle ?? "")
                }
                // Combine weights: title(0.5), artist(0.35), album(0.15)
                var score = titleScore * 0.5 + artistScore * 0.35 + albumScore * 0.15
                // Slight boost for exact matches
                if normalizeString(candidate.title) == normalizeString(title) { score += 0.05 }
                if normalizeString(candidate.artistName) == normalizeString(artist) { score += 0.03 }

                // Log promising candidates (or the first few)
                if score >= 0.25 || idx <= 3 {
                    let msg = String(format: "candidate[%d] id=%@ title='%@' artist='%@' album='%@' scores: title=%.3f artist=%.3f album=%.3f combined=%.3f", idx, candidate.id.rawValue, candidate.title, candidate.artistName, candidate.albumTitle ?? "", titleScore, artistScore, albumScore, score)
                    LogWriter.logDebug(msg)
                }

                if bestForThisTerm == nil || score > bestForThisTerm!.confidence {
                    bestForThisTerm = (candidate, score)
                }
            }

            if let foundTermBest = bestForThisTerm {
                let msg = String(format: "best for term='%@' -> id=%@ title='%@' artist='%@' combined=%.3f", term, foundTermBest.song.id.rawValue, foundTermBest.song.title, foundTermBest.song.artistName, foundTermBest.confidence)
                LogWriter.logDebug(msg)
                if best == nil || foundTermBest.confidence > best!.confidence {
                    best = foundTermBest
                }
            } else {
                LogWriter.logDebug("metadataSearchAndPlay: no candidates for term='\(term)'")
            }

            // If we found a very confident match, stop early
            if let found = best, found.confidence > 0.6 {
                break
            }
        }

            if let found = best {
            // Accept slightly lower score if album strongly matches
            let acceptThreshold = 0.45
            LogWriter.logDebug(String(format: "metadataSearchAndPlay: best overall -> id=%@ title='%@' artist='%@' confidence=%.3f", found.song.id.rawValue, found.song.title, found.song.artistName, found.confidence))
            if found.confidence >= acceptThreshold {
                do {
                    try await MusicPlayerAdapter.shared.insertAndPlaySong(found.song)
                    return (true, found.song.id.rawValue, found.confidence)
                } catch {
                    LogWriter.logDebug("metadataSearchAndPlay: adapter play failed: \(error)")
                    return (false, nil, 0.0)
                }
                } else {
                LogWriter.logDebug(String(format: "metadataSearchAndPlay: best candidate confidence %.3f below acceptThreshold %.3f", found.confidence, 0.45))
            }
        } else {
            LogWriter.logDebug("metadataSearchAndPlay: no match found across all terms")
        }
        return (false, nil, 0.0)
    }
    
    // CRASH FIX: Thread-safe connections access
    private var connections: [WebSocketConnection] {
        return connectionsQueue.sync { _connections }
    }
    
    private func addConnection(_ connection: WebSocketConnection) {
        connectionsQueue.async(flags: .barrier) { [weak self] in
            self?._connections.append(connection)
        }
    }
    
    private func removeConnection(_ wsConnection: WebSocketConnection) {
        connectionsQueue.async(flags: .barrier) { [weak self] in
            self?._connections.removeAll { $0.id == wsConnection.id }
        }
        // CRASH FIX: Cancel on separate queue
        DispatchQueue.global().async {
            wsConnection.connection.cancel()
        }
    LogWriter.logDebug("Removed WebSocket connection. Total: \(connections.count)")
    }
    
    func startServer() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: .global())
            Mac4MacWebSocketServer.shared = self
            LogWriter.logEssential("WebSocket server started on port \(port)")
        } catch {
            LogWriter.logEssential("Failed to start WebSocket server: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let wsConnection = WebSocketConnection(connection: connection)
        addConnection(wsConnection)
        connection.start(queue: .global())
        
    LogWriter.logDebug("New WebSocket connection. Total: \(connections.count)")
        
        // Start receiving data for WebSocket handshake
        receiveData(from: wsConnection)
    }
    
    private func receiveData(from wsConnection: WebSocketConnection) {
        // CRASH FIX: Add weak references
        wsConnection.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak wsConnection] data, _, isComplete, error in
            
            guard let self = self, let wsConnection = wsConnection else { return }
            
            if let error = error {
                LogWriter.logDebug("WebSocket receive error: \(error)")
                self.removeConnection(wsConnection)
                return
            }
            
            if let data = data, !data.isEmpty {
                if !wsConnection.isWebSocketUpgraded {
                    self.handleWebSocketHandshake(data: data, wsConnection: wsConnection)
                } else {
                    self.handleWebSocketFrame(data: data, wsConnection: wsConnection)
                }
            }
            
            if isComplete {
                self.removeConnection(wsConnection)
                return
            }
            
            // Continue receiving
            self.receiveData(from: wsConnection)
        }
    }
    
    private func handleWebSocketHandshake(data: Data, wsConnection: WebSocketConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            removeConnection(wsConnection)
            return
        }
        
        // Parse WebSocket handshake
        let lines = request.components(separatedBy: "\r\n")
        var webSocketKey: String?
        var isWebSocketUpgrade = false
        var isConnectionUpgrade = false
        
        for line in lines {
            let lowercaseLine = line.lowercased()
            if lowercaseLine.starts(with: "sec-websocket-key:") {
                webSocketKey = String(line.dropFirst(18).trimmingCharacters(in: .whitespaces))
            } else if lowercaseLine.starts(with: "upgrade:") && lowercaseLine.contains("websocket") {
                isWebSocketUpgrade = true
            } else if lowercaseLine.starts(with: "connection:") && lowercaseLine.contains("upgrade") {
                isConnectionUpgrade = true
            }
        }
        
        guard let key = webSocketKey, isWebSocketUpgrade, isConnectionUpgrade else {
            removeConnection(wsConnection)
            return
        }
        
        // Generate WebSocket accept key
        let acceptKey = generateWebSocketAcceptKey(key: key)
        
        // Send WebSocket handshake response
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r

        """
        
        if let responseData = response.data(using: .utf8) {
            // CRASH FIX: Add weak references in completion
            wsConnection.connection.send(content: responseData, completion: .contentProcessed { [weak self, weak wsConnection] error in
                guard let self = self, let wsConnection = wsConnection else { return }
                
                if let error = error {
                    LogWriter.logDebug("Failed to send WebSocket handshake: \(error)")
                    self.removeConnection(wsConnection)
                } else {
                    wsConnection.isWebSocketUpgraded = true
                    LogWriter.logDebug("WebSocket connection upgraded successfully")
                    
                    // Send initial messages
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self, weak wsConnection] in
                        guard let self = self, let wsConnection = wsConnection else { return }
                        self.sendServerInfo(to: wsConnection)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self, weak wsConnection] in
                        guard let self = self, let wsConnection = wsConnection else { return }
                        let welcome = WebSocketMessage(type: .heartbeat, data: [
                            "message": "Connected to Mac4Mac",
                            "status": "ready",
                            "serverTime": ISO8601DateFormatter().string(from: Date())
                        ])
                        self.sendWebSocketMessage(to: wsConnection, message: welcome)
                    }
                }
            })
        }
    }
    
    private func sendServerInfo(to wsConnection: WebSocketConnection) {
        let computerName = Host.current().localizedName ?? "Unknown Mac"
        let serverInfo = WebSocketMessage(type: .serverInfo, data: [
            "name": computerName,
            "app": "Mac4Mac",
            "version": "1.0",
            "wsPort": port,
            "httpPort": 8989,
            "capabilities": ["track_updates", "audio_config", "remote_control", "artwork", "progress_tracking", "seek_control", "volume_control"]
        ])
        
        sendWebSocketMessage(to: wsConnection, message: serverInfo)
    }
    
    private func generateWebSocketAcceptKey(key: String) -> String {
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magicString
        
        guard let data = combined.data(using: .utf8) else {
            return ""
        }
        
        // Use CommonCrypto for SHA1
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { bytes in
            CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        
        let hashData = Data(hash)
        return hashData.base64EncodedString()
    }
    
    private func handleWebSocketFrame(data: Data, wsConnection: WebSocketConnection) {
        guard data.count >= 2 else { return }
        
        let firstByte = data[0]
        let secondByte = data[1]
        
        let _ = (firstByte & 0x80) != 0  // fin bit - not used in this implementation
        let opcode = firstByte & 0x0F
        let masked = (secondByte & 0x80) != 0
        var payloadLength = Int(secondByte & 0x7F)
        
        var offset = 2
        
        // Handle extended payload length
        if payloadLength == 126 {
            guard data.count >= 4 else { return }
            payloadLength = Int(data[2]) << 8 | Int(data[3])
            offset = 4
        } else if payloadLength == 127 {
            return // 64-bit length not supported
        }
        
        // Handle masking key
        var maskingKey: [UInt8] = []
        if masked {
            guard data.count >= offset + 4 else { return }
            maskingKey = Array(data[offset..<offset+4])
            offset += 4
        }
        
        // Extract payload
        guard data.count >= offset + payloadLength else { return }
        var payload = Array(data[offset..<offset+payloadLength])
        
        // Unmask payload if needed
        if masked {
            for i in 0..<payload.count {
                payload[i] ^= maskingKey[i % 4]
            }
        }
        
        // Process the message based on opcode
        switch opcode {
        case 1: // Text frame
            if let messageString = String(data: Data(payload), encoding: .utf8) {
                if let messageData = messageString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] {
                    handleIncomingMessage(json, from: wsConnection)
                }
            }
            
        case 8: // Close frame
            sendCloseFrame(to: wsConnection)
            removeConnection(wsConnection)
            
        case 9: // Ping frame
            sendPongFrame(to: wsConnection, payload: payload)
            
        case 10: // Pong frame
            break // Pong received
            
        default:
            break // Unknown opcode
        }
    }
    
    private func sendCloseFrame(to wsConnection: WebSocketConnection) {
        var frame = Data()
        frame.append(0x88) // FIN + Close opcode
        frame.append(0x00) // No payload
        
        wsConnection.connection.send(content: frame, completion: .contentProcessed { _ in })
    }
    
    private func sendPongFrame(to wsConnection: WebSocketConnection, payload: [UInt8]) {
        var frame = Data()
        frame.append(0x8A) // FIN + Pong opcode
        frame.append(UInt8(payload.count))
        frame.append(contentsOf: payload)
        
        wsConnection.connection.send(content: frame, completion: .contentProcessed { _ in })
    }
    
    private func handleIncomingMessage(_ json: [String: Any], from wsConnection: WebSocketConnection) {
        guard let typeString = json["type"] as? String,
              let messageType = MessageType(rawValue: typeString) else {
            return
        }
        
        switch messageType {
        case .remoteCommand:
            if let data = json["data"] as? [String: Any] {
                handleRemoteCommand(data, from: wsConnection)
            }
        case .seekCommand:
            if let data = json["data"] as? [String: Any] {
                handleSeekCommand(data)
            }
        case .volumeCommand:
            if let data = json["data"] as? [String: Any] {
                handleVolumeCommand(data)
            }
        case .heartbeat:
            // Respond to heartbeat
            let response = WebSocketMessage(type: .heartbeat, data: [
                "status": "alive",
                "connections": connections.filter { $0.isWebSocketUpgraded }.count,
                "serverTime": ISO8601DateFormatter().string(from: Date()),
                "progressTracking": progressTracker.trackingStatus
            ])
            sendWebSocketMessage(to: wsConnection, message: response)
        default:
            break
        }
    }

    // Helper to send ack back to a specific WebSocket connection
    private func sendAck(to wsConnection: WebSocketConnection, command: String, status: String, reason: String? = nil, resolvedID: String? = nil, confidence: Double? = nil) {
        var ackData: [String: Any] = [
            "command": command,
            "status": status
        ]
        if let r = reason { ackData["reason"] = r }
        if let id = resolvedID { ackData["resolvedID"] = id }
        if let c = confidence { ackData["matchConfidence"] = c }

        let ackMessage = WebSocketMessage(type: .ack, data: ackData)
        // Log exact ACK payload for diagnostics
        if let jsonData = ackMessage.toJSON(), let jsonString = String(data: jsonData, encoding: .utf8) {
            LogWriter.logDebug("Sending ACK to connection \(wsConnection.id.uuidString): \(jsonString)")
        } else {
            LogWriter.logDebug("Sending ACK (could not serialize JSON) for command: \(command) status: \(status)")
        }

        sendWebSocketMessage(to: wsConnection, message: ackMessage)
    }

    private func handleRemoteCommand(_ data: [String: Any], from wsConnection: WebSocketConnection) {
        guard let command = data["command"] as? String else { return }
    // Also log via LogWriter (ensures persistence in ~/Library/Caches/MAC4MAC_Logs)
    LogWriter.logNormal("Remote command received: \(command) | data: \(data)")
        switch command {
        case "play_pause":
            let script = "tell application \"Music\" to playpause"
            executeAppleScript(script)
        case "next_track":
            let script = "tell application \"Music\" to next track"
            executeAppleScript(script)
        case "previous_track":
            let script = "tell application \"Music\" to previous track"
            executeAppleScript(script)
        case "play_song":
            // Prefer a true library `persistentID` if provided. If not, prefer `catalogID` (MusicKit ID) for Apple Music items.
            LogWriter.logDebug("play_song handler invoked on connection \(wsConnection.id.uuidString) thread=\(Thread.isMainThread ? "main" : "bg")")
            // Ensure the client sees we received the command
            sendAck(to: wsConnection, command: "play_song", status: "attempting", reason: "RECEIVED")
            if let pid = data["persistentID"] as? String, !pid.isEmpty {
                // Treat this as a library persistent ID and attempt AppleScript lookup first
                let musicKitID = pid
                LogWriter.logNormal("play_song persistentID: \(musicKitID)")
                LogWriter.logNormal("Received play_song with persistentID: \(musicKitID)")

                // Send immediate ack: command received and attempt starting
                sendAck(to: wsConnection, command: "play_song", status: "attempting")

                // Try AppleScript for local library first
                let script = """
                tell application \"Music\"
                    if it is running then
                        try
                            set theTrack to (first track of library playlist whose persistent ID is "\(musicKitID)")
                            play theTrack
                        on error
                            return \"NOT_FOUND\"
                        end try
                    end if
                end tell
                """
                let result = executeAppleScriptWithResult(script)
                LogWriter.logNormal("AppleScript result for persistentID \(musicKitID): \(result ?? "nil")")
                if result == "NOT_FOUND" || result == nil {
                let result = executeAppleScriptWithResult(script)
                    LogWriter.logNormal("AppleScript did not find local track by persistentID. Checking metadata-based local search first for ID: \(musicKitID)")
                if result == "NOT_FOUND" || result == nil {
                    // AppleScript did not find the track by persistent ID.
                    LogWriter.logNormal("AppleScript did not find local track by persistentID. Checking metadata-based local search first for ID: \(musicKitID)")

                    // If client provided an appleMusicURL (e.g., from Shazam), try opening it directly first
                    if let appleMusicURL = data["appleMusicURL"] as? String, !appleMusicURL.isEmpty {
                        LogWriter.logNormal("Received appleMusicURL from client: \(appleMusicURL). Attempting to open/play via Music.app")
                        // Use AppleScript to open the URL in Music and play
                        let openScript = "tell application \"Music\" to open location \"\(appleMusicURL)\""
                        let openResult = executeAppleScriptWithResult(openScript)
                        LogWriter.logNormal("AppleScript open location result: \(openResult ?? "nil")")
                        // Try to play after opening
                        let playScript = "tell application \"Music\" to play"
                        _ = executeAppleScriptWithResult(playScript)
                        // Give some time for Music to load the link; send ack that we attempted
                        sendAck(to: wsConnection, command: "play_song", status: "attempting", reason: "OPENED_URL")
                        // Return early; player state will be verified by progress tracker or subsequent updates
                        return
                    }

                    // Try a metadata-based AppleScript search (title + artist) in the local library before contacting MusicKit catalog
                    var handledByMeta = false
                    if let title = data["title"] as? String, let artist = data["artist"] as? String {
                        // Escape quotes in title/artist
                        let escTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
                        let escArtist = artist.replacingOccurrences(of: "\"", with: "\\\"")
                        let metaScript = """
                        tell application \"Music\"
                            if it is running then
                                try
                                    set foundTracks to (every track of library playlist whose name contains \"\(escTitle)\" and artist contains \"\(escArtist)\")
                                    if (count of foundTracks) > 0 then
                                        set theTrack to item 1 of foundTracks
                                        play theTrack
                                        return \"FOUND_LOCAL_BY_META\"
                                    else
                                        return \"NOT_FOUND_BY_META\"
                                    end if
                                on error
                                    return \"NOT_FOUND_BY_META\"
                                end try
                            end if
                        end tell
                        """

                        let metaResult = executeAppleScriptWithResult(metaScript)
                        LogWriter.logNormal("AppleScript metadata search result for title='\(title)' artist='\(artist)': \(metaResult ?? "nil")")
                        if metaResult == "FOUND_LOCAL_BY_META" {
                            LogWriter.logNormal("Metadata-based local search succeeded for title='\(title)' artist='\(artist)'")
                            // Final ack: success (local play via metadata)
                            sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: musicKitID, confidence: 1.0)
                            handledByMeta = true
                        }
                    }

                    if handledByMeta {
                        // Already handled local playback via metadata search
                        return
                    }

                    // Fallback: Use MusicKit to play by MusicKit ID (for Apple Music catalog songs)
                    LogWriter.logNormal("Trying MusicKit fallback for persistentID-as-MusicKit-ID: \(musicKitID)")
                    Task {
                        do {
                            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(musicKitID))
                            let response = try await request.response()
                            let song = response.items.first
                                if let song = song {
                                do {
                                    try await MusicPlayerAdapter.shared.insertAndPlaySong(song)
                                    LogWriter.logNormal("MusicKit fallback: Played song by MusicKit ID: \(musicKitID) via adapter")
                                } catch {
                                    LogWriter.logEssential("MusicKit fallback adapter play failed: \(error)")
                                }
                                // Final ack: success
                                sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: musicKitID, confidence: 1.0)
                } else {
                    LogWriter.logNormal("MusicKit fallback: No song found for ID: \(musicKitID)")
                                    // Attempt metadata search fallback (title + artist) if metadata was provided
                                    if let title = data["title"] as? String, let artist = data["artist"] as? String {
                                        LogWriter.logNormal("Attempting metadata search for title='\(title)' artist='\(artist)'")
                                        do {
                                            let (played, resolvedID, confidence) = try await metadataSearchAndPlay(title: title, artist: artist, album: data["album"] as? String, wsConnection: wsConnection)
                                            if played {
                                                LogWriter.logNormal("Metadata search matched and played: resolvedID=\(resolvedID ?? "") confidence=\(confidence)")
                                                sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: resolvedID, confidence: confidence)
                                            } else {
                                                LogWriter.logNormal("Metadata search found no confident match for title='\(title)' artist='\(artist)'")
                                                sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "NOT_FOUND")
                                            }
                                        } catch {
                                            LogWriter.logEssential("Metadata search error for title='\(data["title"] ?? "")' artist='\(data["artist"] ?? "")': \(error)")
                                            sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "SEARCH_ERROR")
                                        }
                                    } else {
                                        // Final ack: failed (no metadata to search)
                                        sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "NOT_FOUND")
                                    }
                            }
                        } catch {
                            LogWriter.logEssential("MusicKit fallback error for ID \(musicKitID): \(error)")
                            // If the resource request failed with a 404, attempt metadata search if possible
                            // Attempt metadata search on common MusicKit 404-like failures
                            let nsErr = error as NSError
                            if nsErr.code == 404 || nsErr.domain == "MusicDataRequest.Error" || nsErr.code == 40400 {
                                if let title = data["title"] as? String, let artist = data["artist"] as? String {
                                    LogWriter.logNormal("MusicKit ID request returned 404 — attempting metadata search as fallback")
                                    do {
                                        let (played, resolvedID, confidence) = try await metadataSearchAndPlay(title: title, artist: artist, album: data["album"] as? String, wsConnection: wsConnection)
                                        if played {
                                            LogWriter.logNormal("Metadata search matched and played after 404: resolvedID=\(resolvedID ?? "") confidence=\(confidence)")
                                            sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: resolvedID, confidence: confidence)
                                        } else {
                                            LogWriter.logNormal("Metadata search after 404 found no confident match")
                                            sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "NOT_FOUND")
                                        }
                                    } catch {
                                        LogWriter.logEssential("Metadata search after 404 error: \(error)")
                                        sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "SEARCH_ERROR")
                                    }
                                } else {
                                    sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "MUSICKIT_ERROR")
                                }
                            } else {
                                sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "MUSICKIT_ERROR")
                            }
                        }
                    }
                } else {
                    LogWriter.logNormal("AppleScript successfully triggered playback for persistentID: \(musicKitID)")
                    // Final ack: success (local play)
                    sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: musicKitID, confidence: 1.0)
                }
                return
            }

            // If we get here, no library persistentID was provided (or it was empty). Prefer catalogID (MusicKit ID) if present.
            if let catalogID = data["catalogID"] as? String, !catalogID.isEmpty {
                LogWriter.logNormal("play_song catalogID: \(catalogID)")
                LogWriter.logNormal("Received play_song with catalogID: \(catalogID)")

                // Send immediate ack: command received and attempt starting
                sendAck(to: wsConnection, command: "play_song", status: "attempting")

                // If client provided an appleMusicURL, try to extract an explicit track id (i=) and prefer it for catalog lookups
                if let appleMusicURL = data["appleMusicURL"] as? String, !appleMusicURL.isEmpty {
                    LogWriter.logNormal("Received appleMusicURL from client: \(appleMusicURL)")
                    if let url = URL(string: appleMusicURL), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        // Attempt to extract ?i=TRACK_ID
                        let trackParam = components.queryItems?.first(where: { $0.name == "i" })?.value
                        // Try last path component as a candidate (many Apple Music URLs include the track id as the last path component, e.g. /song/i.<id>)
                        let lastPathComponent = url.path.split(separator: "/").last.map(String.init)

                        // Prefer query param, otherwise look for a path-based id like "i.<id>" or a raw id in the path
                        var trackIdCandidate: String? = trackParam
                        if trackIdCandidate == nil, let last = lastPathComponent {
                            if last.starts(with: "i.") {
                                trackIdCandidate = last
                            } else if last.count > 5 {
                                // Some URLs may use the id directly as the last component
                                trackIdCandidate = last
                            }
                        }

                        if let trackId = trackIdCandidate, !trackId.isEmpty {
                            LogWriter.logNormal("Extracted track id from URL/path: \(trackId). Will attempt MusicKit lookup using this id first.")
                            // Prefer the extracted track id before other candidates
                            Task {
                                let idCandidates = [trackId, "i.\(trackId)", catalogID]
                                var lastError: Error?
                                var found = false
                                for candidate in idCandidates {
                                    do {
                                        LogWriter.logNormal("MusicKit: attempting resource request for candidate id=\(candidate)")
                                        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(candidate))
                                        let response = try await request.response()
                                        if let song = response.items.first {
                                        do {
                                            try await MusicPlayerAdapter.shared.insertAndPlaySong(song)
                                            LogWriter.logNormal("MusicKit: Played song by candidate id: \(candidate) via adapter")
                                            sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: candidate, confidence: 1.0)
                                            found = true
                                            break
                                        } catch {
                                            LogWriter.logEssential("MusicKit adapter play failed for candidate id=\(candidate): \(error)")
                                        }
                                        } else {
                                            LogWriter.logNormal("MusicKit: No song found for candidate id=\(candidate)")
                                        }
                                    } catch {
                                        lastError = error
                                        let nsErr = error as NSError
                                        let desc = (nsErr.userInfo[NSLocalizedDescriptionKey] as? String) ?? String(describing: error)
                                        LogWriter.logEssential("MusicKit resource request error for candidate id=\(candidate): domain=\(nsErr.domain) code=\(nsErr.code) desc=\(desc) userInfo=\(nsErr.userInfo)")
                                        continue
                                    }
                                }

                                if found { return }

                                // If nothing found by id, fall back to metadata search (title+artist) if provided
                                if let title = data["title"] as? String, let artist = data["artist"] as? String {
                                    do {
                                        let (played, resolvedID, confidence) = try await metadataSearchAndPlay(title: title, artist: artist, album: data["album"] as? String ?? lastPathComponent, wsConnection: wsConnection)
                                        if played {
                                            sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: resolvedID, confidence: confidence)
                                        } else {
                                            sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "NOT_FOUND")
                                        }
                                    } catch {
                                        if let e = lastError as NSError? {
                                            let desc = (e.userInfo[NSLocalizedDescriptionKey] as? String) ?? String(describing: e)
                                            LogWriter.logEssential("Final fallback metadata search error; last MusicKit error domain=\(e.domain) code=\(e.code) desc=\(desc)")
                                        }
                                        sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "SEARCH_ERROR")
                                    }
                                } else {
                                    // No track id extracted but also no metadata to search with — fall through to try resource-by-id for the provided catalogID below
                                    LogWriter.logNormal("No explicit track id extracted from URL and no metadata to assist search — will try catalogID resource request next.")
                                }
                            }
                            return
                        }
                    }

                    // If we couldn't extract a usable track id from the URL, do not open the URL immediately here.
                    // Let the later resource-by-id attempt (using catalogID) run and only open the URL as a last resort
                    LogWriter.logNormal("appleMusicURL present but no explicit track id extracted — will attempt catalogID resource request before opening URL")
                }

                // Otherwise, try MusicKit resource request by catalogID (try a few id-variants if necessary)
                LogWriter.logNormal("Trying MusicKit resource request for catalogID: \(catalogID)")
                // Send an extra debug ack so clients can see we began the catalog lookup
                sendAck(to: wsConnection, command: "play_song", status: "attempting", reason: "CATALOG_LOOKUP_STARTED")
                LogWriter.logDebug("Spawning Task for catalogID resource lookup for id=\(catalogID)")
                Task {
                    LogWriter.logDebug("catalogID resource lookup Task started for id=\(catalogID)")
                    // Use centralized adapter for playback
                                    // player not required here; adapter will be used inside metadataSearchAndPlay
                    // Try common id variants to handle storefront/format differences
                    let idCandidates = [catalogID, "i.\(catalogID)"]
                    var lastError: Error?
                    var found = false
                    for candidate in idCandidates {
                        do {
                            LogWriter.logNormal("MusicKit: attempting resource request for candidate id=\(candidate)")
                            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(candidate))
                            let response = try await request.response()
                            if let song = response.items.first {
                                do {
                                    try await MusicPlayerAdapter.shared.insertAndPlaySong(song)
                                    LogWriter.logNormal("MusicKit: Played song by catalogID candidate: \(candidate) via adapter")
                                    sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: candidate, confidence: 1.0)
                                    found = true
                                    break
                                } catch {
                                    LogWriter.logEssential("MusicKit adapter play failed for candidate=\(candidate): \(error)")
                                }
                            } else {
                                            LogWriter.logNormal("MusicKit: No song found for candidate id=\(candidate)")
                            }
                        } catch {
                            lastError = error
                            let nsErr = error as NSError
                            let desc = (nsErr.userInfo[NSLocalizedDescriptionKey] as? String) ?? String(describing: error)
                                        LogWriter.logEssential("MusicKit resource request error for candidate id=\(candidate): domain=\(nsErr.domain) code=\(nsErr.code) desc=\(desc) userInfo=\(nsErr.userInfo)")
                            // Try next candidate if this one failed with a 404-like issue
                            continue
                        }
                    }

                    if found { return }

                                LogWriter.logDebug("catalogID resource lookup completed; found=\(found)")

                    // If no candidate succeeded, fall back to metadata search (if we have title/artist)
                    if let title = data["title"] as? String, let artist = data["artist"] as? String {
                        do {
                            let (played, resolvedID, confidence) = try await metadataSearchAndPlay(title: title, artist: artist, album: data["album"] as? String, wsConnection: wsConnection)
                            if played {
                                sendAck(to: wsConnection, command: "play_song", status: "ok", resolvedID: resolvedID, confidence: confidence)
                            } else {
                                sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "NOT_FOUND")
                            }
                        } catch {
                            // If we had a lastError from resource attempts, include that info in the logs
                            if let e = lastError as NSError? {
                                let desc = (e.userInfo[NSLocalizedDescriptionKey] as? String) ?? String(describing: e)
                                LogWriter.logEssential("Final fallback metadata search error; last MusicKit error domain=\(e.domain) code=\(e.code) desc=\(desc)")
                            }
                            sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "SEARCH_ERROR")
                        }
                    } else {
                        // No metadata available to search with
                        if let e = lastError as NSError? {
                            let desc = (e.userInfo[NSLocalizedDescriptionKey] as? String) ?? String(describing: e)
                            LogWriter.logEssential("MusicKit resource-by-id attempts failed; last error domain=\(e.domain) code=\(e.code) desc=\(desc)")
                        }
                        sendAck(to: wsConnection, command: "play_song", status: "failed", reason: "MUSICKIT_ERROR")
                    }
                }
                return
            }
            }
        case "start_progress_tracking":
            startProgressTracking()
        case "stop_progress_tracking":
            stopProgressTracking()
        case "set_progress_interval":
            if let interval = data["interval"] as? Double {
                setProgressInterval(interval)
            } else {
                setProgressInterval(1.0) // Default to 1.0 if missing
            }
        default:
            break
        }
    }
    
    private func handleSeekCommand(_ data: [String: Any]) {
        guard let position = data["position"] as? Double else { return }
        
        let script = "tell application \"Music\" to set player position to \(position)"
        executeAppleScript(script)
        
        // Immediately fetch and broadcast new position
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.fetchAndBroadcastProgress()
        }
    }
    
    private func handleVolumeCommand(_ data: [String: Any]) {
        guard let volume = data["volume"] as? Int else { return }
        
        let clampedVolume = max(0, min(100, volume))
        let script = "tell application \"Music\" to set sound volume to \(clampedVolume)"
        executeAppleScript(script)
    }
    
    private func executeAppleScript(_ script: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
                LogWriter.logEssential("Failed to execute AppleScript: \(error)")
        }
    }
    
    func fetchAndBroadcastProgress() {
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
                return "stopped"
            end if
        end tell
        """
        
        DispatchQueue.global().async {
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
                    
                    if output == "stopped" {
                        self.progressTracker.stopTracking()
                        return
                    }
                    
                    let components = output.components(separatedBy: ",")
                    if components.count >= 4,
                       let position = Double(components[0]),
                       let duration = Double(components[1]),
                       let volume = Int(components[2]) {
                        
                        let isPlaying = components[3] == "true"
                        
                        // Adjust tracking interval based on play state
                        let newInterval: TimeInterval = isPlaying ? 1.0 : 5.0
                        if abs(newInterval - self.progressTracker.currentUpdateInterval) > 0.1 {
                            self.progressTracker.setUpdateInterval(newInterval)
                        }
                        
                        let message = WebSocketMessage(type: .progressUpdate, data: [
                            "position": position,
                            "duration": duration,
                            "volume": volume,
                            "isPlaying": isPlaying,
                            "percentage": duration > 0 ? (position / duration) * 100 : 0
                        ])
                        
                        DispatchQueue.main.async {
                            self.broadcast(message)
                        }
                    }
                }
            } catch {
                LogWriter.logDebug("Failed to fetch progress: \(error)")
            }
        }
    }
    
    func startProgressTracking() {
        progressTracker.startTracking()
        
        // Send initial progress immediately
        fetchAndBroadcastProgress()
    }
    
    func stopProgressTracking() {
        progressTracker.stopTracking()
    }
    
    func setProgressInterval(_ interval: TimeInterval) {
        progressTracker.setUpdateInterval(interval)
    }
    
    private func sendWebSocketMessage(to wsConnection: WebSocketConnection, message: WebSocketMessage) {
        guard wsConnection.isWebSocketUpgraded else { return }
        
        guard let jsonData = message.toJSON(),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        sendWebSocketText(to: wsConnection, text: jsonString)
    }
    
    private func sendWebSocketText(to wsConnection: WebSocketConnection, text: String) {
        guard let textData = text.data(using: .utf8) else { return }
        
        let payloadLength = textData.count
        var frame = Data()
        
        // First byte: FIN = 1, opcode = 1 (text)
        frame.append(0x81)
        
        // Second byte: payload length (server frames are never masked)
        if payloadLength < 126 {
            frame.append(UInt8(payloadLength))
        } else if payloadLength < 65536 {
            frame.append(126)
            frame.append(UInt8(payloadLength >> 8))
            frame.append(UInt8(payloadLength & 0xFF))
        } else {
            return // Payload too large
        }
        
        // Payload
        frame.append(textData)
        
        // CRASH FIX: Add weak reference in completion
        wsConnection.connection.send(content: frame, completion: .contentProcessed { [weak self, weak wsConnection] error in
            guard let self = self, let wsConnection = wsConnection else { return }
            
            if let error = error {
                LogWriter.logDebug("WebSocket send failed: \(error)")
                self.removeConnection(wsConnection)
            }
        })
    }
    
    // MARK: - Public Methods for Broadcasting Updates
    
    func broadcastTrackUpdate(trackName: String, artist: String, album: String, persistentID: String?, isPlaying: Bool, artworkBase64: String? = nil) {
        var messageData: [String: Any] = [
            "trackName": trackName,
            "artist": artist,
            "album": album,
            "persistentID": persistentID as Any,
            "isPlaying": isPlaying,
            "hasArtwork": artworkBase64 != nil
        ]
        
        // Add the actual artwork data to the message
        messageData["artworkBase64"] = artworkBase64
        
        let message = WebSocketMessage(type: .trackUpdate, data: messageData)
        broadcast(message)
    }
    
    func broadcastAudioConfigUpdate(sampleRate: Double, bitDepth: Int, deviceName: String) {
        let message = WebSocketMessage(type: .audioConfigUpdate, data: [
            "sampleRate": sampleRate,
            "bitDepth": bitDepth,
            "deviceName": deviceName,
            "sampleRateDisplay": String(format: "%.1f kHz", sampleRate / 1000.0),
            "bitDepthDisplay": "\(bitDepth)-bit"
        ])
        
        broadcast(message)
    }
    
    func broadcastPlayStateUpdate(isPlaying: Bool) {
        let message = WebSocketMessage(type: .playStateUpdate, data: [
            "isPlaying": isPlaying
        ])
        
        broadcast(message)
    }
    
    private func broadcast(_ message: WebSocketMessage) {
        let activeConnections = connections.filter { $0.isWebSocketUpgraded }
        
        activeConnections.forEach { wsConnection in
            sendWebSocketMessage(to: wsConnection, message: message)
        }
    }
    
    func stopServer() {
        progressTracker.stopTracking()
        // CRASH FIX: Thread-safe cleanup
        connectionsQueue.async(flags: .barrier) { [weak self] in
            let connectionsToCancel = self?._connections ?? []
            self?._connections.removeAll()
            
            DispatchQueue.global().async {
                connectionsToCancel.forEach { $0.connection.cancel() }
            }
        }
        listener?.cancel()
        listener = nil
    Mac4MacWebSocketServer.shared = nil
    LogWriter.logEssential("WebSocket server stopped")
    }
}
