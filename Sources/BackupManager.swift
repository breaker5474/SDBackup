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
                self.dummyTrigger.toggle()
            }
        }
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
            let dcimURL = card.url.appendingPathComponent("DCIM")
            startBackupProcess(volumeURL: card.url, dcimURL: dcimURL)
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
                self.connectedCards.removeAll { $0.url == url }
            }
        }
    }
    
    private func checkExistingVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        if let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) {
            for url in urls {
                let dcimURL = url.appendingPathComponent("DCIM")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: dcimURL.path, isDirectory: &isDir), isDir.boolValue {
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
            if let fmt = r.volumeLocalizedFormatDescription { format = fmt }
            if let cap = r.volumeTotalCapacity { total = Int64(cap) }
            if let avail = r.volumeAvailableCapacity { free = Int64(avail) }
        }
        
        let deviceID = url.lastPathComponent
        let isTrusted = trustedDeviceIDs.contains(deviceID)
        
        let card = ConnectedCard(url: url, name: name, format: format, totalSpace: total, freeSpace: free, isTrusted: isTrusted)
        DispatchQueue.main.async {
            if !self.connectedCards.contains(where: { $0.url == url }) {
                self.connectedCards.append(card)
                self.dummyTrigger.toggle()
            }
        }
    }
    
    private func removeCard(url: URL) {
        DispatchQueue.main.async {
            self.connectedCards.removeAll { $0.url == url }
            self.dummyTrigger.toggle()
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
    
    private func handleMountEvent(volumeURL: URL) {
        let dcimURL = volumeURL.appendingPathComponent("DCIM")
        var isDir: ObjCBool = false
        let isSDCard = FileManager.default.fileExists(atPath: dcimURL.path, isDirectory: &isDir) && isDir.boolValue
        
        if isSDCard {
            addCard(url: volumeURL)
        }
        
        let userDefaults = UserDefaults.standard
        if userDefaults.object(forKey: "autoBackupOnMount") == nil {
            userDefaults.set(true, forKey: "autoBackupOnMount")
        }
        let isAutoBackup = userDefaults.bool(forKey: "autoBackupOnMount")
        let shouldMigrateFallback = userDefaults.bool(forKey: "autoMigrateFallback")
        
        let isTrusted = trustedDeviceIDs.contains(volumeURL.lastPathComponent)
        
        if isSDCard && isAutoBackup && isTrusted {
            startBackupProcess(volumeURL: volumeURL, dcimURL: dcimURL)
        }
        
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
                    self.runRsync(source: fallbackPath, destination: targetPath, actionNameKey: "migrating", sourceName: "Fallback Cache", isMigrating: true, sourceVolumeURL: nil)
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
    
    private func startBackupProcess(volumeURL: URL, dcimURL: URL) {
        let targetPath = UserDefaults.standard.string(forKey: "targetBackupPath") ?? ""
        let isTargetAvailable = !targetPath.isEmpty && FileManager.default.fileExists(atPath: targetPath)
        let fallbackPath = getFallbackPath()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // 增量根目录仍然按天放置，分类在里面再细分，以保证 rsync 逻辑平稳
        let dateFolderName = formatter.string(from: Date())
        
        let finalDestinationStr: String
        if isTargetAvailable {
            finalDestinationStr = URL(fileURLWithPath: targetPath).appendingPathComponent(dateFolderName).path
        } else if !fallbackPath.isEmpty {
            finalDestinationStr = URL(fileURLWithPath: fallbackPath).appendingPathComponent(dateFolderName).path
        } else {
            print("Both main target and fallback paths are unavailable. Backup aborted.")
            return
        }
        
        let sourceName = volumeURL.lastPathComponent
        self.runRsync(source: dcimURL.path, destination: finalDestinationStr, actionNameKey: "working", sourceName: sourceName, isMigrating: false, sourceVolumeURL: volumeURL)
    }
    
    private func runRsync(source: String, destination: String, actionNameKey: String, sourceName: String, isMigrating: Bool, sourceVolumeURL: URL?) {
        guard !isWorking else {
            print("Already working, ignoring trigger.")
            return
        }
        
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
            let sourcePath = source.hasSuffix("/") ? source : source + "/"
            var dryArgs = ["-avn", "--out-format=%i"]
            if verifyChecksum { dryArgs.append("--checksum") }
            dryArgs.append(sourcePath)
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
            
            args.append(sourcePath)
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
                                
                                DispatchQueue.main.async {
                                    self.progressPercent = percent
                                    self.progressDetailText = String(format: "已传 %d/%d (%.1f MB/s)  %d%%", copiedFilesCount, totalFilesToTransfer, speed / 1_000_000, percentInt)
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
                        self.cleanEmptyDirectories(at: source)
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
                    print("Backup finished with status: \(process.terminationStatus)")
                }
            } catch {
                print("Failed to run rsync: \(error)")
                pipe.fileHandleForReading.readabilityHandler = nil
                let log = BackupLog(date: Date(), sourceName: sourceName, destinationPath: destination, dataTransferredStr: "0 MB", fileCount: 0, durationSeconds: 0, result: "失败")
                self.addLog(log)
                DispatchQueue.main.async {
                    self.isWorking = false
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
