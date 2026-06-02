# Dynamic Port Configuration Analysis & Recommendations

## Current Architecture Analysis

### Mac4Mac (macOS Application)

#### Hardcoded Ports
1. **HTTP Server**: Port **8989** (hardcoded in `Mac4MacHTTPServer.swift`)
2. **WebSocket Server**: Port **8990** (hardcoded in `Mac4MacWebSocketServer.swift`)
3. **Bonjour Service**: Advertises these ports in TXT record

#### Server Locations
```
MAC4MAC/Network/
├── Mac4MacHTTPServer.swift       → Port 8989 (line 6)
├── Mac4MacWebSocketServer.swift  → Port 8990 (line 12)
└── Mac4MacBonjourService.swift   → TXT record with ports (lines 79-80)
```

#### Current Initialization Flow
```swift
AppDelegate.applicationDidFinishLaunching()
  └─> startServers()
      ├─> httpServer.startServer()        // Attempts port 8989
      ├─> webSocketServer.startServer()   // Attempts port 8990
      └─> bonjourService.startAdvertising() // Publishes hardcoded ports
```

### Mac4MacRemote (iOS Application)

#### Discovery Methods (Priority Order)
1. **Bonjour Discovery** (Primary)
   - Searches for `_mac4mac._tcp` service
   - Reads TXT record to get ports: `wsPort` and `httpPort`
   - ✅ **Already reads ports from TXT record**

2. **UDP Broadcast Discovery** (Fallback)
   - Listens on port **8989** (hardcoded - line 213)
   - Sends broadcast to port **8989** (hardcoded - line 237)
   - ❌ **Hardcoded port**

3. **Network Scan Discovery** (Last Resort)
   - Tests port **8989** on subnet IPs (lines 416, 501)
   - Tests port **8990** for WebSocket (line 523)
   - ❌ **Hardcoded ports**

4. **Manual Connection**
   - Creates server with ports **8990** and **8989** (lines 483-484)
   - ❌ **Hardcoded in `verifyAndAddServer()`**

#### Discovery Flow
```swift
ServerDiscoveryManager.startDiscovery()
  ├─> startBonjourDiscovery()           // ✅ Reads ports from TXT
  ├─> startUDPBroadcastDiscovery()      // ❌ Hardcoded 8989
  └─> startIntelligentNetworkScan()     // ❌ Hardcoded 8989/8990
      └─> verifyAndAddServer()          // ❌ Hardcoded ports
```

---

## Problems with Current Implementation

### 1. **Port Conflicts**
- If ports 8989 or 8990 are in use, Mac4Mac fails to start servers
- No fallback mechanism
- No error recovery

### 2. **Inflexibility**
- Cannot run multiple Mac4Mac instances on same network
- Testing environments limited
- Cannot coexist with other services on same ports

### 3. **iOS App Limitations**
- UDP broadcast and network scan methods won't discover dynamic ports
- Manual connection requires user to know exact ports
- Fallback methods become unreliable

---

## Recommended Solution

### Architecture: **Dynamic Port Allocation with Bonjour Priority**

### Phase 1: macOS App (Mac4Mac) - Dynamic Port Binding

#### Implementation Strategy

```swift
// Shared configuration class
class NetworkConfiguration {
    static let shared = NetworkConfiguration()
    
    private(set) var httpPort: UInt16 = 0
    private(set) var wsPort: UInt16 = 0
    
    // Port ranges to try
    private let preferredHTTPPort: UInt16 = 8989
    private let preferredWSPort: UInt16 = 8990
    private let portRange: ClosedRange<UInt16> = 8989...9099
    
    func allocatePorts() -> Bool {
        // Try preferred ports first, then range
        httpPort = findAvailablePort(preferred: preferredHTTPPort)
        wsPort = findAvailablePort(preferred: preferredWSPort, excluding: [httpPort])
        
        return httpPort > 0 && wsPort > 0
    }
    
    private func findAvailablePort(preferred: UInt16, excluding: [UInt16] = []) -> UInt16 {
        // Try preferred port first
        if !excluding.contains(preferred) && isPortAvailable(preferred) {
            return preferred
        }
        
        // Try range
        for port in portRange {
            if !excluding.contains(port) && isPortAvailable(port) {
                return port
            }
        }
        
        // Fallback: let system assign
        return 0 // NWEndpoint.Port(0) = system-assigned
    }
    
    private func isPortAvailable(_ port: UInt16) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD != -1 else { return false }
        defer { close(socketFD) }
        
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return bindResult == 0
    }
}
```

#### Modified Server Classes

**Mac4MacHTTPServer.swift:**
```swift
class Mac4MacHTTPServer {
    private var listener: NWListener?
    private(set) var actualPort: UInt16 = 0  // Store actual bound port
    
    func startServer(port: UInt16 = 0) -> UInt16? {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            let nwPort: NWEndpoint.Port
            if port == 0 {
                // System-assigned port
                nwPort = NWEndpoint.Port(rawValue: 0)!
            } else {
                nwPort = NWEndpoint.Port(integerLiteral: port)
            }
            
            listener = try NWListener(using: parameters, on: nwPort)
            
            // Get actual bound port
            if let boundPort = listener?.port {
                actualPort = boundPort.rawValue
                LogWriter.logEssential("HTTP server started on port \(actualPort)")
                
                listener?.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                
                listener?.start(queue: .global())
                return actualPort
            }
        } catch {
            LogWriter.logEssential("Failed to start HTTP server: \(error)")
        }
        return nil
    }
}
```

**Mac4MacWebSocketServer.swift:**
```swift
class Mac4MacWebSocketServer {
    private var listener: NWListener?
    private(set) var actualPort: UInt16 = 0
    
    func startServer(port: UInt16 = 0) -> UInt16? {
        // Similar implementation to HTTP server
        // Returns actual bound port
    }
}
```

**Mac4MacBonjourService.swift:**
```swift
class Mac4MacBonjourService {
    private var bonjourListener: NWListener?
    private let serviceName: String
    private var httpPort: UInt16 = 0
    private var wsPort: UInt16 = 0
    
    func startAdvertising(httpPort: UInt16, wsPort: UInt16) {
        self.httpPort = httpPort
        self.wsPort = wsPort
        
        let txtRecord = createTXTRecord()
        // ... rest of implementation
    }
    
    private func createTXTRecord() -> NWTXTRecord {
        var txtRecord = NWTXTRecord()
        
        txtRecord["version"] = "1.0"
        txtRecord["app"] = "Mac4Mac"
        txtRecord["wsPort"] = String(wsPort)      // Dynamic port
        txtRecord["httpPort"] = String(httpPort)  // Dynamic port
        txtRecord["capabilities"] = "track,audio,control,artwork,progress"
        txtRecord["model"] = "macOS"
        
        return txtRecord
    }
}
```

**AppDelegate.swift:**
```swift
private func startServers() {
    LogWriter.logEssential("Allocating network ports...")
    
    // Allocate ports first
    guard NetworkConfiguration.shared.allocatePorts() else {
        LogWriter.logEssential("❌ Failed to allocate ports!")
        showPortAllocationError()
        return
    }
    
    let httpPortToUse = NetworkConfiguration.shared.httpPort
    let wsPortToUse = NetworkConfiguration.shared.wsPort
    
    LogWriter.logEssential("📡 Allocated ports - HTTP: \(httpPortToUse), WS: \(wsPortToUse)")
    
    // Start servers with allocated ports
    if let actualHTTP = httpServer.startServer(port: httpPortToUse),
       let actualWS = webSocketServer.startServer(port: wsPortToUse) {
        
        // Update configuration with actual ports (might be system-assigned)
        NetworkConfiguration.shared.httpPort = actualHTTP
        NetworkConfiguration.shared.wsPort = actualWS
        
        // Start Bonjour with actual ports
        bonjourService.startAdvertising(httpPort: actualHTTP, wsPort: actualWS)
        
        LogWriter.logEssential("✅ All servers started - HTTP: \(actualHTTP), WS: \(actualWS)")
    } else {
        LogWriter.logEssential("❌ Failed to start network services")
        showServerStartError()
    }
}

private func showPortAllocationError() {
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "Network Port Error"
        alert.informativeText = "Unable to find available network ports. Please check if other applications are using ports 8989-9099."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

### Phase 2: iOS App (Mac4MacRemote) - Minimal Changes Required

#### ✅ **Good News: Bonjour Discovery Already Works!**

The iOS app **already reads ports from the Bonjour TXT record**, so it will automatically discover dynamic ports when using Bonjour discovery (the primary method).

#### ⚠️ Issues to Fix in iOS App

**1. UDP Broadcast Discovery (Lines 213, 237)**
```swift
// CURRENT (Hardcoded):
udpListener = try NWListener(using: udpParams, on: 8989)

// RECOMMENDED (Port range or disable):
// Option A: Try multiple ports
for port in 8989...9099 {
    do {
        udpListener = try NWListener(using: udpParams, on: UInt16(port))
        break
    } catch { continue }
}

// Option B: Remove UDP broadcast entirely (rely on Bonjour)
```

**2. Network Scan Discovery (Lines 416, 501, 523)**
```swift
// CURRENT (Hardcoded):
guard let url = URL(string: "http://\(ipAddress):8989/status") else { return }

// RECOMMENDED (Port range scanning):
private func testServerAtIP(_ ipAddress: String) {
    for httpPort in 8989...9099 {
        testServerAtPort(ipAddress: ipAddress, httpPort: httpPort)
    }
}

private func testServerAtPort(ipAddress: String, httpPort: Int) {
    guard let url = URL(string: "http://\(ipAddress):\(httpPort)/status") else { return }
    
    // Test connectivity and extract wsPort from response
    URLSession.shared.dataTask(with: url) { data, response, error in
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wsPort = json["websocket_port"] as? Int else {
            return
        }
        
        // Found server with dynamic ports
        self.verifyAndAddServer(
            name: json["name"] as? String ?? "Mac4Mac",
            computerName: json["computerName"] as? String ?? "Unknown",
            ipAddress: ipAddress,
            version: json["version"] as? String ?? "1.0",
            capabilities: json["capabilities"] as? [String] ?? [],
            method: .networkScan,
            httpPort: httpPort,
            wsPort: wsPort
        )
    }.resume()
}
```

**3. Server Verification (Lines 483-484)**
```swift
// CURRENT (Hardcoded):
let server = Mac4MacServer(
    // ...
    wsPort: 8990,
    httpPort: 8989,
    // ...
)

// RECOMMENDED (Use discovered ports):
private func verifyAndAddServer(name: String, computerName: String, ipAddress: String, 
                                version: String, capabilities: [String], method: DiscoveryMethod,
                                httpPort: Int, wsPort: Int) {
    // Use provided ports instead of hardcoded values
    let server = Mac4MacServer(
        name: name,
        computerName: computerName,
        ipAddress: ipAddress,
        wsPort: wsPort,      // From discovery
        httpPort: httpPort,  // From discovery
        version: version,
        capabilities: capabilities,
        httpAvailable: httpAvailable,
        wsAvailable: wsAvailable,
        discoveryMethod: method
    )
}
```

**4. Update HTTP Server Response**

The macOS HTTP server should return its WebSocket port in `/status` endpoint:

```swift
// In Mac4MacHTTPServer.swift
private func sendStatus(connection: NWConnection) {
    let status = [
        "status": "Mac4Mac Server Running",
        "port": actualPort,  // HTTP port
        "websocket_port": NetworkConfiguration.shared.wsPort,  // Add WS port
        "version": "1.0",
        "computerName": computerName,
        // ...
    ]
}
```

---

## Best Practices Implementation

### 1. **Port Selection Priority**
```
1. Try preferred port (8989 for HTTP, 8990 for WS)
2. Try port range (8989-9099)
3. Let system assign (port 0)
4. Fail gracefully with user notification
```

### 2. **Error Handling**
- Show user-friendly error if ports unavailable
- Log actual ports to console for debugging
- Persist last successful ports for next launch

### 3. **User Notification**
```swift
// Show actual ports in menu bar
@objc func updateMenuBar() {
    let httpPort = NetworkConfiguration.shared.httpPort
    let wsPort = NetworkConfiguration.shared.wsPort
    statusItem?.title = "🎧 \(currentSampleRate) | HTTP:\(httpPort) WS:\(wsPort)"
}
```

### 4. **Compatibility Mode**
Add a preference for "Fixed Port Mode" for users who need specific ports:
```swift
// In Settings/Preferences
@AppStorage("useFixedPorts") var useFixedPorts = false
@AppStorage("fixedHTTPPort") var fixedHTTPPort = 8989
@AppStorage("fixedWSPort") var fixedWSPort = 8990
```

---

## Migration Strategy

### Phase 1: macOS App (Week 1)
1. ✅ Create `NetworkConfiguration` class
2. ✅ Modify server classes to support dynamic ports
3. ✅ Update Bonjour service to advertise actual ports
4. ✅ Update AppDelegate initialization
5. ✅ Add error handling and user notifications
6. ✅ Test with both available and occupied ports

### Phase 2: iOS App (Week 2)
1. ✅ Update HTTP `/status` response to include `websocket_port`
2. ✅ Modify `verifyAndAddServer()` to accept port parameters
3. ✅ Update network scan to try port range
4. ✅ Update UDP broadcast to try multiple ports OR remove it
5. ✅ Test discovery with dynamic ports
6. ✅ Test fallback methods

### Phase 3: Testing (Week 3)
1. Test with preferred ports available
2. Test with preferred ports occupied
3. Test with multiple Mac4Mac instances
4. Test iOS discovery from various network conditions
5. Test reconnection scenarios
6. Test after Mac4Mac restart

---

## iOS App Uplift Required?

### ✅ **Minimal Changes Required**

**Bonjour Discovery (Primary Method):**
- ✅ Already reads ports from TXT record
- ✅ No changes needed

**Fallback Methods (Secondary):**
- ⚠️ Network scan needs port range support
- ⚠️ UDP broadcast needs port range or removal
- ⚠️ `verifyAndAddServer()` needs dynamic port parameters

### Recommended Changes for iOS App

| Component | Change Required | Priority | Effort |
|-----------|----------------|----------|--------|
| Bonjour Discovery | None | N/A | None |
| Network Scan | Port range scanning | Medium | 2-3 hours |
| UDP Broadcast | Port range or removal | Low | 1-2 hours |
| Server Verification | Accept port parameters | High | 1 hour |
| Manual Connection | Add port fields (optional) | Low | 2 hours |

**Total Effort: ~6-8 hours**

---

## Summary

### Current State
- ❌ Hardcoded ports throughout codebase
- ❌ No fallback for port conflicts
- ❌ Cannot run multiple instances
- ❌ iOS fallback methods won't work with dynamic ports

### After Implementation
- ✅ Dynamic port allocation at runtime
- ✅ Automatic fallback if preferred ports occupied
- ✅ Can run multiple Mac4Mac instances
- ✅ iOS app discovers via Bonjour (primary method)
- ✅ iOS fallback methods support port ranges
- ✅ Follows macOS best practices
- ✅ Better error handling and user feedback

### iOS App Compatibility
- ✅ **Primary discovery (Bonjour) works without changes**
- ⚠️ **Fallback methods need updates** (6-8 hours of work)
- ✅ **Backwards compatible** if you keep trying preferred ports first

### Recommendation
**Implement Phase 1 (macOS) first**, test Bonjour discovery, then **implement Phase 2 (iOS)** to make fallback methods robust.
