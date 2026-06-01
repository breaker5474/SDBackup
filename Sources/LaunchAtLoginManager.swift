import Foundation
import Combine

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    
    @Published var isEnabled: Bool = false
    
    private init() {
        refreshStatus()
    }
    
    func refreshStatus() {
        // 使用 AppleScript 检查登录项是否存在
        let appName = "SD 备份助手" // 对应 Language.swift 中的 appName
        let script = "tell application \"System Events\" to count (every login item whose name is \"\(appName)\")"
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&error)
                if error == nil {
                    DispatchQueue.main.async {
                        self.isEnabled = result.int32Value > 0
                    }
                }
            }
        }
    }
    
    func toggle() {
        let appPath = Bundle.main.bundlePath
        let appName = "SD 备份助手" 
        
        let shouldEnable = !isEnabled
        
        let script: String
        if !shouldEnable {
            script = "tell application \"System Events\" to delete (every login item whose name is \"\(appName)\")"
        } else {
            script = "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", name:\"\(appName)\", hidden:false}"
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let err = error {
                    print("AppleScript Error: \(err)")
                }
                self.refreshStatus()
            }
        }
    }
}
