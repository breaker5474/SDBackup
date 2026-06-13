import Foundation
import ServiceManagement
import Combine

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool = false
    
    private init() {
        refreshStatus()
    }
    
    func refreshStatus() {
        DispatchQueue.main.async {
            self.isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
    
    func toggle() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Login item error: \(error.localizedDescription)")
        }
        refreshStatus()
    }
}
