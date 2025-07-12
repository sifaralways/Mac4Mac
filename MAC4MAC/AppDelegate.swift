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
    let bonjourService = Mac4MacBonjourService()
    
    // Track the last processed track to detect artwork updates
    private var lastProcessedTrackID: String?
    
    // Network permission helper
    private var permissionTriggerListener: NWListener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogWriter.logEssential("Mac4Mac launched successfully")

        // Set log level based on feature toggle
        LogWriter.currentLogLevel = FeatureToggleManager.isEnabled(.logging) ? .debug : .essential

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
            self?.startServers()
        }
        
        setupMenuBar()
        setupTrackMonitor()
    }
    
    private func startServers() {
        LogWriter.logEssential("Starting network services...")
        httpServer.startServer()
        webSocketServer.startServer()
        bonjourService.startAdvertising()
        LogWriter.logEssential("All network services started")
    }
    
    private func requestNetworkPermissions(completion: @escaping () -> Void) {
        LogWriter.logNormal("Requesting network permissions...")
        
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
                    LogWriter.logNormal("Network permission granted")
                    // Stop the permission trigger listener
                    self.permissionTriggerListener?.cancel()
                    self.permissionTriggerListener = nil
                    // Start the actual servers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        completion()
                    }
                case .remove(_):
                    LogWriter.logDebug("Network service registration removed")
                @unknown default:
                    break
                }
            }
            
            permissionTriggerListener?.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    LogWriter.logEssential("Permission trigger failed: \(error)")
                    // Start servers anyway
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        completion()
                    }
                case .ready:
                    LogWriter.logDebug("Permission trigger ready")
                default:
                    break
                }
            }
            
            permissionTriggerListener?.start(queue: .global())
            
            // Fallback timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if self.permissionTriggerListener != nil {
                    LogWriter.logNormal("Permission timeout - starting servers anyway")
                    self.permissionTriggerListener?.cancel()
                    self.permissionTriggerListener = nil
                    completion()
                }
            }
            
        } catch {
            LogWriter.logEssential("Failed to create permission trigger: \(error)")
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
        LogWriter.logEssential("Starting track monitor with priority-based processing")

        trackChangeMonitor.onTrackChange = { [weak self] trackInfo in
            guard let self = self else { return }

            LogWriter.logEssential("Track: \(trackInfo.name) by \(trackInfo.artist)")
            
            // Check if this is a minimal callback (for sample rate sync) or full callback
            let isMinimalCallback = trackInfo.artist == "Loading..." && trackInfo.album == "Loading..."
            
            // Check if this is an artwork update (same track, but with artwork)
            let isArtworkUpdate = trackInfo.artworkData != nil &&
                                 self.lastProcessedTrackID == trackInfo.persistentID
            
            if isMinimalCallback {
                // PRIORITY 1: Handle sample rate sync immediately
                self.handleSampleRateSync(for: trackInfo)
            } else if isArtworkUpdate {
                // ARTWORK UPDATE: Just update the artwork without full processing
                self.handleArtworkUpdate(for: trackInfo)
            } else {
                // PRIORITY 2 & 3: Handle full track info and updates
                self.handleFullTrackUpdate(for: trackInfo)
                self.lastProcessedTrackID = trackInfo.persistentID
            }
        }

        trackChangeMonitor.startMonitoring()

        // Force initial track update
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            LogWriter.logNormal("Triggering initial track check")
            self.trackChangeMonitor.forceTrackUpdate()
        }
    }
    
    // PRIORITY 1: Critical sample rate sync
    private func handleSampleRateSync(for trackInfo: TrackChangeMonitor.TrackInfo) {
        LogWriter.logEssential("🚨 PRIORITY: Starting immediate sample rate sync")
        
        // Timeout for Phase 2 in case sample rate detection hangs
        var phase2Completed = false
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
            if !phase2Completed {
                LogWriter.logEssential("⏰ PHASE 2 TIMEOUT: Sample rate detection took >10s, sending fallback")
                self?.sendFallbackAudioConfig()
            }
        }
        
        // Start sample rate detection immediately in background
        DispatchQueue.global().async { [weak self] in
            LogMonitor.fetchLatestSampleRate(forTrack: trackInfo.name) { [weak self] rate, _ in
                guard let self = self else { return }
                
                phase2Completed = true
                LogWriter.logEssential("🎚️ PHASE 2: Sample rate detection completed: \(rate) Hz")
                
                // Handle sample rate detection result
                if rate > 0 {
                    // Update audio output if rate is different
                    if abs(rate - self.currentSampleRate) >= 0.5 {
                        LogWriter.logEssential("📡 Audio output change needed: \(self.currentSampleRate) Hz → \(rate) Hz")
                        
                        let success = AudioManager.setOutputSampleRate(to: rate)
                        if success {
                            self.currentSampleRate = rate
                            
                            // Update UI on main thread
                            DispatchQueue.main.async {
                                self.updateStatusBarTitle()
                                self.updateMenu()
                            }
                            
                            LogWriter.logEssential("🚨 PRIORITY: Sample rate synced to \(rate) Hz")
                        } else {
                            LogWriter.logEssential("❌ FAILED: Could not change audio output sample rate")
                        }
                    } else {
                        LogWriter.logNormal("🔍 Audio output unchanged (\(rate) Hz)")
                    }
                    
                    // 🎚️ PHASE 2: ALWAYS update remote clients with detected sample rate
                    LogWriter.logEssential("🎚️ PHASE 2: Updating remote clients with \(String(format: "%.1f", rate / 1000.0)) kHz...")
                    
                    let deviceName = AudioManager.getOutputDeviceName() ?? "Unknown"
                    
                    self.httpServer.updateAudioConfig(
                        sampleRate: rate,
                        bitDepth: 32,
                        deviceName: deviceName
                    )
                    
                    self.webSocketServer.broadcastAudioConfigUpdate(
                        sampleRate: rate,
                        bitDepth: 32,
                        deviceName: deviceName
                    )
                    
                    LogWriter.logEssential("🎚️ ✅ PHASE 2 COMPLETE: Remote clients updated to \(String(format: "%.1f", rate / 1000.0)) kHz")
                    
                } else {
                    LogWriter.logEssential("❌ PHASE 2 FAILED: Sample rate detection failed (rate: \(rate))")
                    self.sendFallbackAudioConfig()
                }
            }
        }
    }
    
    private func sendFallbackAudioConfig() {
        LogWriter.logEssential("🔄 FALLBACK: Sending current rate \(String(format: "%.1f", currentSampleRate / 1000.0)) kHz to remote clients")
        
        let deviceName = AudioManager.getOutputDeviceName() ?? "Unknown"
        
        httpServer.updateAudioConfig(
            sampleRate: currentSampleRate,
            bitDepth: 32,
            deviceName: deviceName
        )
        
        webSocketServer.broadcastAudioConfigUpdate(
            sampleRate: currentSampleRate,
            bitDepth: 32,
            deviceName: deviceName
        )
        
        LogWriter.logEssential("🔄 FALLBACK COMPLETE: Remote clients notified of current rate")
    }
    
    // PRIORITY 2 & 3: Full track info processing (PHASE 1)
    private func handleFullTrackUpdate(for trackInfo: TrackChangeMonitor.TrackInfo) {
        LogWriter.logEssential("📱 PHASE 1: Sending immediate track info to remote clients")
        
        // Convert artwork to base64 if available
        var artworkBase64: String? = nil
        if let artworkData = trackInfo.artworkData {
            artworkBase64 = artworkData.base64EncodedString()
            LogWriter.logNormal("Artwork available (\(artworkData.count) bytes)")
        }

        // 📱 PHASE 1: Send track info immediately (excellent UX)
        httpServer.updateTrackData(
            trackName: trackInfo.name,
            artist: trackInfo.artist,
            album: trackInfo.album,
            persistentID: trackInfo.persistentID,
            isPlaying: true,
            artworkBase64: artworkBase64
        )

        webSocketServer.broadcastTrackUpdate(
            trackName: trackInfo.name,
            artist: trackInfo.artist,
            album: trackInfo.album,
            persistentID: trackInfo.persistentID,
            isPlaying: true,
            artworkBase64: artworkBase64
        )
        
        // Start progress tracking for new track
        webSocketServer.startProgressTracking()
        
        LogWriter.logEssential("📱 ✅ PHASE 1 COMPLETE: Track info sent to remote clients")
        LogWriter.logNormal("🖼️ Artwork will be updated in Phase 1.5 when ready...")
        LogWriter.logNormal("🔄 Audio config will be updated in Phase 2 after sample rate detection...")
        
        // PRIORITY 4: Playlist updates (lowest priority)
        if FeatureToggleManager.isEnabled(.playlistManagement) {
            DispatchQueue.global().async {
                PlaylistManager.addTrack(persistentID: trackInfo.persistentID, sampleRate: self.currentSampleRate)
            }
        }
    }
    
    // Handle artwork update without full track processing
    private func handleArtworkUpdate(for trackInfo: TrackChangeMonitor.TrackInfo) {
        LogWriter.logEssential("🖼️ ARTWORK UPDATE: Adding artwork to existing track")
        
        // Convert artwork to base64
        var artworkBase64: String? = nil
        if let artworkData = trackInfo.artworkData {
            artworkBase64 = artworkData.base64EncodedString()
            LogWriter.logNormal("🖼️ Artwork updated (\(artworkData.count) bytes)")
        }

        // Update HTTP server with artwork (keep existing track info)
        httpServer.updateTrackData(
            trackName: trackInfo.name,
            artist: trackInfo.artist,
            album: trackInfo.album,
            persistentID: trackInfo.persistentID,
            isPlaying: true,
            artworkBase64: artworkBase64
        )

        // Broadcast artwork update via WebSocket
        webSocketServer.broadcastTrackUpdate(
            trackName: trackInfo.name,
            artist: trackInfo.artist,
            album: trackInfo.album,
            persistentID: trackInfo.persistentID,
            isPlaying: true,
            artworkBase64: artworkBase64
        )
        
        LogWriter.logEssential("🖼️ ✅ ARTWORK UPDATE COMPLETE: Remote clients updated with artwork")
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
        let success = AudioManager.setOutputSampleRate(to: rate)
        if success {
            currentSampleRate = rate
            updateStatusBarTitle()
            updateMenu()
        }
    }

    @objc func openAudioMIDISetup() {
        let path = "/System/Applications/Utilities/Audio MIDI Setup.app"
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                LogWriter.logEssential("Failed to open Audio MIDI Setup: \(error.localizedDescription)")
            } else {
                LogWriter.logNormal("Audio MIDI Setup launched")
            }
        }
    }

    @objc func toggleFeature(_ sender: NSMenuItem) {
        guard let feature = sender.representedObject as? FeatureToggle else { return }
        FeatureToggleManager.toggle(feature)
        
        // Update log level if logging feature is toggled
        if feature == .logging {
            LogWriter.currentLogLevel = FeatureToggleManager.isEnabled(.logging) ? .debug : .essential
        }
        
        LogWriter.logNormal("Toggled \(feature.displayName) → \(FeatureToggleManager.isEnabled(feature))")
        updateMenu()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        LogWriter.logEssential("Mac4Mac shutting down")
        permissionTriggerListener?.cancel()
        bonjourService.stopAdvertising()
        webSocketServer.stopServer()
        trackChangeMonitor.stopMonitoring()
    }
}
