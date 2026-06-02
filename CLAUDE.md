# CLAUDE.md

## Project Overview

MAC4MAC is a macOS menu bar app that monitors Apple Music track changes and automatically switches the system output sample rate to match the currently playing track. It also exposes the current track/audio state and remote playback controls over local HTTP and WebSocket servers for companion clients.

The project solves the gap where macOS does not automatically keep Audio MIDI sample rate in sync with Apple Music content. Primary users are audiophiles and Apple Music listeners who want hands-off sample-rate matching and optional remote control from another device.

File repomix-output.xml contains all the files in the repository combined into one.

## Tech Stack

- Language: Swift (project build setting `SWIFT_VERSION = 5.0`)
- Platform/runtime: macOS app target (`MACOSX_DEPLOYMENT_TARGET = 15.5`)
- UI: SwiftUI (`MAC4MAC/MAC4MACApp.swift`, `MAC4MAC/ContentView.swift`, `MAC4MAC/LogReaderView.swift`)
- App lifecycle: AppKit delegate via `@NSApplicationDelegateAdaptor` (`MAC4MAC/MAC4MACApp.swift`, `MAC4MAC/AppDelegate.swift`)
- Audio APIs: CoreAudio (`MAC4MAC/Core/AudioManager.swift`)
- Music control/detection: AppleScript via `/usr/bin/osascript`, plus ScriptingBridge protocol declarations (`MAC4MAC/AppDelegate.swift`, `MAC4MAC/Monitors/TrackChangeMonitor.swift`, `MAC4MAC/Network/Mac4MacHTTPServer.swift`, `MAC4MAC/Network/Mac4MacWebSocketServer.swift`)
- Networking: Network.framework (`NWListener`, `NWConnection`, `NWBrowser`-compatible Bonjour service type)
- Service discovery: Bonjour `_mac4mac._tcp` (`MAC4MAC/Network/Mac4MacBonjourService.swift`)
- Crypto helper: CommonCrypto for WebSocket accept key SHA1 (`MAC4MAC/Network/Mac4MacWebSocketServer.swift`)
- No third-party package manager dependency is configured (`Package.resolved` not present)

Non-standard/unusual setup:

- Xcode project uses file-system synchronized groups (sources/resources lists in `project.pbxproj` are empty and folder membership is inferred).
- Local REST/WebSocket servers are built manually using raw `NWConnection` parsing/framing rather than using a web framework.

## Architecture

### Top-level directory structure

- `MAC4MAC/`: main macOS app source.
- `MAC4MAC/Core/`: cross-cutting core utilities (audio control, logging).
- `MAC4MAC/Managers/`: feature toggles and settings gatekeeping.
- `MAC4MAC/Monitors/`: track/log monitoring pipeline for detection and enrichment.
- `MAC4MAC/MusicIntegration/`: Apple Music playlist integration.
- `MAC4MAC/Network/`: HTTP server, WebSocket server, Bonjour advertisement.
- `MAC4MAC.xcodeproj/`: Xcode project and build configuration.
- `LocalTriageDetails/`: local analysis notes.
- `build/`: generated build artifacts (not source of truth).
- Root `*.swift` scripts (`musickit_test.swift`, `test_logging.swift`): ad-hoc/manual validation scripts.

### Key entry points

- App entry: `MAC4MAC/MAC4MACApp.swift` (`@main` app struct).
- Lifecycle bootstrap: `MAC4MAC/AppDelegate.swift`.
- Server bootstrap: `AppDelegate.startServers()` starts HTTP, WebSocket, Bonjour.
- Tracking bootstrap: `AppDelegate.setupTrackMonitor()` starts `TrackChangeMonitor`.
- UI entry: `MAC4MAC/ContentView.swift` tab view with main panel + log reader.

### Data flow (end-to-end)

1. `TrackChangeMonitor` polls Apple Music every second for current track persistent ID (`osascript`).
1. On track ID change, monitor emits a minimal callback immediately (priority path) and then asynchronous track metadata/artwork callbacks.
1. `AppDelegate` handles callbacks in three phases:
   - Phase 1: immediate track info broadcast to HTTP/WebSocket clients.
   - Phase 2: sample-rate detection via `LogMonitor.fetchLatestSampleRate`, then CoreAudio switch via `AudioManager.setOutputSampleRate`.
   - Phase 3/1.5: artwork update once extracted.
1. Updated state is reflected in:
   - menu bar title/menu (`updateStatusBarTitle`, `updateMenu`),
   - HTTP responses (`/track`, `/audio`, `/progress`, `/queue`),
   - WebSocket pushes (`track_update`, `audio_config_update`, `progress_update`, etc).
1. Remote control commands from HTTP `POST /control` or WebSocket `remote_command/seek_command/volume_command` are mapped to AppleScript commands against Music.app.

### Non-obvious architectural decisions

- Explicit priority sequencing is used to optimize user-perceived responsiveness: track metadata can arrive before final audio-config certainty.
- Two transport paths exist in parallel (HTTP pull + WebSocket push) with mostly shared state in `Mac4MacHTTPServer.currentTrackData` and `Mac4MacWebSocketServer` broadcasts.
- Logging is not incidental; it is structured as a first-class observability layer with module-level filtering and per-track separators (`LogWriter`).

## Domain Model

Core entities and meaning:

- `TrackChangeMonitor.TrackInfo`: local detected track snapshot (name/artist/album/persistentID/artworkData).
- `Mac4MacHTTPServer.TrackData`: server-facing canonical payload for remote clients (track + audio + device + artwork + timestamp).
- `AudioManager` state: default output device, current nominal sample rate, bit depth, available sample rates.
- `FeatureToggle`: runtime switches (`logging`, `playlistManagement`, `httpServer`, future flags).
- WebSocket message envelope (`Mac4MacWebSocketServer.WebSocketMessage`): typed server/client messages with timestamp.

Key relationships:

- `TrackInfo` events drive `TrackData` updates.
- `TrackData.sampleRate` is derived from log monitor + audio manager, not directly from Apple Music metadata.
- Remote command messages mutate Music.app state, which then feeds back into monitor/progress updates.

Domain-specific terminology used in code/docs:

- “Phase 1 / Phase 2 / Phase 1.5”: staged remote update pipeline.
- “Sample rate sync”: forcing CoreAudio output nominal sample rate to track value.
- “Fallback audio config”: sending current known config when detection times out/fails.

## Development Commands

### Install dependencies

No package installation step is required beyond Xcode command line tools; dependencies are Apple frameworks.

### Run locally

- Open project in Xcode:
  - `open MAC4MAC.xcodeproj`
- Build (Debug):
  - `xcodebuild -project MAC4MAC.xcodeproj -scheme MAC4MAC -configuration Debug build`
- Run from Xcode using scheme `MAC4MAC`.

### Tests

There is no XCTest target in this repository.

Manual script checks available:

- Logging script:
  - `swift test_logging.swift`
- MusicKit experiment script:
  - `swift musickit_test.swift`

### Build for production

- Release build:
  - `xcodebuild -project MAC4MAC.xcodeproj -scheme MAC4MAC -configuration Release build`
- Archive:
  - `xcodebuild -project MAC4MAC.xcodeproj -scheme MAC4MAC -configuration Release archive -archivePath build/MAC4MAC.xcarchive`

### Environment variables

No required environment variables were found in source. Runtime configuration is through:

- `Info.plist` permissions (`NSLocalNetworkUsageDescription`, Bonjour services, microphone usage text).
- `UserDefaults` keys for feature toggles and logging module filters.

## Code Conventions

Naming conventions:

- Types/files use PascalCase (`Mac4MacHTTPServer`, `TrackChangeMonitor`).
- Methods/properties use lowerCamelCase.
- Enum cases lowerCamelCase.
- Manager/service suffixes are common (`*Manager`, `*Service`, `*Monitor`).

Folder placement rules (observed):

- Audio/logging utilities -> `Core/`.
- User-toggle/runtime config -> `Managers/`.
- Polling/parsing listeners -> `Monitors/`.
- Network protocol surface -> `Network/`.
- Apple Music playlist-specific behavior -> `MusicIntegration/`.

Consistent patterns:

- Heavy use of `Process` + `osascript` for Music.app integration.
- Event fan-out from monitor into both UI and remote interfaces.
- Defensive fallbacks for missing data/timeouts (e.g., keep current sample rate, send fallback config).
- Logging macros/wrappers over direct `print` in most production paths.

Patterns explicitly avoided (or being corrected):

- The codebase documents ongoing efforts against monolithic files and mixed concerns; new work should avoid adding cross-layer logic back into large orchestration files.
- Avoid introducing external dependencies for networking where existing raw Network.framework pipeline is already established.

## Testing Approach

- Test framework/runner: no formal unit-test runner configured in project targets.
- Test location: root-level ad-hoc scripts (`test_logging.swift`, `musickit_test.swift`).
- What is tested:
  - Logging rotation/format behavior (script-based).
  - Exploratory MusicKit authorization/player access checks (script-based).
- What is not comprehensively tested:
  - End-to-end monitor -> sample-rate switch -> remote broadcast in automated CI.
  - HTTP/WebSocket contract regression tests.

Run a single test file:

- `swift test_logging.swift`
- `swift musickit_test.swift`

## External Integrations

Critical path integrations:

- Apple Music app control/introspection via AppleScript and ScriptingBridge declarations.
- CoreAudio default output device sample-rate mutation.
- Local-network API surface:
  - HTTP server on port 8989 (hardcoded).
  - WebSocket server on port 8990 (hardcoded).
  - Bonjour advertisement `_mac4mac._tcp` with TXT metadata.

Optional/non-critical:

- Playlist auto-organization (`PlaylistManager`) gated behind feature toggle.

Credentials/config handling:

- No cloud credentials, DB credentials, or API keys are used.
- Local app permissions managed via entitlements/Info.plist and macOS privacy prompts.

## Known Complexity & Gotchas

1. Multi-phase track pipeline timing:
   - Track metadata, artwork, and sample-rate certainty arrive on different timelines. Race conditions can appear if features assume a single atomic update.

1. Hardcoded network ports:
   - Several components assume 8989/8990. Repo docs already flag this as a limitation and source of discovery fragility.

1. AppleScript dependency surface:
   - Playback control, progress, queue, and track metadata rely on script execution/parsing; failures are runtime and often environment/permission dependent.

1. Manual protocol handling:
   - WebSocket handshake/frame parsing is hand-rolled; any protocol changes require careful low-level updates.

1. Logging as operational dependency:
   - Sample-rate detection path depends on `LogMonitor.fetchLatestSampleRate`; if logs are stale/missing, fallback behavior is used and may mask root causes.

Areas needing caution/refactor (from in-repo docs + code shape):

- Dynamic port handling remains a known improvement area.
- `AppDelegate.swift` centralizes many responsibilities (lifecycle, network bootstrap, monitor orchestration, UI updates).

## What NOT to Touch

- Auto-generated/build outputs:
  - `build/` contents, derived data artifacts, generated module files.
- Xcode user-local settings/artifacts:
  - `*.xcworkspace/xcuserdata`, user-specific metadata.
- Provisioning/signing values that are environment/team managed unless explicitly requested.
- Port constants/protocol contract fields (`8989`, `8990`, message type strings) without coordinated updates to remote client.
- Existing feature-toggle key names in `UserDefaults` (`MAC4MAC.FeatureToggle.*`) unless migration logic is added.

If uncertain about a behavior, prefer tracing from `TrackChangeMonitor` callback emission through `AppDelegate` phase handlers and then into both `Mac4MacHTTPServer` and `Mac4MacWebSocketServer` broadcasts before changing logic.
