import Foundation
import Network
import CommonCrypto

class Mac4MacWebSocketServer {
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
                handleRemoteCommand(data)
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
    
    private func handleRemoteCommand(_ data: [String: Any]) {
        guard let command = data["command"] as? String else { return }
        
        LogWriter.logNormal("Remote command: \(command)")
        
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
        case "stop":
            let script = "tell application \"Music\" to stop"
            executeAppleScript(script)
        case "start_progress_tracking":
            startProgressTracking()
        case "stop_progress_tracking":
            stopProgressTracking()
        case "set_progress_interval":
            if let interval = data["interval"] as? Double {
                setProgressInterval(interval)
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
