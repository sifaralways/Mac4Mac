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

    func applicationDidFinishLaunching(_ notification: Notification) {
        LogWriter.log("✅ App launched")
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
        trackChangeMonitor.onTrackChange = { [weak self] persistentID in
            guard let self = self else { return }
            LogWriter.log("📻 Track changed, persistentID: \(persistentID)")

            LogMonitor.fetchLatestSampleRate { rate, songName in
                LogWriter.log("🎯 Sample rate: \(rate) Hz, Song: \(songName)")
                AudioManager.setOutputSampleRate(to: rate)
                self.currentSampleRate = rate

                DispatchQueue.main.async {
                    self.statusItem?.button?.title = String(format: "🎵 %.1f kHz", rate / 1000.0)
                    self.updateMenu()
                }

                PlaylistManager.addTrack(persistentID: persistentID, sampleRate: rate)
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

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
