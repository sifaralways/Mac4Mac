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
        LogWriter.log("📡 Bonjour: Starting service advertisement...")
        
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
            
            bonjourListener?.serviceRegistrationUpdateHandler = { update in
                switch update {
                case .add(let endpoint):
                    LogWriter.log("✅ Bonjour: Service registered - \(endpoint)")
                case .remove(let endpoint):
                    LogWriter.log("⚠️ Bonjour: Service removed - \(endpoint)")
                @unknown default:
                    break
                }
            }
            
            bonjourListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    LogWriter.log("✅ Bonjour: Service ready for discovery")
                case .failed(let error):
                    LogWriter.log("❌ Bonjour: Service failed - \(error)")
                default:
                    break
                }
            }
            
            // Don't accept connections on this listener - it's just for Bonjour
            bonjourListener?.newConnectionHandler = { connection in
                connection.cancel()
            }
            
            bonjourListener?.start(queue: .global())
            LogWriter.log("📡 Bonjour: Advertising Mac4Mac service as '\(serviceName)'")
            
        } catch {
            LogWriter.log("❌ Bonjour: Failed to start advertising - \(error)")
        }
    }
    
    func stopAdvertising() {
        bonjourListener?.cancel()
        bonjourListener = nil
        LogWriter.log("🛑 Bonjour: Stopped advertising")
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
        
        LogWriter.log("📋 Bonjour: Created TXT record with capabilities")
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
