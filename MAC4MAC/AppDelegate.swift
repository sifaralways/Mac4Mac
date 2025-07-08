import AppKit
import ScriptingBridge
import Network

// MARK: - Music ScriptingBridge Protocols

@objc protocol MusicApplication {
    @objc optional var currentTrack: MusicTrack { get }
    @objc optional var running: Bool { get }
    @objc optional var userPlaylists: [MusicPlaylist] { get }
    @objc optional var libraryPlaylist: MusicPlaylist { get }
    @objc optional func make(_ newElement: String, at: Any?, withProperties: [String: Any]) -> Any
}

@objc protocol MusicPlaylist {
    @objc optional var name: String { get }
    @objc optional var tracks: [MusicTrack] { get }
    @objc optional func add(_ track: MusicTrack)
}

@objc protocol MusicTrack {
    @objc optional var persistentID: String { get }
    @objc optional var name: String { get }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var currentSampleRate: Double = 44100
    var trackChangeMonitor = TrackChangeMonitor()
    let httpServer = Mac4MacHTTPServer()
    let webSocketServer = Mac4MacWebSocketServer()
    
    // Network permission helper
    private var permissionTriggerListener: NWListener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogWriter.log("✅ AppDelegate: App launched with debug logging")

        // Set initial defaults for toggles only once
        let defaults: [FeatureToggle: Bool] = [
            .logging: true,
            .playlistManagement: true,
            .httpServer: true
        ]
        for (feature, enabled) in defaults {
            let key = "MAC4MAC.FeatureToggle.\(feature.rawValue)"
            if UserDefaults.standard.object(forKey: key) == nil {
                FeatureToggleManager.set(feature, enabled: enabled)
            }
        }

        // Request network permissions first
        requestNetworkPermissions { [weak self] in
            // Start servers after permission is granted
            LogWriter.log("🌐 AppDelegate: Starting servers...")
            self?.httpServer.startServer()
            self?.webSocketServer.startServer()
            LogWriter.log("✅ AppDelegate: Servers started")
        }
        
        setupMenuBar()
        setupTrackMonitor()
    }
    
    private func requestNetworkPermissions(completion: @escaping () -> Void) {
        LogWriter.log("🔐 AppDelegate: Requesting network permissions...")
        
        // Create a temporary listener to trigger the permission dialog
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            // Use Bonjour service to trigger local network permission
            let service = NWListener.Service(name: "Mac4Mac-Permission", type: "_mac4mac._tcp")
            permissionTriggerListener = try NWListener(service: service, using: parameters)
            
            permissionTriggerListener?.newConnectionHandler = { connection in
                // Don't accept connections, just trigger permission
                connection.cancel()
            }
            
            permissionTriggerListener?.serviceRegistrationUpdateHandler = { serviceRegistration in
                switch serviceRegistration {
                case .add(_):
                    LogWriter.log("✅ AppDelegate: Network permission granted")
                    // Stop the permission trigger listener
                    self.permissionTriggerListener?.cancel()
                    self.permissionTriggerListener = nil
                    // Start the actual servers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        completion()
                    }
                case .remove(_):
                    LogWriter.log("⚠️ AppDelegate: Network service registration removed")
                @unknown default:
                    break
                }
            }
            
            permissionTriggerListener?.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    LogWriter.log("❌ AppDelegate: Permission trigger failed: \(error)")
                    // Start servers anyway
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        completion()
                    }
                case .ready:
                    LogWriter.log("🔐 AppDelegate: Permission trigger ready")
                default:
                    break
                }
            }
            
            permissionTriggerListener?.start(queue: .global())
            
            // Fallback timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.permissionTriggerListener != nil {
                    LogWriter.log("⏱️ AppDelegate: Permission timeout - starting servers anyway")
                    self.permissionTriggerListener?.cancel()
                    self.permissionTriggerListener = nil
                    completion()
                }
            }
            
        } catch {
            LogWriter.log("❌ AppDelegate: Failed to create permission trigger: \(error)")
            // Start servers anyway
            completion()
        }
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let _ = statusItem?.button {
            updateStatusBarTitle()
        }
        updateMenu()
    }

    func updateStatusBarTitle() {
        guard let button = statusItem?.button else { return }

        let sampleRateString = String(format: " %.1f kHz", currentSampleRate / 1000.0)

        guard let icon = NSImage(named: "AppIcon") else {
            button.title = sampleRateString
            return
        }

        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = true // for dark/light mode

        let attachment = NSTextAttachment()
        attachment.image = icon
        let iconString = NSAttributedString(attachment: attachment)

        // Offset the baseline so it aligns better with text
        let baselineOffset = NSAttributedString(string: sampleRateString, attributes: [
            .baselineOffset: 3
        ])

        let fullString = NSMutableAttributedString()
        fullString.append(iconString)
        fullString.append(baselineOffset)

        button.attributedTitle = fullString
    }

    func setupTrackMonitor() {
        LogWriter.log("📻 AppDelegate: Starting track monitor with artwork support")

        trackChangeMonitor.onTrackChange = { [weak self] trackInfo in
            guard let self = self else {
                LogWriter.log("❌ AppDelegate: Self is nil in trackChange callback")
                return
            }

            LogWriter.log("🎵 AppDelegate: ========================================")
            LogWriter.log("🎵 AppDelegate: TRACK CHANGE CALLBACK TRIGGERED")
            LogWriter.log("🎵 AppDelegate: ========================================")
            LogWriter.log("📛 AppDelegate: Name: \(trackInfo.name)")
            LogWriter.log("🎤 AppDelegate: Artist: \(trackInfo.artist)")
            LogWriter.log("💿 AppDelegate: Album: \(trackInfo.album)")
            LogWriter.log("🆔 AppDelegate: Persistent ID: \(trackInfo.persistentID)")
            
            // Debug the artwork situation
            if let artworkData = trackInfo.artworkData {
                LogWriter.log("🖼️ AppDelegate: Artwork found: \(artworkData.count) bytes")
                
                // Additional artwork debugging
                let base64Preview = String(artworkData.base64EncodedString().prefix(50))
                LogWriter.log("🔍 AppDelegate: Base64 preview: \(base64Preview)...")
                
                // Check if it's a valid image format
                if artworkData.starts(with: [0xFF, 0xD8, 0xFF]) {
                    LogWriter.log("📸 AppDelegate: Detected JPEG format")
                } else if artworkData.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                    LogWriter.log("📸 AppDelegate: Detected PNG format")
                } else {
                    LogWriter.log("❓ AppDelegate: Unknown image format - first 8 bytes: \(artworkData.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "))")
                }
            } else {
                LogWriter.log("⚠️ AppDelegate: No artwork data received")
            }
            
            LogWriter.log("🔍 AppDelegate: Fetching Sample Rate...")

            LogMonitor.fetchLatestSampleRate(forTrack: trackInfo.name) { rate, songName in
                LogWriter.log("📛 AppDelegate: Sample rate callback - Track Name: \(songName)")
                LogWriter.log("🎯 AppDelegate: Sample rate: \(rate) Hz")

                if abs(rate - self.currentSampleRate) >= 0.5 {
                    AudioManager.setOutputSampleRate(to: rate)
                    self.currentSampleRate = rate
                    DispatchQueue.main.async {
                        self.updateStatusBarTitle()
                        self.updateMenu()
                    }
                } else {
                    LogWriter.log("🔄 AppDelegate: Sample rate unchanged, no update needed")
                }

                if FeatureToggleManager.isEnabled(.playlistManagement) {
                    PlaylistManager.addTrack(persistentID: trackInfo.persistentID, sampleRate: rate)
                } else {
                    LogWriter.log("⏭️ AppDelegate: Playlist creation skipped (disabled in feature toggles)")
                }

                // Convert artwork to base64 if available
                var artworkBase64: String? = nil
                if let artworkData = trackInfo.artworkData {
                    artworkBase64 = artworkData.base64EncodedString()
                    LogWriter.log("🖼️ AppDelegate: Artwork converted to base64 (\(artworkBase64!.count) chars)")
                } else {
                    LogWriter.log("❌ AppDelegate: No artwork to convert")
                }

                LogWriter.log("🌐 AppDelegate: Updating HTTP server...")
                // Update HTTP server
                self.httpServer.updateTrackData(
                    trackName: trackInfo.name,
                    artist: trackInfo.artist,
                    album: trackInfo.album,
                    persistentID: trackInfo.persistentID,
                    isPlaying: true,
                    artworkBase64: artworkBase64
                )
                self.httpServer.updateAudioConfig(
                    sampleRate: rate,
                    bitDepth: 32,
                    deviceName: AudioManager.getOutputDeviceName() ?? "Unknown"
                )
                LogWriter.log("✅ AppDelegate: HTTP server updated")

                LogWriter.log("📡 AppDelegate: Broadcasting via WebSocket...")
                // Broadcast via WebSocket
                self.webSocketServer.broadcastTrackUpdate(
                    trackName: trackInfo.name,
                    artist: trackInfo.artist,
                    album: trackInfo.album,
                    persistentID: trackInfo.persistentID,
                    isPlaying: true,
                    artworkBase64: artworkBase64
                )
                self.webSocketServer.broadcastAudioConfigUpdate(
                    sampleRate: rate,
                    bitDepth: 32,
                    deviceName: AudioManager.getOutputDeviceName() ?? "Unknown"
                )
                LogWriter.log("✅ AppDelegate: WebSocket broadcast completed")

                LogWriter.log("🎵 AppDelegate: ========================================")
                LogWriter.log("🎵 AppDelegate: TRACK CHANGE PROCESSING COMPLETE")
                LogWriter.log("🎵 AppDelegate: ========================================")
            }
        }

        trackChangeMonitor.startMonitoring()
        LogWriter.log("✅ AppDelegate: Track monitor setup completed")
    }

    func updateMenu() {
        let menu = NSMenu()

        let deviceName = AudioManager.getOutputDeviceName() ?? "Unknown"
        menu.addItem(withTitle: "🎧 Device: \(deviceName)", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: String(format: "📈 Sample Rate: %.1f kHz", currentSampleRate / 1000.0), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "🧪 Bit Depth: 32-bit (fixed)", action: nil, keyEquivalent: "")

        let overrideMenu = NSMenu()
        let supportedRates = AudioManager.getAvailableSampleRates()
        for rate in supportedRates {
            let label = String(format: "%.1f kHz", rate / 1000.0)
            let item = NSMenuItem(title: label, action: #selector(overrideSampleRate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rate
            overrideMenu.addItem(item)
        }
        let overrideSubmenu = NSMenuItem(title: "🎚️ Override Sample Rate", action: nil, keyEquivalent: "")
        menu.setSubmenu(overrideMenu, for: overrideSubmenu)
        menu.addItem(overrideSubmenu)

        let midiItem = NSMenuItem(title: "🎛️ Open Audio MIDI Setup", action: #selector(openAudioMIDISetup), keyEquivalent: "")
        midiItem.target = self
        menu.addItem(midiItem)
        menu.addItem(NSMenuItem.separator())

        let toggleMenu = NSMenu()
        for feature in FeatureToggle.allCases {
            let state = FeatureToggleManager.isEnabled(feature)
            let title = state ? "✅ \(feature.displayName)" : "🚫 \(feature.displayName)"
            let item = NSMenuItem(title: title, action: #selector(toggleFeature(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = feature
            toggleMenu.addItem(item)
        }
        let toggleSubmenu = NSMenuItem(title: "🛠️ Features", action: nil, keyEquivalent: "")
        menu.setSubmenu(toggleMenu, for: toggleSubmenu)
        menu.addItem(toggleSubmenu)

        menu.addItem(NSMenuItem.separator())

        // Network status info
        let networkItem = NSMenuItem(title: "🌐 Network: Servers running", action: nil, keyEquivalent: "")
        networkItem.isEnabled = false
        menu.addItem(networkItem)

        menu.addItem(NSMenuItem.separator())

        // Version + Build (disabled, greyed out)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Version \(version) (Build \(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(withTitle: "Quit MAC4MAC", action: #selector(quitApp), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    @objc func overrideSampleRate(_ sender: NSMenuItem) {
        guard let rate = sender.representedObject as? Double else { return }
        AudioManager.setOutputSampleRate(to: rate)
        currentSampleRate = rate
        updateStatusBarTitle()
        updateMenu()
    }

    @objc func openAudioMIDISetup() {
        let path = "/System/Applications/Utilities/Audio MIDI Setup.app"
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                LogWriter.log("❌ AppDelegate: Failed to open Audio MIDI Setup: \(error.localizedDescription)")
            } else {
                LogWriter.log("🎛️ AppDelegate: Audio MIDI Setup launched")
            }
        }
    }

    @objc func toggleFeature(_ sender: NSMenuItem) {
        guard let feature = sender.representedObject as? FeatureToggle else { return }
        FeatureToggleManager.toggle(feature)
        LogWriter.log("🛠️ AppDelegate: Toggled \(feature.displayName) → \(FeatureToggleManager.isEnabled(feature))")
        updateMenu()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTriggerListener?.cancel()
        webSocketServer.stopServer()
    }
}
