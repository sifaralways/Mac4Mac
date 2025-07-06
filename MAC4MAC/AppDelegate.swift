import AppKit
import ScriptingBridge

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogWriter.log("✅ App launched")

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

        httpServer.startServer()
        setupMenuBar()
        setupTrackMonitor()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = String(format: "🎵 %.1f kHz", currentSampleRate / 1000.0)
        }
        updateMenu()
    }

    func setupTrackMonitor() {
        LogWriter.log("📻 Starting track monitor")

        trackChangeMonitor.onTrackChange = { [weak self] trackInfo in
            guard let self = self else { return }

            LogWriter.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            LogWriter.log("🎵 New Track Detected")
            LogWriter.log("📛 Name: \(trackInfo.name)")
            LogWriter.log("💿 Album: \(trackInfo.album)")
            LogWriter.log("🆔 Persistent ID: \(trackInfo.persistentID)")
            LogWriter.log("🔍 Fetching Sample Rate...")

            LogMonitor.fetchLatestSampleRate(forTrack: trackInfo.name) { rate, songName in
                LogWriter.log("📛 Track Name: \(songName)")
                LogWriter.log("🎯 Sample rate: \(rate) Hz")

                if abs(rate - self.currentSampleRate) >= 0.5 {
                    AudioManager.setOutputSampleRate(to: rate)
                    self.currentSampleRate = rate
                    DispatchQueue.main.async {
                        self.statusItem?.button?.title = String(format: "🎵 %.1f kHz", rate / 1000.0)
                        self.updateMenu()
                    }
                } else {
                    LogWriter.log("🔄 Sample rate unchanged, no update needed")
                }

                if FeatureToggleManager.isEnabled(.playlistManagement) {
                    PlaylistManager.addTrack(persistentID: trackInfo.persistentID, sampleRate: rate)
                } else {
                    LogWriter.log("⏭️ Playlist creation skipped (disabled in feature toggles)")
                }

                self.httpServer.updateTrackData(
                    trackName: trackInfo.name,
                    artist: "Unknown Artist", // Future: extract using Music app scripting or metadata
                    album: trackInfo.album,
                    persistentID: trackInfo.persistentID,
                    isPlaying: true
                )
                self.httpServer.updateAudioConfig(
                    sampleRate: rate,
                    bitDepth: 32,
                    deviceName: AudioManager.getOutputDeviceName() ?? "Unknown"
                )

                LogWriter.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }

        trackChangeMonitor.startMonitoring()
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
        // --- New version & build number menu item ---
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
        statusItem?.button?.title = String(format: "🎵 %.1f kHz", currentSampleRate / 1000.0)
        updateMenu()
    }

    @objc func openAudioMIDISetup() {
        let path = "/System/Applications/Utilities/Audio MIDI Setup.app"
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                LogWriter.log("❌ Failed to open Audio MIDI Setup: \(error.localizedDescription)")
            } else {
                LogWriter.log("🎛️ Audio MIDI Setup launched")
            }
        }
    }

    @objc func toggleFeature(_ sender: NSMenuItem) {
        guard let feature = sender.representedObject as? FeatureToggle else { return }
        FeatureToggleManager.toggle(feature)
        LogWriter.log("🛠️ Toggled \(feature.displayName) → \(FeatureToggleManager.isEnabled(feature))")
        updateMenu()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
