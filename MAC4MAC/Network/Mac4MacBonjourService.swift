import Foundation
import Network

class Mac4MacBonjourService {
    private var bonjourListener: NWListener?
    private let serviceName: String
    
    init() {
        // Use computer name for service identification
        self.serviceName = Host.current().localizedName ?? "Mac4Mac"
    }
    
    func startAdvertising() {
        LogWriter.logEssential("Starting Bonjour service advertisement")
        
        // Create TXT record with service capabilities
        let txtRecord = createTXTRecord()
        
        do {
            let service = NWListener.Service(
                name: serviceName,
                type: "_mac4mac._tcp",
                txtRecord: txtRecord
            )
            
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            bonjourListener = try NWListener(service: service, using: parameters)
            
            // CRASH FIX: Add weak self references
            bonjourListener?.serviceRegistrationUpdateHandler = { update in
                switch update {
                case .add(let endpoint):
                    LogWriter.logNormal("Bonjour service registered: \(endpoint)")
                case .remove(let endpoint):
                    LogWriter.logDebug("Bonjour service removed: \(endpoint)")
                @unknown default:
                    break
                }
            }
            
            bonjourListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    LogWriter.logNormal("Bonjour service ready for discovery")
                case .failed(let error):
                    LogWriter.logEssential("Bonjour service failed: \(error)")
                default:
                    break
                }
            }
            
            // Don't accept connections on this listener - it's just for Bonjour
            bonjourListener?.newConnectionHandler = { connection in
                connection.cancel()
            }
            
            bonjourListener?.start(queue: .global())
            LogWriter.logEssential("Advertising Mac4Mac service as '\(serviceName)'")
            
        } catch {
            LogWriter.logEssential("Failed to start Bonjour advertising: \(error)")
        }
    }
    
    func stopAdvertising() {
        bonjourListener?.cancel()
        bonjourListener = nil
        LogWriter.logEssential("Stopped Bonjour advertising")
    }
    
    private func createTXTRecord() -> NWTXTRecord {
        var txtRecord = NWTXTRecord()
        
        // Add service capabilities and info
        txtRecord["version"] = "1.0"
        txtRecord["app"] = "Mac4Mac"
        txtRecord["wsPort"] = "8990"
        txtRecord["httpPort"] = "8989"
        txtRecord["capabilities"] = "track,audio,control,artwork,progress"
        txtRecord["model"] = "macOS"
        
        // Add current system info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        txtRecord["appVersion"] = version
        
        // Add computer model info if available
        let model = getComputerModel()
        txtRecord["deviceModel"] = model
        
        LogWriter.logDebug("Created Bonjour TXT record with capabilities")
        return txtRecord
    }
    
    private func getComputerModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    // Helper to get current service info
    func getServiceInfo() -> [String: String] {
        return [
            "name": serviceName,
            "type": "_mac4mac._tcp",
            "wsPort": "8990",
            "httpPort": "8989",
            "capabilities": "track,audio,control,artwork,progress"
        ]
    }
}
