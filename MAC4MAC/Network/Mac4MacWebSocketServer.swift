import Foundation
import Network
import CommonCrypto

class Mac4MacWebSocketServer {
    private var listener: NWListener?
    private var connections: [WebSocketConnection] = []
    private let port: UInt16 = 8990
    
    // Message types for communication
    enum MessageType: String, CaseIterable {
        case trackUpdate = "track_update"
        case audioConfigUpdate = "audio_config_update"
        case playStateUpdate = "play_state_update"
        case remoteCommand = "remote_command"
        case heartbeat = "heartbeat"
        case serverInfo = "server_info"
    }
    
    class WebSocketConnection {
        let connection: NWConnection
        var isWebSocketUpgraded = false
        let id = UUID()
        
        init(connection: NWConnection) {
            self.connection = connection
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
                print("[Mac4Mac WebSocket] ❌ Failed to serialize message: \(error)")
                return nil
            }
        }
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
            print("[Mac4Mac WebSocket] ✅ Started on port \(port)")
        } catch {
            print("[Mac4Mac WebSocket] ❌ Failed to start: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let wsConnection = WebSocketConnection(connection: connection)
        connections.append(wsConnection)
        connection.start(queue: .global())
        
        print("[Mac4Mac WebSocket] 🔗 New connection \(wsConnection.id). Total: \(connections.count)")
        
        // Start receiving data for WebSocket handshake
        receiveData(from: wsConnection)
    }
    
    private func receiveData(from wsConnection: WebSocketConnection) {
        wsConnection.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            
            if let error = error {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Receive error: \(error)")
                self?.removeConnection(wsConnection)
                return
            }
            
            if let data = data, !data.isEmpty {
                if !wsConnection.isWebSocketUpgraded {
                    print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🤝 Processing handshake")
                    self?.handleWebSocketHandshake(data: data, wsConnection: wsConnection)
                } else {
                    print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📨 Processing WebSocket frame")
                    self?.handleWebSocketFrame(data: data, wsConnection: wsConnection)
                }
            }
            
            if isComplete {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🔌 Connection completed normally")
                self?.removeConnection(wsConnection)
                return
            }
            
            // Continue receiving
            self?.receiveData(from: wsConnection)
        }
    }
    
    private func handleWebSocketHandshake(data: Data, wsConnection: WebSocketConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Failed to decode handshake")
            removeConnection(wsConnection)
            return
        }
        
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🤝 Handshake request:\n\(request.prefix(500))")
        
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
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Invalid WebSocket handshake")
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Key: \(webSocketKey ?? "nil"), Upgrade: \(isWebSocketUpgrade), Connection: \(isConnectionUpgrade)")
            removeConnection(wsConnection)
            return
        }
        
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] ✅ Valid handshake with key: \(key)")
        
        // Generate WebSocket accept key
        let acceptKey = generateWebSocketAcceptKey(key: key)
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🔑 Generated accept key: \(acceptKey)")
        
        // Send WebSocket handshake response
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r

        """
        
        if let responseData = response.data(using: .utf8) {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📤 Sending handshake response")
            wsConnection.connection.send(content: responseData, completion: .contentProcessed { error in
                if let error = error {
                    print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Failed to send handshake: \(error)")
                    self.removeConnection(wsConnection)
                } else {
                    wsConnection.isWebSocketUpgraded = true
                    print("[Mac4Mac WebSocket] [\(wsConnection.id)] ✅ WebSocket upgraded successfully!")
                    
                    // Send initial messages with delay to prevent overwhelming
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                        self.sendServerInfo(to: wsConnection)
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
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
            "capabilities": ["track_updates", "audio_config", "remote_control", "artwork"]
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
        data.withUnsafeBytes { bytes in
            CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        
        let hashData = Data(hash)
        return hashData.base64EncodedString()
    }
    
    private func handleWebSocketFrame(data: Data, wsConnection: WebSocketConnection) {
        guard data.count >= 2 else {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Frame too short: \(data.count) bytes")
            return
        }
        
        let firstByte = data[0]
        let secondByte = data[1]
        
        let fin = (firstByte & 0x80) != 0
        let opcode = firstByte & 0x0F
        let masked = (secondByte & 0x80) != 0
        var payloadLength = Int(secondByte & 0x7F)
        
        var offset = 2
        
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📊 Frame: FIN=\(fin), opcode=\(opcode), masked=\(masked), length=\(payloadLength)")
        
        // Handle extended payload length
        if payloadLength == 126 {
            guard data.count >= 4 else {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Extended length frame too short")
                return
            }
            payloadLength = Int(data[2]) << 8 | Int(data[3])
            offset = 4
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📊 Extended length: \(payloadLength)")
        } else if payloadLength == 127 {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ 64-bit length not supported")
            return
        }
        
        // Handle masking key
        var maskingKey: [UInt8] = []
        if masked {
            guard data.count >= offset + 4 else {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Masked frame too short for key")
                return
            }
            maskingKey = Array(data[offset..<offset+4])
            offset += 4
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🔑 Masking key: \(maskingKey.map { String(format: "%02x", $0) }.joined())")
        }
        
        // Extract payload
        guard data.count >= offset + payloadLength else {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Frame too short for payload: need \(offset + payloadLength), have \(data.count)")
            return
        }
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
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📝 Received text: \(messageString)")
                
                if let messageData = messageString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] {
                    handleIncomingMessage(json, from: wsConnection)
                } else {
                    print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Failed to parse JSON")
                }
            } else {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Failed to decode text payload")
            }
            
        case 8: // Close frame
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] 👋 Client requested close")
            sendCloseFrame(to: wsConnection)
            removeConnection(wsConnection)
            
        case 9: // Ping frame
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🏓 Received ping")
            sendPongFrame(to: wsConnection, payload: payload)
            
        case 10: // Pong frame
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🏓 Received pong")
            
        default:
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❓ Unknown opcode: \(opcode)")
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
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Invalid message type")
            return
        }
        
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📨 Handling message type: \(messageType)")
        
        switch messageType {
        case .remoteCommand:
            if let data = json["data"] as? [String: Any] {
                handleRemoteCommand(data)
            }
        case .heartbeat:
            // Respond to heartbeat
            let response = WebSocketMessage(type: .heartbeat, data: [
                "status": "alive",
                "connections": connections.filter { $0.isWebSocketUpgraded }.count,
                "serverTime": ISO8601DateFormatter().string(from: Date())
            ])
            sendWebSocketMessage(to: wsConnection, message: response)
        default:
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ℹ️ Unhandled message type: \(messageType)")
        }
    }
    
    private func handleRemoteCommand(_ data: [String: Any]) {
        guard let command = data["command"] as? String else {
            print("[Mac4Mac WebSocket] ❌ No command in remote command data")
            return
        }
        
        print("[Mac4Mac WebSocket] 🎮 Received remote command: \(command)")
        
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
        default:
            print("[Mac4Mac WebSocket] ❓ Unknown command: \(command)")
            return
        }
        
        executeAppleScript(script)
    }
    
    private func executeAppleScript(_ script: String) {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        do {
            try task.run()
            task.waitUntilExit()
            print("[Mac4Mac WebSocket] ✅ Executed AppleScript command successfully")
        } catch {
            print("[Mac4Mac WebSocket] ❌ Failed to execute command: \(error)")
        }
    }
    
    private func sendWebSocketMessage(to wsConnection: WebSocketConnection, message: WebSocketMessage) {
        guard wsConnection.isWebSocketUpgraded else {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Cannot send - not upgraded")
            return
        }
        
        guard let jsonData = message.toJSON(),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Failed to serialize message")
            return
        }
        
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📤 Sending: \(message.type.rawValue)")
        sendWebSocketText(to: wsConnection, text: jsonString)
    }
    
    private func sendWebSocketText(to wsConnection: WebSocketConnection, text: String) {
        guard let textData = text.data(using: .utf8) else {
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Failed to encode text")
            return
        }
        
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
            print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Payload too large: \(payloadLength)")
            return
        }
        
        // Payload
        frame.append(textData)
        
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 📤 Sending frame: \(frame.count) bytes")
        
        wsConnection.connection.send(content: frame, completion: .contentProcessed { error in
            if let error = error {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] ❌ Send failed: \(error)")
                self.removeConnection(wsConnection)
            } else {
                print("[Mac4Mac WebSocket] [\(wsConnection.id)] ✅ Message sent successfully")
            }
        })
    }
    
    private func removeConnection(_ wsConnection: WebSocketConnection) {
        connections.removeAll { $0.id == wsConnection.id }
        wsConnection.connection.cancel()
        print("[Mac4Mac WebSocket] [\(wsConnection.id)] 🗑️ Removed. Total: \(connections.count)")
    }
    
    // MARK: - Public Methods for Broadcasting Updates
    
    func broadcastTrackUpdate(trackName: String, artist: String, album: String, persistentID: String?, isPlaying: Bool, artworkBase64: String? = nil) {
        var messageData: [String: Any] = [
            "trackName": trackName,
            "artist": artist,
            "album": album,
            "persistentID": persistentID as Any,
            "isPlaying": isPlaying
        ]
        
        if let artworkBase64 = artworkBase64 {
            messageData["artworkBase64"] = artworkBase64
            messageData["hasArtwork"] = true
        } else {
            messageData["hasArtwork"] = false
        }
        
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
        print("[Mac4Mac WebSocket] 📡 Broadcasting \(message.type.rawValue) to \(activeConnections.count) clients")
        
        activeConnections.forEach { wsConnection in
            sendWebSocketMessage(to: wsConnection, message: message)
        }
    }
    
    func stopServer() {
        connections.forEach { $0.connection.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        print("[Mac4Mac WebSocket] 🛑 Server stopped")
    }
}
