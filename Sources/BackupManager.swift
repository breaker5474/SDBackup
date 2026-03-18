import Foundation
import AppKit
import ImageIO

struct ConnectedCard: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    let format: String
    let totalSpace: Int64
    let freeSpace: Int64
    var isTrusted: Bool
    var selectedSourcePaths: [String] = [] // NEW: support multiple sources
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
                    self.animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        self.isWorkingAnimationToggle.toggle()
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
    private let sourcePathsKey = "deviceSourcePaths"
    private let ignoredDevicesKey = "ignoredDeviceIDs"
    private var ignoredDeviceIDs: Set<String> = []
    
    @Published var currentActionTextKey = "ready"
    
    @Published var progressPercent: Double = 0.0
    @Published var progressDetailText: String = "" 
    
    @Published var connectedCards: [ConnectedCard] = []
    @Published var backupHistory: [BackupLog] = []
    
    private let historyKey = "backupHistoryLog"
    private let trustedDevicesKey = "trustedDevices"
    @Published var dummyTrigger = false 
    @Published var isWorkingAnimationToggle: Bool = false
    @Published var trustedDeviceIDs: Set<String> = []
    private var animationTimer: Timer?
    
    init() {
        loadTrustedDevices()
        loadHistory()
        checkExistingVolumes()
        startListening()
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
            
            // 更新对应卡片状态 (使用全局通知或重置数组触发)
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
        for card in connectedCards {
            if card.selectedSourcePaths.isEmpty {
                let dcimURL = card.url.appendingPathComponent("DCIM")
                startBackupProcess(volumeURL: card.url, sourceURLs: [dcimURL])
            } else {
                let urls = card.selectedSourcePaths.map { URL(fileURLWithPath: $0) }
                startBackupProcess(volumeURL: card.url, sourceURLs: urls)
            }
        }
    }
    
    func ejectCard(url: URL) {
        let isVolume = url.pathComponents.count > 1 && url.pathComponents[1] == "Volumes"
        DispatchQueue.global(qos: .userInitiated).async {
            if isVolume {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } else {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            }
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
        
        if Set(keys).isSubset(of: [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            if let r = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
                if let vn = r.volumeName { name = vn }
                if let fmt = r.volumeLocalizedFormatDescription { 
                    format = fmt.replacingOccurrences(of: " (Encrypted)", with: "", options: .caseInsensitive).replacingOccurrences(of: "（已加密）", with: "") 
                }
                if let cap = r.volumeTotalCapacity { total = Int64(cap) }
                if let avail = r.volumeAvailableCapacity { free = Int64(avail) }
            }
        } else {
            if let r = try? url.resourceValues(forKeys: Set(keys)) {
                if let vn = r.volumeName { name = vn }
                if let fmt = r.volumeLocalizedFormatDescription { 
                    format = fmt.replacingOccurrences(of: " (Encrypted)", with: "", options: .caseInsensitive).replacingOccurrences(of: "（已加密）", with: "") 
                }
                if let cap = r.volumeTotalCapacity { total = Int64(cap) }
                if let avail = r.volumeAvailableCapacity { free = Int64(avail) }
            }
        }
        
        let deviceID = url.lastPathComponent
        let isTrusted = trustedDeviceIDs.contains(deviceID)
        
        // 加载记忆的源路径
        var savedSources: [String] = []
        if let dict = UserDefaults.standard.dictionary(forKey: sourcePathsKey) as? [String: [String]], let paths = dict[deviceID] {
            savedSources = paths
        }
        
        let card = ConnectedCard(url: url, name: name, format: format, totalSpace: total, freeSpace: free, isTrusted: isTrusted, selectedSourcePaths: savedSources)
        DispatchQueue.main.async {
            if !self.connectedCards.contains(where: { $0.url == url }) {
                self.connectedCards.append(card)
                self.dummyTrigger.toggle()
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
            }
        }
    }
    
    private func isPotentialMemoryCard(at url: URL) -> Bool {
        // 1. 基本排除：根分区、系统分区、已忽略的设备
        if url.path == "/" || url.path == "/System/Volumes/Data" { return false }
        let deviceID = url.lastPathComponent
        if ignoredDeviceIDs.contains(deviceID) { return false }
        
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeLocalizedFormatDescriptionKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
            print("DEBUG: Failed to get resource values for \(url.path)")
            return false
        }
        
        let isInternal = values.volumeIsInternal ?? true
        let isEjectable = values.volumeIsEjectable ?? false
        let isRemovable = values.volumeIsRemovable ?? false
        let name = values.volumeName ?? url.lastPathComponent
        let totalCapacity = Int64(values.volumeTotalCapacity ?? 0)
        let format = values.volumeLocalizedFormatDescription ?? ""
        
        print("DEBUG: Checking volume: \(name) [\(url.path)] | Internal: \(isInternal) | Ejectable: \(isEjectable) | Removable: \(isRemovable) | Cap: \(totalCapacity / 1_000_000_000) GB | Format: \(format)")
        
        // 2. 强力排除规则：内置硬盘直接过滤
        if isInternal && url.path == "/" { return false }
        
        // 3. 排除明确的备份盘和 Time Machine
        let lowerName = name.lowercased()
        if lowerName.contains("time machine") || lowerName.contains("backup") || lowerName.contains("tm-") || lowerName.contains("time-machine") {
            print("DEBUG: Skipping backup drive by name: \(name)")
            return false
        }
        
        // 4. 文件系统判定：SD 卡通常为 ExFAT 或 FAT32。APFS/HFS+ 通常是移动硬盘或系统盘。
        let lowerFormat = format.lowercased()
        let isAppleFormat = lowerFormat.contains("apfs") || lowerFormat.contains("mac os extended") || lowerFormat.contains("hfs")
        
        // 5. 核心判定规则 A：物理可移除介质 (USB 读卡器里的 SD/CF 卡) -> 允许
        if isRemovable && isEjectable { return true }
        
        // 6. 核心判定规则 B：对于非 Removable 但 Ejectable 的设备 (雷电读卡器、移动 SSD)
        if isEjectable {
            // 如果是苹果专有格式 (APFS/HFS) 且没有 Removable 标记，绝大概率是移动硬盘
            if isAppleFormat {
                // 除非极其明确有相机文件夹，否则视为硬盘排除
                let cameraPaths = ["DCIM", "PRIVATE", "VIDEO", "CLIP", "AVCHD"]
                for p in cameraPaths {
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent(p).path) {
                        return true
                    }
                }
                print("DEBUG: Skipping Apple-formatted external drive without camera folders: \(name)")
                return false
            }
            
            // 容量判定 (摄影存储卡通常不会超过 1TB)
            let oneTera: Int64 = 1_100_000_000_000 
            if totalCapacity > oneTera {
                // 同上，除非有相机目录
                let cameraPaths = ["DCIM", "PRIVATE", "VIDEO", "CLIP", "AVCHD"]
                for p in cameraPaths {
                    if FileManager.default.fileExists(atPath: url.appendingPathComponent(p).path) {
                        return true
                    }
                }
                print("DEBUG: Skipping large external drive (>1TB) without camera folders: \(name)")
                return false
            }
            
            return true
        }
        
        // 兜底判定
        if url.path.hasPrefix("/Volumes/") && !isAppleFormat {
            return true
        }
        
        return false
    }
    
    private func handleMountEvent(volumeURL: URL) {
        if isPotentialMemoryCard(at: volumeURL) {
            self.addCard(url: volumeURL)
            
            let userDefaults = UserDefaults.standard
            if userDefaults.object(forKey: "autoBackupOnMount") == nil {
                userDefaults.set(true, forKey: "autoBackupOnMount")
            }
            let isAutoBackup = userDefaults.bool(forKey: "autoBackupOnMount")
            let isTrusted = trustedDeviceIDs.contains(volumeURL.lastPathComponent)
            
            if isAutoBackup && isTrusted {
                if let idx = self.connectedCards.firstIndex(where: { $0.url == volumeURL }), !self.connectedCards[idx].selectedSourcePaths.isEmpty {
                    let urls = self.connectedCards[idx].selectedSourcePaths.map { URL(fileURLWithPath: $0) }
                    startBackupProcess(volumeURL: volumeURL, sourceURLs: urls)
                } else {
                    let dcimURL = volumeURL.appendingPathComponent("DCIM")
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: dcimURL.path, isDirectory: &isDir) && isDir.boolValue {
                        startBackupProcess(volumeURL: volumeURL, sourceURLs: [dcimURL])
                    }
                }
            }
            // Silent migrate fallback on target mount check...
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
    
    private func startBackupProcess(volumeURL: URL, sourceURLs: [URL]) {
        let targetPath = UserDefaults.standard.string(forKey: "targetBackupPath") ?? ""
        let isTargetAvailable = !targetPath.isEmpty && FileManager.default.fileExists(atPath: targetPath)
        let fallbackPath = getFallbackPath()
        
        // "目标文件夹不要用日期进行命名" -> Remove date component entirely
        let destination: String
        if isTargetAvailable {
            destination = targetPath
        } else if !fallbackPath.isEmpty {
            destination = fallbackPath
        } else {
            print("Both main target and fallback paths are unavailable. Backup aborted.")
            return
        }
        
        let sourceName = volumeURL.lastPathComponent
        self.runRsync(sources: sourceURLs.map { $0.path }, destination: destination, actionNameKey: "working", sourceName: sourceName, isMigrating: false, sourceVolumeURL: volumeURL)
    }
    
    private func runRsync(sources: [String], destination: String, actionNameKey: String, sourceName: String, isMigrating: Bool, sourceVolumeURL: URL?) {
        guard !isWorking else {
            print("Already working, ignoring trigger.")
            return
        }
        
        guard !sources.isEmpty else { return }
        
        if !FileManager.default.fileExists(atPath: destination) {
            do {
                try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create destination: \(error)")
                return
            }
        }
        
        DispatchQueue.main.async {
            self.isWorking = true
            self.currentActionTextKey = actionNameKey
            self.progressPercent = 0.0
            self.progressDetailText = "" // Let L10n handle the calculating state text later
        }
        
        let startTime = Date()
        
        let verifyChecksum = UserDefaults.standard.bool(forKey: "verifyChecksum")
        let sortFormats = UserDefaults.standard.bool(forKey: "sortFormats")
        let ejectOnFinish = UserDefaults.standard.bool(forKey: "ejectOnFinish")
        let openFinderOnFinish = UserDefaults.standard.bool(forKey: "openFinderOnFinish")
        
        // 我们用 -n 跑一遍空转获取总数据量来实现真正的进度条（牺牲几秒钟时间换取体验）
        DispatchQueue.global(qos: .userInitiated).async {
            var totalFilesToTransfer: Int = 0
            var _: [Int64] = [] // 不强统计具体字节大小只按文件个数做进度可以非常快
            
            let dryRunProcess = Process()
            dryRunProcess.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            var dryArgs = ["-avn", "--out-format=%i"]
            if verifyChecksum { dryArgs.append("--checksum") }
            
            for s in sources {
                let sourcePath = s.hasSuffix("/") ? s : s + "/"
                dryArgs.append(sourcePath)
            }
            
            dryArgs.append(destination)
            dryRunProcess.arguments = dryArgs
            
            let dryPipe = Pipe()
            dryRunProcess.standardOutput = dryPipe
            
            do {
                try dryRunProcess.run()
                // 读取完整输出
                let data = dryPipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        if line.starts(with: ">f") || line.starts(with: "<f") || line.starts(with: "c") {
                            totalFilesToTransfer += 1
                        }
                    }
                }
                dryRunProcess.waitUntilExit()
            } catch {
                print("Dry run failed.")
            }
            
            // 如果计算出是 0，直接结束不用真跑
            if totalFilesToTransfer == 0 {
                DispatchQueue.main.async {
                    self.isWorking = false
                    let log = BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "无新文件")
                    self.addLog(log)
                }
                return
            }
            
            // 真实运行 rsync 
            let process = Process()
            self.currentProcess = process
            
            // 强制伪终端(PTY)开启进行行缓存，解决 rsync 内部缓冲导致 SwiftUI 死结
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            let strategy = UserDefaults.standard.integer(forKey: "backupStrategy")
            var args = ["-q", "/dev/null", "/usr/bin/rsync", "-av", "--out-format=%i %n %l"]
            if strategy == 1 {
                args.append("--ignore-existing")
            } else {
                args.append("-u") // default: update based on size/date
            }
            
            if verifyChecksum { args.append("--checksum") }
            if isMigrating { args.append("--remove-source-files") }
            
            // File Filters
            if UserDefaults.standard.bool(forKey: "enableFileFilter") {
                let extsStr = UserDefaults.standard.string(forKey: "allowedFileExtensions") ?? "arw, cr2, cr3, jpg, heif, mov, mp4, xml"
                let extArray = extsStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                
                if !extArray.isEmpty {
                    args.append("--include=*/") // allow traversal
                    for ext in extArray {
                        args.append("--include=*.\(ext)")
                        args.append("--include=*.\(ext.uppercased())")
                    }
                    args.append("--exclude=*") // block everything else
                }
            }
            
            for s in sources {
                args.append(s)
            }
            
            args.append(destination)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            var transferredBytes: Int64 = 0
            var copiedFilesCount: Int = 0
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                
                let lines = str.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                    if parts.count == 3 {
                        let flags = String(parts[0])
                        if flags.starts(with: ">f") || flags.starts(with: "<f") || flags.starts(with: "c") {
                            if let size = Int64(parts[2]) {
                                transferredBytes += size
                                copiedFilesCount += 1
                                
                                let elapsed = Date().timeIntervalSince(startTime)
                                let speed = elapsed > 0 ? Double(transferredBytes) / elapsed : 0
                                let percent = min(Double(copiedFilesCount) / Double(totalFilesToTransfer), 1.0)
                                let percentInt = Int(percent * 100)
                                
                                var etaStr = ""
                                if percent > 0 && percent < 1.0 {
                                    let estTotalTime = elapsed / percent
                                    let remainSeconds = max(0, estTotalTime - elapsed)
                                    if remainSeconds > 60 {
                                        etaStr = String(format: "%d分%d秒", Int(remainSeconds)/60, Int(remainSeconds)%60)
                                    } else {
                                        etaStr = String(format: "%d秒", Int(remainSeconds))
                                    }
                                }
                                
                                DispatchQueue.main.async {
                                    self.progressPercent = percent
                                    self.progressDetailText = String(format: "已传 %d/%d (%.1f MB/s)  %d%%", copiedFilesCount, totalFilesToTransfer, speed / 1_000_000, percentInt)
                                    self.etaText = etaStr
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
                
                let duration = Date().timeIntervalSince(startTime)
                
                if process.terminationStatus == 0 {
                    if isMigrating {
                        for s in sources {
                            self.cleanEmptyDirectories(at: s)
                        }
                    }
                    
                    if !isMigrating && sortFormats && copiedFilesCount > 0 {
                        self.organizeFormatsWithTemplate(in: destination)
                    }
                    
                    if openFinderOnFinish && copiedFilesCount > 0 {
                        DispatchQueue.main.async {
                            NSWorkspace.shared.open(URL(fileURLWithPath: destination))
                        }
                    }
                    
                    if ejectOnFinish && !isMigrating, let url = sourceVolumeURL {
                        self.ejectCard(url: url)
                    }
                    
                    let transferredMB = Double(transferredBytes) / 1_000_000
                    let dataStr = transferredMB > 1000 ? String(format: "%.2f GB", transferredMB / 1000) : String(format: "%.1f MB", transferredMB)
                    let resultStr = copiedFilesCount > 0 ? "成功" : "无新文件"
                    
                    let log = BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: dataStr, fileCount: copiedFilesCount, durationSeconds: duration, result: resultStr)
                    self.addLog(log)
                    
                } else {
                    let log = BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: duration, result: "失败")
                    self.addLog(log)
                }
                
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.currentProcess = nil
                    print("Backup finished with status: \(process.terminationStatus)")
                }
            } catch {
                print("Failed to run rsync: \(error)")
                pipe.fileHandleForReading.readabilityHandler = nil
                let log = BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "失败")
                self.addLog(log)
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.currentProcess = nil
                }
            }
        }
    }
    
    // EXIF Template 抽取系统
    private func organizeFormatsWithTemplate(in directoryPath: String) {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: directoryPath)
        
        let templateStr = UserDefaults.standard.string(forKey: "directoryTemplate") ?? "{YYYY}-{MM}-{DD}/{MODEL}/{EXT}/"
        _ = "{EXT}/" // 兜底
        
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        
        for case let fileURL as URL in enumerator {
            // 跳过已经是嵌套进入了子层级的文件 
            // 简单逻辑：直接遍历根下第一层的项如果是一个有效文件就挪动到相对根指定的层级里
            if fileURL.deletingLastPathComponent().path != directoryPath { continue }
            
            let ext = fileURL.pathExtension.uppercased()
            if ext.isEmpty { continue }
            
            // 解析元数据
            var yyyy = "Unknown"
            var mm = "XX"
            var dd = "XX"
            var make = "Unknown"
            var model = "Unknown"
            
            if let imgSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(imgSource, 0, nil) as? [String: Any] {
                
                // 解析 TIFF 提取相机型号
                if let tiff = props["{TIFF}"] as? [String: Any] {
                    if let mkr = tiff["Make"] as? String { make = mkr.trimmingCharacters(in: .whitespaces) }
                    if let mdl = tiff["Model"] as? String { model = mdl.trimmingCharacters(in: .whitespaces) }
                }
                
                // 解析 EXIF 取拍摄时间 "2023:10:25 12:30:45"
                if let exif = props["{Exif}"] as? [String: Any],
                   let dtOriginal = exif["DateTimeOriginal"] as? String {
                    let parts = dtOriginal.split(separator: " ")
                    if let datePart = parts.first {
                        let dps = datePart.split(separator: ":")
                        if dps.count == 3 {
                            yyyy = String(dps[0])
                            mm = String(dps[1])
                            dd = String(dps[2])
                        }
                    }
                }
            }
            
            var generatedTemplate = templateStr
                .replacingOccurrences(of: "{YYYY}", with: yyyy)
                .replacingOccurrences(of: "{MM}", with: mm)
                .replacingOccurrences(of: "{DD}", with: dd)
                .replacingOccurrences(of: "{MAKE}", with: make)
                .replacingOccurrences(of: "{MODEL}", with: model)
                .replacingOccurrences(of: "{EXT}", with: ext)
            
            // 防御性处理，去除多余斜杠
            generatedTemplate = (generatedTemplate as NSString).standardizingPath
            
            let destFolderURL = url.appendingPathComponent(generatedTemplate)
            try? fm.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
            let destFile = destFolderURL.appendingPathComponent(fileURL.lastPathComponent)
            
            if !fm.fileExists(atPath: destFile.path) {
                try? fm.moveItem(at: fileURL, to: destFile)
            }
        }
        
        self.cleanEmptyDirectories(at: directoryPath)
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
}
