import Foundation
import AppKit
import ImageIO
import UserNotifications

struct ConnectedCard: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String          // 原始卷名
    var customName: String?   // 用户自定义名
    let format: String
    let totalSpace: Int64
    let freeSpace: Int64
    var isTrusted: Bool
    var selectedSourcePaths: [String] = []
    
    var displayName: String { customName ?? name }
    
    static func == (lhs: ConnectedCard, rhs: ConnectedCard) -> Bool {
        lhs.url == rhs.url && lhs.customName == rhs.customName && lhs.isTrusted == rhs.isTrusted && lhs.selectedSourcePaths == rhs.selectedSourcePaths
    }
}

struct BackupLog: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let sourceName: String
    var destinationPath: String?
    let dataTransferredStr: String 
    let fileCount: Int
    let durationSeconds: TimeInterval
    let result: String 
}

class BackupManager: ObservableObject {
    @Published var isWorking: Bool = false {
        didSet {
            if isWorking {
                DispatchQueue.main.async {
                    self.isWorkingAnimationToggle = false
                    self.animationTimer?.invalidate()
                    self.animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                        self?.isWorkingAnimationToggle.toggle()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.animationTimer?.invalidate()
                    self.animationTimer = nil
                    self.isWorkingAnimationToggle = false
                }
            }
        }
    }
    @Published var etaText: String = ""
    private var currentProcess: Process?
    private var currentSourceVolumeURL: URL?
    private let sourcePathsKey = "deviceSourcePaths"
    private let ignoredDevicesKey = "ignoredDeviceIDs"
    private let customNamesKey = "customCardNames"
    private var ignoredDeviceIDs: Set<String> = []
    
    // 多卡排队备份
    private struct PendingBackup {
        let volumeURL: URL
        let sourceURLs: [URL]
    }
    private var backupQueue: [PendingBackup] = []
    
    @Published var currentActionTextKey = "ready"
    
    @Published var progressPercent: Double = 0.0
    @Published var progressDetailText: String = "" 
    private let sleepPreventer = SleepPreventer()
    
    @Published var connectedCards: [ConnectedCard] = []
    @Published var backupHistory: [BackupLog] = []
    
    private let historyKey = "backupHistoryLog"
    private let trustedDevicesKey = "trustedDevices"
    @Published var dummyTrigger = false 
    @Published var isWorkingAnimationToggle: Bool = false
    @Published var trustedDeviceIDs: Set<String> = []
    private var animationTimer: Timer?
    
    init() {
        requestNotificationPermission()
        loadTrustedDevices()
        loadHistory()
        checkExistingVolumes()
        checkStaleStateFile()
        startListening()
    }
    
    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("INFO: UNUserNotificationCenter skipped (no bundle ID).")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    private func sendNotification(titleKey: String, body: String, isSuccess: Bool = true) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("Notification (Term): [\(body)]")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = L10n.translate(titleKey, lang: UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans")
        content.body = body
        content.sound = isSuccess ? .default : .defaultCritical
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let logs = try? JSONDecoder().decode([BackupLog].self, from: data) {
            self.backupHistory = logs
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(backupHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private func loadTrustedDevices() {
        if let data = UserDefaults.standard.array(forKey: trustedDevicesKey) as? [String] {
            trustedDeviceIDs = Set(data)
        }
        if let data = UserDefaults.standard.array(forKey: ignoredDevicesKey) as? [String] {
            ignoredDeviceIDs = Set(data)
        }
    }
    
    func toggleTrust(for url: URL) {
        let deviceID = url.lastPathComponent
        DispatchQueue.main.async {
            if self.trustedDeviceIDs.contains(deviceID) {
                self.trustedDeviceIDs.remove(deviceID)
            } else {
                self.trustedDeviceIDs.insert(deviceID)
            }
            UserDefaults.standard.set(Array(self.trustedDeviceIDs), forKey: self.trustedDevicesKey)
            
            // 更新对应卡片状态
            if let idx = self.connectedCards.firstIndex(where: { $0.url == url }) {
                self.connectedCards[idx].isTrusted = self.trustedDeviceIDs.contains(deviceID)
                // 强制触发 UI 刷新
                let updatedCard = self.connectedCards[idx]
                self.connectedCards.remove(at: idx)
                self.connectedCards.insert(updatedCard, at: idx)
                
                self.dummyTrigger.toggle()
            }
        }
    }
    
    func saveSourcePaths(for card: ConnectedCard) {
        let deviceID = card.url.lastPathComponent
        var dict = UserDefaults.standard.dictionary(forKey: sourcePathsKey) as? [String: [String]] ?? [:]
        dict[deviceID] = card.selectedSourcePaths
        UserDefaults.standard.set(dict, forKey: sourcePathsKey)
    }
    
    func renameCard(url: URL, newName: String) {
        let deviceID = url.lastPathComponent
        var dict = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String] ?? [:]
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: deviceID)
        } else {
            dict[deviceID] = trimmed
        }
        UserDefaults.standard.set(dict, forKey: customNamesKey)
        
        DispatchQueue.main.async {
            if let idx = self.connectedCards.firstIndex(where: { $0.url == url }) {
                self.connectedCards[idx].customName = trimmed.isEmpty ? nil : trimmed
                self.dummyTrigger.toggle()
            }
        }
    }
    
    func resetAllSettings() {
        let identifier = Bundle.main.bundleIdentifier ?? "SDBackupApp"
        UserDefaults.standard.removePersistentDomain(forName: identifier)
        UserDefaults.standard.synchronize()
        
        DispatchQueue.main.async {
            self.connectedCards = []
            self.trustedDeviceIDs = []
            self.ignoredDeviceIDs = []
            self.backupHistory = []
            self.loadTrustedDevices()
            self.checkExistingVolumes()
            self.dummyTrigger.toggle()
        }
    }
    
    func ignoreDevice(for url: URL) {
        let deviceID = url.lastPathComponent
        ignoredDeviceIDs.insert(deviceID)
        UserDefaults.standard.set(Array(ignoredDeviceIDs), forKey: ignoredDevicesKey)
        removeCard(url: url)
    }
    
    func addLog(_ log: BackupLog) {
        DispatchQueue.main.async {
            self.backupHistory.insert(log, at: 0)
            if self.backupHistory.count > 100 {
                self.backupHistory.removeLast()
            }
            self.saveHistory()
        }
    }
    
    func manualBackupAll() {
        backupQueue.removeAll()
        for card in connectedCards {
            let urls: [URL]
            if card.selectedSourcePaths.isEmpty {
                urls = [card.url.appendingPathComponent("DCIM")]
            } else {
                urls = card.selectedSourcePaths.map { URL(fileURLWithPath: $0) }
            }
            if isWorking {
                backupQueue.append(PendingBackup(volumeURL: card.url, sourceURLs: urls))
            } else {
                startBackupProcess(volumeURL: card.url, sourceURLs: urls)
            }
        }
    }

    func ejectCard(url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            // 稍等一秒后从 UI 移除
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.removeCard(url: url)
            }
        }
    }

    func removeCard(url: URL) {
        connectedCards.removeAll { $0.url == url }
    }
    
    func cancelTransfer() {
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
            DispatchQueue.main.async {
                self.isWorking = false
                self.progressDetailText = "已中断"
                self.etaText = ""
            }
        }
    }
    
    private func checkExistingVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        if let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) {
            for url in urls {
                if isPotentialMemoryCard(at: url) {
                    addCard(url: url)
                }
            }
        }
    }
    
    private func addCard(url: URL) {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        var name = url.lastPathComponent
        var format = "未知"
        var total: Int64 = 0
        var free: Int64 = 0
        
        if let r = try? url.resourceValues(forKeys: Set(keys)) {
            if let vn = r.volumeName { name = vn }
            if let fmt = r.volumeLocalizedFormatDescription { 
                format = fmt.replacingOccurrences(of: " (Encrypted)", with: "", options: .caseInsensitive).replacingOccurrences(of: "（已加密）", with: "") 
            }
            if let cap = r.volumeTotalCapacity { total = Int64(cap) }
            if let avail = r.volumeAvailableCapacity { free = Int64(avail) }
        }
        
        let deviceID = url.lastPathComponent
        let isTrusted = trustedDeviceIDs.contains(deviceID)
        
        // 加载记忆的源路径
        var savedSources: [String] = []
        if let dict = UserDefaults.standard.dictionary(forKey: sourcePathsKey) as? [String: [String]], let paths = dict[deviceID] {
            savedSources = paths
        }
        
        // 加载自定义名称
        var customName: String? = nil
        if let dict = UserDefaults.standard.dictionary(forKey: customNamesKey) as? [String: String], let saved = dict[deviceID] {
            customName = saved
        }
        
        let card = ConnectedCard(url: url, name: name, customName: customName, format: format, totalSpace: total, freeSpace: free, isTrusted: isTrusted, selectedSourcePaths: savedSources)
        DispatchQueue.main.async {
            if !self.connectedCards.contains(where: { $0.url == url }) {
                self.connectedCards.append(card)
                self.dummyTrigger.toggle()
                
                // 卡片添加完成后，检查是否需要自动备份
                self.triggerAutoBackupIfNeeded(for: card)
            }
        }
    }
    
    /// 在卡片实际加入 connectedCards 后调用，避免竞态导致只备份 DCIM
    private func triggerAutoBackupIfNeeded(for card: ConnectedCard) {
        let userDefaults = UserDefaults.standard
        if userDefaults.object(forKey: "autoBackupOnMount") == nil {
            userDefaults.set(true, forKey: "autoBackupOnMount")
        }
        let isAutoBackup = userDefaults.bool(forKey: "autoBackupOnMount")
        let isTrusted = trustedDeviceIDs.contains(card.url.lastPathComponent)
        
        guard isAutoBackup && isTrusted else { return }
        
        if !card.selectedSourcePaths.isEmpty {
            let urls = card.selectedSourcePaths.map { URL(fileURLWithPath: $0) }
            startBackupProcess(volumeURL: card.url, sourceURLs: urls)
        } else {
            let dcimURL = card.url.appendingPathComponent("DCIM")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dcimURL.path, isDirectory: &isDir) && isDir.boolValue {
                startBackupProcess(volumeURL: card.url, sourceURLs: [dcimURL])
            }
        }
    }
    
    private func startListening() {
        let ws = NSWorkspace.shared
        let nc = ws.notificationCenter
        
        nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                self.handleMountEvent(volumeURL: volumeURL)
            }
        }
        
        nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                self.removeCard(url: volumeURL)
                if self.isWorking, self.currentSourceVolumeURL == volumeURL {
                    self.cancelTransfer()
                    self.sendNotification(titleKey: "appName", body: "⚠️ 存储卡在传输过程中被意外拔出！请重新插入后重试。", isSuccess: false)
                    self.addLog(BackupLog(date: Date(), sourceName: volumeURL.lastPathComponent, destinationPath: "", dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "意外中断 (拔出)"))
                }
            }
        }
    }
    
    private func isPotentialMemoryCard(at url: URL) -> Bool {
        if url.path == "/" || url.path == "/System/Volumes/Data" { return false }
        let deviceID = url.lastPathComponent
        if ignoredDeviceIDs.contains(deviceID) { return false }
        
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeLocalizedFormatDescriptionKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
        
        let isInternal = values.volumeIsInternal ?? true
        let isEjectable = values.volumeIsEjectable ?? false
        let isRemovable = values.volumeIsRemovable ?? false
        let name = values.volumeName ?? url.lastPathComponent
        let totalCapacity = Int64(values.volumeTotalCapacity ?? 0)
        let format = values.volumeLocalizedFormatDescription ?? ""
        
        if isInternal && url.path == "/" { return false }
        
        let lowerName = name.lowercased()
        if lowerName.contains("time machine") || lowerName.contains("backup") || lowerName.contains("tm-") || lowerName.contains("time-machine") {
            return false
        }
        
        let lowerFormat = format.lowercased()
        let isAppleFormat = lowerFormat.contains("apfs") || lowerFormat.contains("mac os extended") || lowerFormat.contains("hfs")
        
        if isRemovable && isEjectable { return true }
        
        if isEjectable {
            if isAppleFormat {
                let cameraPaths = ["DCIM", "PRIVATE", "VIDEO", "CLIP", "AVCHD"]
                for p in cameraPaths {
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent(p).path) {
                        return true
                    }
                }
                return false
            }

            let capacityThreshold: Int64 = 1_100_000_000_000
            if totalCapacity > capacityThreshold {
                let cameraPaths = ["DCIM", "PRIVATE", "VIDEO", "CLIP", "AVCHD"]
                for p in cameraPaths {
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent(p).path) {
                        return true
                    }
                }
                return false
            }
            
            return true
        }
        
        if url.path.hasPrefix("/Volumes/") && !isAppleFormat {
            return true
        }
        
        return false
    }
    
    private func handleMountEvent(volumeURL: URL) {
        if isPotentialMemoryCard(at: volumeURL) {
            self.addCard(url: volumeURL) // 自动备份逻辑已移入 addCard，卡片实际添加后再触发
        }
        
        let userDefaults = UserDefaults.standard
        if userDefaults.object(forKey: "autoBackupOnMount") == nil {
            userDefaults.set(true, forKey: "autoBackupOnMount")
        }
        let shouldMigrateFallback = userDefaults.bool(forKey: "autoMigrateFallback")
        
        if shouldMigrateFallback {
            tryFallbackSync()
        }
    }
    
    private func tryFallbackSync() {
        let isFallbackEnabled = UserDefaults.standard.bool(forKey: "enableFallbackPath")
        guard isFallbackEnabled else { return }
        
        let targetPath = UserDefaults.standard.string(forKey: "targetBackupPath") ?? ""
        let isTargetAvailable = !targetPath.isEmpty && FileManager.default.fileExists(atPath: targetPath)
        
        let fallbackPath = getFallbackPath()
        
        if isTargetAvailable && FileManager.default.fileExists(atPath: fallbackPath) {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: fallbackPath) {
                let hasFilesToSync = !contents.filter { $0 != ".DS_Store" }.isEmpty
                if hasFilesToSync {
                    print("Migrating fallback local backup to target drive...")
                    self.runRsync(sources: [fallbackPath], destination: targetPath, actionNameKey: "migrating", sourceName: "Fallback Cache", isMigrating: true, sourceVolumeURL: nil)
                }
            }
        }
    }
    
    private func getFallbackPath() -> String {
        let isFallbackEnabled = UserDefaults.standard.bool(forKey: "enableFallbackPath")
        guard isFallbackEnabled else { return "" }
        
        var fallbackPath = UserDefaults.standard.string(forKey: "localBackupPath") ?? ""
        if fallbackPath.isEmpty {
            if let picURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
                fallbackPath = picURL.appendingPathComponent("SDBackup_Fallback").path
            }
        }
        return fallbackPath
    }
    
    func startBackupProcess(volumeURL: URL, sourceURLs: [URL]) {
        let targetPath = UserDefaults.standard.string(forKey: "targetBackupPath") ?? ""
        let isTargetAvailable = !targetPath.isEmpty && FileManager.default.fileExists(atPath: targetPath)
        let fallbackPath = getFallbackPath()
        
        let destination: String
        if isTargetAvailable {
            destination = targetPath
        } else if !fallbackPath.isEmpty {
            destination = fallbackPath
        } else {
            print("Both main target and fallback paths are unavailable. Backup aborted.")
            return
        }
        
        // 建议7: 备份前检查目标空间是否足够
        let sourceName = volumeURL.lastPathComponent
        var totalSourceSize: UInt64 = 0
        for srcURL in sourceURLs {
            if let enumerator = FileManager.default.enumerator(at: srcURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        totalSourceSize += UInt64(size)
                    }
                }
            }
        }
        
        let destURL = URL(fileURLWithPath: destination)
        if let destValues = try? destURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let availableCapacity = destValues.volumeAvailableCapacity {
            let freeBytes = UInt64(availableCapacity)
            // 源大小的 1.1 倍作为安全余量（考虑 --backup 保留旧文件）
            let requiredBytes = totalSourceSize + totalSourceSize / 10
            if freeBytes < requiredBytes {
                let freeGB = Double(freeBytes) / 1_000_000_000
                let needGB = Double(requiredBytes) / 1_000_000_000
                let msg = String(format: "⚠️ 目标空间不足: 需要 %.1f GB，仅剩 %.1f GB", needGB, freeGB)
                DispatchQueue.main.async {
                    self.sendNotification(titleKey: "appName", body: "\(sourceName) \(msg)", isSuccess: false)
                    self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "空间不足 (需\(String(format: "%.1f", needGB))GB，剩\(String(format: "%.1f", freeGB))GB)"))
                }
                return
            }
        }
        
        self.runRsync(sources: sourceURLs.map { $0.path }, destination: destination, actionNameKey: "working", sourceName: sourceName, isMigrating: false, sourceVolumeURL: volumeURL)
    }
    
    private func buildRsyncFilterArgs(mode: FileFilterMode, extensions: String) -> [String] {
        let extArray = extensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !extArray.isEmpty else { return [] }
        
        var filterArgs: [String] = []
        
        if mode == .include {
            filterArgs.append("--include=*/") // Include all directories to traverse
            for ext in extArray {
                let baseExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
                filterArgs.append("--include=*.\(baseExt)")
                filterArgs.append("--include=*.\(baseExt.uppercased())")
            }
            filterArgs.append("--exclude=*") // Exclude everything else
        } else {
            // Exclude mode
            for ext in extArray {
                let baseExt = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
                filterArgs.append("--exclude=*.\(baseExt)")
                filterArgs.append("--exclude=*.\(baseExt.uppercased())")
            }
        }
        
        return filterArgs
    }
    
    private func runRsync(sources: [String], destination: String, actionNameKey: String, sourceName: String, isMigrating: Bool, sourceVolumeURL: URL?) {
        guard !isWorking else { return }
        guard !sources.isEmpty else { return }
        
        if !FileManager.default.fileExists(atPath: destination) {
            try? FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true, attributes: nil)
        }
        
        DispatchQueue.main.async {
            self.isWorking = true
            self.currentSourceVolumeURL = sourceVolumeURL
            self.currentActionTextKey = actionNameKey
            self.progressPercent = 0.0
            self.progressDetailText = "" 
            self.etaText = ""
        }
        
        let startTime = Date()
        let defaults = UserDefaults.standard
        let enableVerif = defaults.bool(forKey: "enableVerification")
        let verifLevel = PostTransferVerificationLevel(rawValue: defaults.integer(forKey: "verificationLevel")) ?? .basic
        let strategy = BackupComparisonStrategy(rawValue: defaults.integer(forKey: "comparisonStrategy")) ?? .updateIfModified
        
        let enableFilter = defaults.bool(forKey: "enableFileFilter")
        let filterMode = FileFilterMode(rawValue: defaults.integer(forKey: "fileFilterMode")) ?? .include
        let filterExtensions = defaults.string(forKey: "allowedFileExtensions") ?? ""
        
        let ejectOnFinish = defaults.bool(forKey: "ejectOnFinish")
        let openFinderOnFinish = defaults.bool(forKey: "openFinderOnFinish")
        let preventSleep = defaults.bool(forKey: "preventSleep")

        DispatchQueue.global(qos: .userInitiated).async {
            var totalFilesToTransfer: Int = 0
            var totalBytesToTransfer: Int64 = 0
            
            // --- Feature 5: Check for existing lock file ---
            let lockPath = (destination as NSString).appendingPathComponent(".sdbackup_lock")
            if let lockData = FileManager.default.contents(atPath: lockPath),
               let lockJSON = try? JSONSerialization.jsonObject(with: lockData) as? [String: Any],
               let pid = lockJSON["pid"] as? Int32 {
                if self.isProcessAlive(pid) {
                    DispatchQueue.main.async {
                        self.isWorking = false
                        self.sendNotification(titleKey: "appName", body: "⚠️ \(sourceName) 备份已在另一进程中运行 (PID: \(pid))", isSuccess: false)
                    }
                    return
                }
                // Stale lock, will be overwritten
            }
            
            // --- Dry Run ---
            let dryRunProcess = Process()
            dryRunProcess.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            var dryArgs = ["-an", "--whole-file", "--out-format=%i %l"] // -n for dry run, -W for whole-file performance; %l = file length
            
            if enableVerif && verifLevel != .basic { dryArgs.append("--checksum") }
            if strategy == .skipIfExists { dryArgs.append("--ignore-existing") } else { dryArgs.append("-u") }
            
            let filterArgs = enableFilter ? self.buildRsyncFilterArgs(mode: filterMode, extensions: filterExtensions) : []
            dryArgs.append(contentsOf: filterArgs)
            
            for s in sources { dryArgs.append(s) }
            dryArgs.append(destination)
            dryRunProcess.arguments = dryArgs
            
            let dryPipe = Pipe()
            dryRunProcess.standardOutput = dryPipe
            
            do {
                try dryRunProcess.run()
                let data = dryPipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        // Format: "%i %l" — flags then file size
                        let dryParts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                        if dryParts.count >= 1 {
                            let flags = String(dryParts[0])
                            if (flags.contains(">f") || flags.contains("<f") || flags.contains("cf")) && !flags.contains(".f") {
                                totalFilesToTransfer += 1
                                if dryParts.count >= 2, let fileSize = Int64(dryParts[1]) {
                                    totalBytesToTransfer += fileSize
                                }
                            }
                        }
                    }
                }
                dryRunProcess.waitUntilExit()
                
                let dryExitCode = dryRunProcess.terminationStatus
                if dryExitCode != 0 {
                    // On error, track card health
                    if !isMigrating, let volURL = sourceVolumeURL {
                        self.trackCardError(volURL: volURL, exitCode: dryExitCode)
                    }
                    DispatchQueue.main.async {
                        self.isWorking = false
                        self.sendNotification(titleKey: "appName", body: "⚠️ \(sourceName) 备份预检失败 (Exit: \(dryExitCode))，请检查存储卡连接。", isSuccess: false)
                        self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "预检失败 (Exit: \(dryExitCode))"))
                    }
                    return
                }
            } catch { 
                print("Dry run failed: \(error)")
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.sendNotification(titleKey: "appName", body: "⚠️ \(sourceName) 备份预检失败: \(error.localizedDescription)", isSuccess: false)
                    self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "预检异常"))
                }
                return
            }
            
            if totalFilesToTransfer == 0 {
                // Reset card error count on successful dry run (no errors detected)
                if !isMigrating, let volURL = sourceVolumeURL {
                    self.resetCardErrorCount(volURL: volURL)
                }
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "无新文件"))
                }
                return
            }
            
            // --- Show estimate before real run ---
            let estimateMB = Double(totalBytesToTransfer) / 1_000_000
            let estimateDataStr: String
            if estimateMB > 1000 {
                estimateDataStr = String(format: "%.2f GB", estimateMB / 1000)
            } else {
                estimateDataStr = String(format: "%.0f MB", estimateMB)
            }
            // Rough estimate: ~50 MB/s for SD card
            let estimatedSeconds = max(1, Int(estimateMB / 50))
            let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
            let estimateMsg = L10n.translate("backupEstimate", lang: lang)
                .replacingOccurrences(of: "{files}", with: "\(totalFilesToTransfer)")
                .replacingOccurrences(of: "{size}", with: estimateDataStr)
                .replacingOccurrences(of: "{seconds}", with: "\(estimatedSeconds)")
            DispatchQueue.main.async {
                self.progressDetailText = estimateMsg
            }
            
            // --- Feature 5: Write lock file ---
            let lockData: [String: Any] = [
                "source": sourceName,
                "started": ISO8601DateFormatter().string(from: Date()),
                "pid": ProcessInfo.processInfo.processIdentifier
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: lockData) {
                FileManager.default.createFile(atPath: lockPath, contents: jsonData)
            }
            
            // --- Feature 6: Write initial state file ---
            let statePath = (destination as NSString).appendingPathComponent(".sdbackup_state.json")
            let stateData: [String: Any] = [
                "source": sourceName,
                "totalFiles": totalFilesToTransfer,
                "started": ISO8601DateFormatter().string(from: Date())
            ]
            if let jsonStateData = try? JSONSerialization.data(withJSONObject: stateData) {
                FileManager.default.createFile(atPath: statePath, contents: jsonStateData)
            }
            
            // --- Real Run ---
            let process = Process()
            self.currentProcess = process
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            
            // -a (archive), -W (whole-file)
            var args = ["-q", "/dev/null", "/usr/bin/rsync", "-aW", "--out-format=%i %n %l"]
            
            if strategy == .skipIfExists { args.append("--ignore-existing") } else { args.append("-u") }
            if enableVerif && verifLevel != .basic { args.append("--checksum") }
            if isMigrating { args.append("--remove-source-files") }
            
            args.append("--partial")
            args.append("--backup")
            args.append("--suffix=_\(Int(Date().timeIntervalSince1970))")
            
            args.append(contentsOf: filterArgs)
            
            for s in sources { args.append(s) }
            args.append(destination)
            process.arguments = args
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            var transferredBytes: Int64 = 0
            var copiedFilesCount: Int = 0
            var errorOutput = ""
            // Feature 1: Track file categories
            var fileCategoryCounts: [String: Int] = ["photo": 0, "video": 0, "metadata": 0, "other": 0]
            
            if preventSleep { self.sleepPreventer.startPreventingSleep(reason: "SD Backup: \(sourceName)") }
            
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8) { errorOutput += str }
            }
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                let lines = str.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                        if parts.count == 3 {
                            let flags = String(parts[0])
                            if (flags.contains(">f") || flags.contains("<f") || flags.contains("cf")) && !flags.contains(".f") {
                            if let size = Int64(parts[2]) {
                                transferredBytes += size
                                copiedFilesCount += 1
                                // Feature 1: Categorize file by extension
                                let filename = String(parts[1])
                                let ext = (filename as NSString).pathExtension.lowercased()
                                switch ext {
                                case "jpg", "jpeg", "heif", "heic", "arw", "cr2", "cr3", "nef", "orf", "raf", "dng":
                                    fileCategoryCounts["photo", default: 0] += 1
                                case "mov", "mp4", "m4v", "avi", "mts":
                                    fileCategoryCounts["video", default: 0] += 1
                                case "xml", "xmp":
                                    fileCategoryCounts["metadata", default: 0] += 1
                                default:
                                    fileCategoryCounts["other", default: 0] += 1
                                }
                                let elapsed = Date().timeIntervalSince(startTime)
                                let percent = min(Double(copiedFilesCount) / Double(totalFilesToTransfer), 1.0)
                                let speed = elapsed > 0 ? Double(transferredBytes) / elapsed : 0
                                
                                DispatchQueue.main.async {
                                    self.progressPercent = percent
                                    self.progressDetailText = String(format: "已传 %d/%d (%.1f MB/s)  %d%%", copiedFilesCount, totalFilesToTransfer, speed / 1_000_000, Int(percent * 100))
                                }
                                
                                // Feature 6: Update state file every 10 files
                                if copiedFilesCount % 10 == 0 {
                                    let updateData: [String: Any] = [
                                        "completedFiles": copiedFilesCount,
                                        "completedBytes": transferredBytes,
                                        "lastFile": String(parts[1]),
                                        "updated": ISO8601DateFormatter().string(from: Date())
                                    ]
                                    if let jsonData = try? JSONSerialization.data(withJSONObject: updateData) {
                                        FileManager.default.createFile(atPath: statePath, contents: jsonData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                let exitStatus = process.terminationStatus
                let duration = Date().timeIntervalSince(startTime)
                
                if exitStatus == 0 {
                    if isMigrating { for s in sources { self.cleanEmptyDirectories(at: s) } }
                    if openFinderOnFinish && copiedFilesCount > 0 {
                        DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: destination)) }
                    }
                    if ejectOnFinish && !isMigrating, let url = sourceVolumeURL { self.ejectCard(url: url) }
                    // Feature 3: Reset card error count on success
                    if !isMigrating, let volURL = sourceVolumeURL {
                        self.resetCardErrorCount(volURL: volURL)
                    }
                    
                    let transferredMB = Double(transferredBytes) / 1_000_000
                    let dataStr = transferredMB > 1000 ? String(format: "%.2f GB", transferredMB / 1000) : String(format: "%.1f MB", transferredMB)
                    // Feature 1: Build category breakdown string
                    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
                    let catPhoto = L10n.translate("catPhoto", lang: lang)
                    let catVideo = L10n.translate("catVideo", lang: lang)
                    let catMetadata = L10n.translate("catMetadata", lang: lang)
                    let catOther = L10n.translate("catOther", lang: lang)
                    let photoCount = fileCategoryCounts["photo"] ?? 0
                    let videoCount = fileCategoryCounts["video"] ?? 0
                    let metadataCount = fileCategoryCounts["metadata"] ?? 0
                    let otherCount = fileCategoryCounts["other"] ?? 0
                    var catParts: [String] = []
                    if photoCount > 0 { catParts.append("\(catPhoto) \(photoCount)") }
                    if videoCount > 0 { catParts.append("\(catVideo) \(videoCount)") }
                    if metadataCount > 0 { catParts.append("\(catMetadata) \(metadataCount)") }
                    if otherCount > 0 { catParts.append("\(catOther) \(otherCount)") }
                    let catStr = catParts.joined(separator: ", ")
                    let statMsg: String
                    if catParts.isEmpty {
                        statMsg = String(format: "已检查 %d 个文件，新增备份 %d 个 (%@)", totalFilesToTransfer, copiedFilesCount, dataStr)
                    } else {
                        statMsg = String(format: "已检查 %d 个文件，新增备份 %d 个 (%@) — %@", totalFilesToTransfer, copiedFilesCount, catStr, dataStr)
                    }
                    
                    self.sendNotification(titleKey: "appName", body: "\(sourceName) 备份完成: \(statMsg)", isSuccess: true)
                    self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: dataStr, fileCount: copiedFilesCount, durationSeconds: duration, result: "成功 (\(statMsg))"))
                } else {
                    var errorReason = "任务出错 (Exit: \(exitStatus))"
                    if exitStatus == 12 { errorReason = "存储空间不足" }
                    else if exitStatus == 10 || exitStatus == 11 || exitStatus == 23 { errorReason = "物理连接断开" }
                    else if exitStatus == 20 { errorReason = "用户手动取消" }
                    else if exitStatus == 21 { errorReason = "校验异常 (Checksum Error)" }
                    
                    // Feature 3: Track card errors
                    if !isMigrating, let volURL = sourceVolumeURL {
                        self.trackCardError(volURL: volURL, exitCode: exitStatus)
                    }
                    
                    if !errorOutput.isEmpty { print("Rsync Error: \(errorOutput)") }
                    if exitStatus != 20 { 
                        self.sendNotification(titleKey: "appName", body: "⚠️ 备份异常: \(sourceName) - \(errorReason)", isSuccess: false)
                    }
                    self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: duration, result: "失败 (\(errorReason))"))
                }
            } catch {
                print("Failed to run rsync: \(error)")
                self.addLog(BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "系统错误"))
            }
            
            // Feature 5 & 6: Clean up lock and state files
            self.deleteLockFile(at: destination)
            self.deleteStateFile(at: destination)
            
            self.sleepPreventer.stopPreventingSleep()
            DispatchQueue.main.async {
                self.isWorking = false
                self.currentProcess = nil
                self.currentSourceVolumeURL = nil
                
                // 排队机制：当前任务完成后，自动开始下一个
                if !self.backupQueue.isEmpty {
                    let next = self.backupQueue.removeFirst()
                    self.startBackupProcess(volumeURL: next.volumeURL, sourceURLs: next.sourceURLs)
                }
            }
        }
    }
    
    // MARK: - Feature 3: Card Health Tracking
    
    private let cardErrorCountsKey = "cardErrorCounts"
    private let cardErrorThreshold = 3
    
    /// Track rsync error for a specific card. Only tracks IO/connection errors (exit codes 10, 11, 23).
    private func trackCardError(volURL: URL, exitCode: Int32) {
        // Only track IO/connection errors
        guard exitCode == 10 || exitCode == 11 || exitCode == 23 else { return }
        
        let deviceID = volURL.lastPathComponent
        var counts = UserDefaults.standard.dictionary(forKey: cardErrorCountsKey) as? [String: Int] ?? [:]
        let newCount = (counts[deviceID] ?? 0) + 1
        counts[deviceID] = newCount
        UserDefaults.standard.set(counts, forKey: cardErrorCountsKey)
        
        if newCount >= cardErrorThreshold {
            let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
            let cardName = self.connectedCards.first(where: { $0.url == volURL })?.displayName ?? deviceID
            let warningMsg = L10n.translate("cardHealthWarning", lang: lang)
                .replacingOccurrences(of: "{name}", with: cardName)
                .replacingOccurrences(of: "{count}", with: "\(newCount)")
            self.sendNotification(titleKey: "appName", body: warningMsg, isSuccess: false)
        }
    }
    
    /// Reset card error count on successful backup.
    private func resetCardErrorCount(volURL: URL) {
        let deviceID = volURL.lastPathComponent
        var counts = UserDefaults.standard.dictionary(forKey: cardErrorCountsKey) as? [String: Int] ?? [:]
        if counts[deviceID] != nil && counts[deviceID]! > 0 {
            counts[deviceID] = 0
            UserDefaults.standard.set(counts, forKey: cardErrorCountsKey)
        }
    }
    
    // MARK: - Feature 4: Log Export
    
    /// Export backup history as a formatted CSV string.
    func exportLogs() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var csv = "Time,Source,Destination,Files,Size,Duration(s),Status\n"
        for log in backupHistory {
            let time = dateFormatter.string(from: log.date)
            let source = log.sourceName.replacingOccurrences(of: ",", with: ";")
            let dest = (log.destinationPath ?? "-").replacingOccurrences(of: ",", with: ";")
            let size = log.dataTransferredStr.replacingOccurrences(of: ",", with: ";")
            let status = log.result.replacingOccurrences(of: ",", with: ";")
            csv += "\(time),\(source),\(dest),\(log.fileCount),\(size),\(Int(log.durationSeconds)),\(status)\n"
        }
        return csv
    }
    
    private func cleanEmptyDirectories(at path: String) {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        var dirs = [URL]()
        for case let fileURL as URL in enumerator {
            if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir { dirs.append(fileURL) }
        }
        dirs.sort { $0.path.count > $1.path.count }
        for dir in dirs {
            if let contents = try? fileManager.contentsOfDirectory(atPath: dir.path) {
                let unhidden = contents.filter { $0 != ".DS_Store" }
                if unhidden.isEmpty { try? fileManager.removeItem(at: dir) }
            }
        }
    }
    
    // MARK: - Feature 5: Backup Lock File
    
    private func isProcessAlive(_ pid: Int32) -> Bool {
        return kill(pid, 0) == 0
    }
    
    private func deleteLockFile(at destination: String) {
        let lockPath = (destination as NSString).appendingPathComponent(".sdbackup_lock")
        try? FileManager.default.removeItem(atPath: lockPath)
    }
    
    // MARK: - Feature 6: Resume State File
    
    private func deleteStateFile(at destination: String) {
        let statePath = (destination as NSString).appendingPathComponent(".sdbackup_state.json")
        try? FileManager.default.removeItem(atPath: statePath)
    }
    
    private func checkStaleStateFile() {
        let targetPath = UserDefaults.standard.string(forKey: "targetBackupPath") ?? ""
        let fallbackPath = getFallbackPath()
        
        let pathsToCheck = [targetPath, fallbackPath].filter { !$0.isEmpty }
        
        for path in pathsToCheck {
            let statePath = (path as NSString).appendingPathComponent(".sdbackup_state.json")
            if FileManager.default.fileExists(atPath: statePath) {
                let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
                let msg = L10n.translate("incompleteBackupDetected", lang: lang)
                sendNotification(titleKey: "appName", body: msg, isSuccess: false)
                break
            }
        }
    }
}
