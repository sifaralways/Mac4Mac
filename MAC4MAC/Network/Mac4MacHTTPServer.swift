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
            "endpoints": [
                "/track": "Current track information with artwork",
                "/artwork": "Current track artwork (binary image data)",
                "/status": "Server status",
                "/audio": "Audio device information"
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
            "bitDepthDisplay": currentTrackData.bitDepthDisplay
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
    
    private func sendWelcome(connection: NWConnection) {
        let welcome = """
        {
            "message": "Mac4Mac HTTP Server",
            "description": "Provides real-time Apple Music track and audio information with artwork support",
            "endpoints": {
                "/track": "Current track information including base64 artwork",
                "/artwork": "Current track artwork as binary image data",
                "/status": "Server status",
                "/audio": "Audio device information"
            },
            "usage": "GET requests only, JSON responses for most endpoints, binary for /artwork"
        }
        """
        
        let response = createHTTPResponse(data: welcome.data(using: .utf8) ?? Data(), contentType: "application/json")
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
    
    private func sendNotFound(connection: NWConnection, message: String? = nil) {
        let notFoundMessage = message ?? "Available endpoints: /track, /artwork, /status, /audio"
        let notFound = """
        {
            "error": "Not Found",
            "message": "\(notFoundMessage)"
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
            "message": "\(error)"
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
        Access-Control-Allow-Methods: GET\r
        Access-Control-Allow-Headers: Content-Type\r
        Cache-Control: no-cache\r
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
}
