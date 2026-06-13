import Foundation
import UserNotifications

class UpdateChecker: ObservableObject {
    @Published var latestVersion: String? = nil
    @Published var updateAvailable: Bool = false
    
    // Configurable GitHub releases API URL
    private let githubAPIURL = "https://api.github.com/repos/nanyang/SDBackupApp/releases/latest"
    private let lastCheckKey = "lastUpdateCheckDate"
    private let cachedVersionKey = "cachedLatestVersion"
    
    init() {
        loadCachedResult()
        checkForUpdates()
    }
    
    private func loadCachedResult() {
        if let cached = UserDefaults.standard.string(forKey: cachedVersionKey) {
            latestVersion = cached
            updateAvailable = isNewerVersion(cached, than: AppEnvironment.appVersion)
        }
    }
    
    func checkForUpdates() {
        // Don't check more than once per day
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            if Date().timeIntervalSince(lastCheck) < 86400 {
                return
            }
        }
        
        guard let url = URL(string: githubAPIURL) else { return }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                
                DispatchQueue.main.async {
                    self.latestVersion = version
                    self.updateAvailable = self.isNewerVersion(version, than: AppEnvironment.appVersion)
                    
                    // Cache result
                    UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)
                    UserDefaults.standard.set(version, forKey: self.cachedVersionKey)
                    
                    if self.updateAvailable {
                        self.sendUpdateNotification(version: version)
                    }
                }
            }
        }.resume()
    }
    
    private func sendUpdateNotification(version: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
        let msg = L10n.translate("updateAvailable", lang: lang)
            .replacingOccurrences(of: "{version}", with: version)
        
        let content = UNMutableNotificationContent()
        content.title = L10n.translate("appName", lang: lang)
        content.body = msg
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "updateCheck-\(version)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(newParts.count, currentParts.count) {
            let n = i < newParts.count ? newParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }
}
