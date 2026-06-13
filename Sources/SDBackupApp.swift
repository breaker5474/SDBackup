import SwiftUI
import AppKit

@main
struct SDBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var backupManager = BackupManager()
    @StateObject private var env = AppEnvironment()
    
    // 其他设置
    @AppStorage("hideDockIcon") private var hideDockIcon: Bool = true
    
    var body: some Scene {
        MenuBarExtra(L10n.translate("appName", lang: env.languageCode), systemImage: backupManager.isWorking ? (backupManager.isWorkingAnimationToggle ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath") : "sdcard") {
            if backupManager.isWorking {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                    Text(L10n.translate(backupManager.currentActionTextKey, lang: env.languageCode))
                }
                .disabled(true)
                
                if !backupManager.etaText.isEmpty {
                    Text("\(L10n.translate("eta", lang: env.languageCode))\(backupManager.etaText)")
                        .font(.caption2)
                        .disabled(true)
                }
                
                if backupManager.progressDetailText.isEmpty {
                    Text(L10n.translate("calculating", lang: env.languageCode))
                        .font(.caption)
                        .disabled(true)
                } else {
                    Text(backupManager.progressDetailText)
                        .font(.caption)
                        .disabled(true)
                }
                
                Divider()
                
                Button(L10n.translate("cancelTransfer", lang: env.languageCode)) {
                    backupManager.cancelTransfer()
                }
                
                Divider()
            }
            
            if !backupManager.connectedCards.isEmpty {
                Text(L10n.translate("connectedCards", lang: env.languageCode))
                    .disabled(true)
                
                if let lastLog = backupManager.backupHistory.first {
                    Text("\(L10n.translate("lastBackup", lang: env.languageCode)) \(lastLog.date, style: .date) \(lastLog.date, style: .time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .disabled(true)
                }
                
                ForEach(backupManager.connectedCards) { card in
                    let freeGB = Double(card.freeSpace) / 1_000_000_000
                    let totalGB = Double(card.totalSpace) / 1_000_000_000
                    let cardLastLog = backupManager.backupHistory.first(where: { $0.sourceName == card.url.lastPathComponent })
                    
                    Menu("• \(card.displayName)") {
                        Text("\(card.format) | \(L10n.translate("freeCap", lang: env.languageCode)): \(String(format: "%.1f", freeGB))GB / \(String(format: "%.1f", totalGB))GB")
                            .disabled(true)
                        
                        if let log = cardLastLog {
                            Text("\(L10n.translate("lastBackup", lang: env.languageCode)) \(log.date, style: .date) \(log.date, style: .time)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .disabled(true)
                        }
                        
                        Divider()
                        
                        Button(L10n.translate("backupCardNow", lang: env.languageCode)) {
                            let urls: [URL]
                            if card.selectedSourcePaths.isEmpty {
                                urls = [card.url.appendingPathComponent("DCIM")]
                            } else {
                                urls = card.selectedSourcePaths.map { URL(fileURLWithPath: $0) }
                            }
                            backupManager.startBackupProcess(volumeURL: card.url, sourceURLs: urls)
                        }
                        .disabled(backupManager.isWorking)
                        
                        Divider()
                        
                        Button("\(L10n.translate("eject", lang: env.languageCode)) \(card.displayName)") {
                            backupManager.ejectCard(url: card.url)
                        }
                    }
                }
                Divider()
            }
            
            Button(L10n.translate("settingsAction", lang: env.languageCode)) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            Divider()
            Button(L10n.translate("quit", lang: env.languageCode)) {
                NSApplication.shared.terminate(nil)
            }
        }
        
        Window(L10n.translate("settingsTitle", lang: env.languageCode), id: "settings") {
            SettingsView(backupManager: backupManager)
                .environmentObject(env) // 注入响应式双语环境
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupLogging()
        
        let hideDock = UserDefaults.standard.bool(forKey: "hideDockIcon")
        if hideDock {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    private func setupLogging() {
        if let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs") {
            do {
                try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
                let logFile = logDir.appendingPathComponent("SDBackupApp.log").path
                freopen(logFile.cString(using: .ascii), "a+", stderr)
                freopen(logFile.cString(using: .ascii), "a+", stdout)
                print("\n\n--- App Launched at \(Date()) ---")
            } catch {
                print("Failed to setup logging: \(error)")
            }
        }
    }
}

// macOS 风格的设置主界面
struct SettingsView: View {
    @ObservedObject var backupManager: BackupManager
    @EnvironmentObject var env: AppEnvironment
    @State private var selection: SidebarItem = .backup
    
    enum SidebarItem: String, CaseIterable, Identifiable {
        case backup = "navBackup"
        case advanced = "navAdvanced"
        case logs = "navLogs"
        case other = "navOther"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .backup: return "arrow.triangle.2.circlepath"
            case .advanced: return "gearshape.2"
            case .logs: return "list.bullet.rectangle"
            case .other: return "ellipsis.circle"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    NavigationLink(value: item) {
                        Label {
                            LocalizedText(item.rawValue)
                        } icon: {
                            Image(systemName: item.icon)
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle(env.localized("appName"))
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selection {
                    case .backup: BackupSettingsView(backupManager: backupManager)
                    case .advanced: AdvancedSettingsView()
                    case .logs: LogsView(backupManager: backupManager)
                    case .other: OtherSettingsView(backupManager: backupManager)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("")
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// --- 子页面 ---

struct BackupSettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @AppStorage("targetBackupPath") private var targetBackupPath: String = ""
    @AppStorage("enableFallbackPath") private var enableFallbackPath: Bool = false
    @AppStorage("localBackupPath") private var localBackupPath: String = ""
    @AppStorage("autoBackupOnMount") private var autoBackupOnMount: Bool = true
    @AppStorage("enableFileFilter") private var enableFileFilter: Bool = false
    @AppStorage("fileFilterMode") private var fileFilterMode: FileFilterMode = .include
    @AppStorage("allowedFileExtensions") private var allowedFileExtensions: String = "arw, cr2, cr3, jpg, heif, mov, mp4, xml"
    
    @ObservedObject var backupManager: BackupManager
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var refreshToggle = false
    @State private var showingRenameAlert = false
    @State private var renameTarget: ConnectedCard? = nil
    @State private var renameText: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $autoBackupOnMount) { LocalizedText("autoBackupMount") }
                        .toggleStyle(.switch)
                    
                    Button(action: { backupManager.manualBackupAll() }) {
                        LocalizedText("manualBackupAll")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(backupManager.connectedCards.isEmpty || backupManager.isWorking)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { LocalizedText("triggerMode").font(.headline) }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 15) {
                        Image(systemName: "externaldrive.fill").foregroundColor(.blue).font(.system(size: 30))
                        PathSelector(titleKey: "targetMain", path: $targetBackupPath, isTarget: true, refreshToggle: refreshToggle)
                    }
                    
                    Divider()
                    Toggle(isOn: $enableFallbackPath) { LocalizedText("enableFallback") }
                    if enableFallbackPath {
                        HStack(alignment: .center, spacing: 15) {
                            Image(systemName: "internaldrive.fill").foregroundColor(.blue).font(.system(size: 30))
                            PathSelector(titleKey: "targetFallback", path: $localBackupPath, isTarget: false, refreshToggle: refreshToggle)
                        }
                    }
                }
                .padding(12)
            } label: { LocalizedText("targetLocation").font(.headline) }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    if backupManager.connectedCards.isEmpty {
                        LocalizedText("noCards")
                            .foregroundColor(.secondary)
                    } else {
                        let _ = backupManager.dummyTrigger
                        ForEach(backupManager.connectedCards) { card in
                            let totalGB = Double(card.totalSpace) / 1_000_000_000
                            let freeGB = Double(card.freeSpace) / 1_000_000_000
                            let usedGB = totalGB - freeGB
                            let usedPerc = totalGB > 0 ? (usedGB / totalGB) : 0.0
                            let isWarning = freeGB < 10.0 || (1.0 - usedPerc) < 0.1
                            
                            HStack(alignment: .center, spacing: 15) {
                                Image(systemName: "sdcard.fill").foregroundColor(.blue).font(.system(size: 30))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(card.displayName).fontWeight(.medium)
                                        if card.customName != nil {
                                            Text(card.name).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Text(card.format).font(.caption).padding(.horizontal, 4).padding(.vertical, 2).background(Color.secondary.opacity(0.2)).cornerRadius(4)
                                        Spacer()
                                        Text("\(env.localized("freeCap")): \(String(format: "%.1f", freeGB))GB / \(String(format: "%.1f", totalGB))GB (\(Int(usedPerc * 100))%)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if totalGB > 0 {
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 6)
                                                Capsule()
                                                    .fill(isWarning ? Color.red : Color.blue)
                                                    .frame(width: max(0, geo.size.width * CGFloat(usedPerc)), height: 6)
                                            }
                                        }
                                        .frame(height: 8)
                                    }
                                    
                                    if !card.isTrusted {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(env.localized("untrustedWarn")).font(.caption).foregroundColor(.orange)
                                            Button(action: { backupManager.toggleTrust(for: card.url) }) {
                                                Text(" \(Image(systemName: "checkmark.shield.fill")) \(env.localized("trustCard"))")
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.orange)
                                        }
                                        .padding(.top, 4)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(env.localized("sourceSelectionHint"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 4)
                                        
                                        HStack(spacing: 8) {
                                            if !card.selectedSourcePaths.isEmpty {
                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    HStack(spacing: 6) {
                                                        ForEach(card.selectedSourcePaths, id: \.self) { p in
                                                            HStack(spacing: 4) {
                                                                Text(URL(fileURLWithPath: p).lastPathComponent).font(.subheadline)
                                                                Button(action: {
                                                                    if let idx = backupManager.connectedCards.firstIndex(where: { $0.url == card.url }) {
                                                                        backupManager.connectedCards[idx].selectedSourcePaths.removeAll(where: { $0 == p })
                                                                        backupManager.saveSourcePaths(for: backupManager.connectedCards[idx])
                                                                        backupManager.dummyTrigger.toggle()
                                                                    }
                                                                }) {
                                                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.system(size: 14))
                                                                }
                                                                .buttonStyle(.plain)
                                                            }
                                                            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 5)
                                                            .background(Color.blue.opacity(0.1)).cornerRadius(8)
                                                        }
                                                    }
                                                }
                                            } else {
                                                Text(env.localized("noSources")).font(.caption).foregroundColor(.secondary).padding(.leading, 4)
                                            }
                                            
                                            Button(action: {
                                                let panel = NSOpenPanel()
                                                panel.canChooseFiles = false
                                                panel.canChooseDirectories = true
                                                panel.allowsMultipleSelection = true
                                                panel.directoryURL = card.url
                                                panel.title = env.localized("addSource")
                                                if panel.runModal() == .OK {
                                                    let newPaths = panel.urls.map { $0.path }
                                                    if let idx = backupManager.connectedCards.firstIndex(where: { $0.url == card.url }) {
                                                        var currentPaths = backupManager.connectedCards[idx].selectedSourcePaths
                                                        for p in newPaths {
                                                            if !currentPaths.contains(p) { currentPaths.append(p) }
                                                        }
                                                        backupManager.connectedCards[idx].selectedSourcePaths = currentPaths
                                                        backupManager.saveSourcePaths(for: backupManager.connectedCards[idx])
                                                        backupManager.dummyTrigger.toggle()
                                                    }
                                                }
                                            }) {
                                                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundColor(.blue)
                                            }
                                            .buttonStyle(.plain)
                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    Button(action: { backupManager.ejectCard(url: card.url) }) {
                                        LocalizedText("eject")
                                    }
                                    .disabled(backupManager.isWorking)
                                    
                                    Button(action: {
                                        renameTarget = card
                                        renameText = card.customName ?? card.name
                                        showingRenameAlert = true
                                    }) {
                                        LocalizedText("renameCard")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { LocalizedText("cardDetails").font(.headline) }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $enableFileFilter.animation(.spring())) {
                        LocalizedText("enableFileFilter")
                    }
                    
                    if enableFileFilter {
                        Picker(env.localized("fileFilterMode"), selection: $fileFilterMode) {
                            LocalizedText("filterInclude").tag(FileFilterMode.include)
                            LocalizedText("filterExclude").tag(FileFilterMode.exclude)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(env.localized("filterHint"), text: $allowedFileExtensions)
                                .textFieldStyle(.roundedBorder)
                            LocalizedText("filterHint").font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { LocalizedText("fileFilters").font(.headline) }
        }
        .onReceive(timer) { _ in refreshToggle.toggle() }
        .alert(env.localized("renameCardTitle"), isPresented: $showingRenameAlert) {
            TextField(env.localized("renameCardPlaceholder"), text: $renameText)
            Button("OK") {
                if let target = renameTarget {
                    backupManager.renameCard(url: target.url, newName: renameText)
                }
            }
            Button(L10n.translate("cancel", lang: env.languageCode)) {}
        } message: {
            if let target = renameTarget {
                Text("\(target.name)")
            }
        }
    }
}

struct PathSelector: View {
    @EnvironmentObject var env: AppEnvironment
    let titleKey: String
    @Binding var path: String
    let isTarget: Bool
    let refreshToggle: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(titleKey).font(.subheadline).foregroundColor(.secondary)
            HStack {
                TextField(env.localized("notSet"), text: $path).disabled(true).textFieldStyle(.roundedBorder)
                Button(env.localized("select")) { selectFolder() }
                Button(action: { revealInFinder() }) { Image(systemName: "folder") }
                    .disabled(path.isEmpty).help(env.localized("revealFinder"))
            }
            
            let spaceInfo = getFreeSpacePercentage(forPath: path)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if !spaceInfo.format.isEmpty {
                        Text(spaceInfo.format).font(.caption).padding(.horizontal, 4).padding(.vertical, 2).background(Color.secondary.opacity(0.2)).cornerRadius(4)
                    }
                    Text("\(env.localized("freeSpace")) \(spaceInfo.text) / \(String(format: "%.1f GB", spaceInfo.total)) (\(Int((1.0 - spaceInfo.usedPercent) * 100))%)")
                        .font(.caption)
                        .foregroundColor(spaceInfo.isWarning ? .red : .secondary)
                    Spacer()
                }
                if spaceInfo.total > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 6)
                            Capsule().fill(spaceInfo.isWarning ? Color.red : Color.blue).frame(width: geo.size.width * CGFloat(spaceInfo.usedPercent), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .id(refreshToggle)
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = env.localized("openPanelTitle")
        panel.prompt = env.localized("openPanelPrompt")
        if panel.runModal() == .OK {
            if let url = panel.url { path = url.path }
        }
    }
    
    private func revealInFinder() {
        guard !path.isEmpty else { return }
        var checkPath = path
        var isDir: ObjCBool = false
        var iterations = 0
        while !FileManager.default.fileExists(atPath: checkPath, isDirectory: &isDir) && iterations < 100 {
            let parent = URL(fileURLWithPath: checkPath).deletingLastPathComponent().path
            if parent == checkPath { break }
            checkPath = parent
            iterations += 1
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: checkPath))
    }
}

func getFreeSpacePercentage(forPath path: String) -> (text: String, isWarning: Bool, usedPercent: Double, total: Double, format: String) {
    if path.isEmpty { return ("", false, 0.0, 0.0, "") }
    var checkPath = path
    var iterations = 0
    while !FileManager.default.fileExists(atPath: checkPath) && iterations < 100 {
        let parent = URL(fileURLWithPath: checkPath).deletingLastPathComponent().path
        if parent == checkPath { break }
        checkPath = parent
        iterations += 1
    }
    var format = ""
    let url = URL(fileURLWithPath: checkPath)
    if let r = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]), let fmt = r.volumeLocalizedFormatDescription {
        format = fmt.replacingOccurrences(of: " (Encrypted)", with: "", options: .caseInsensitive).replacingOccurrences(of: "（已加密）", with: "")
    }
    do {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: checkPath)
        if let freeSize = attrs[.systemFreeSize] as? NSNumber, let sysTotal = attrs[.systemSize] as? NSNumber {
            let gigabytes = Double(freeSize.int64Value) / 1_000_000_000.0
            let tGB = Double(sysTotal.int64Value) / 1_000_000_000.0
            let used = tGB - gigabytes
            let perc = tGB > 0 ? (used / tGB) : 0.0
            return (String(format: "%.1f GB", gigabytes), gigabytes < 10.0 || (1.0 - perc) < 0.1, perc, tGB, format)
        }
    } catch {}
    return ("", false, 0.0, 0.0, format)
}

struct AdvancedSettingsView: View {
    @AppStorage("comparisonStrategy") private var comparisonStrategy: BackupComparisonStrategy = .updateIfModified
    @AppStorage("enableVerification") private var enableVerification: Bool = false
    @AppStorage("verificationLevel") private var verificationLevel: PostTransferVerificationLevel = .basic
    @AppStorage("ejectOnFinish") private var ejectOnFinish: Bool = false
    @AppStorage("openFinderOnFinish") private var openFinderOnFinish: Bool = true
    @AppStorage("autoMigrateFallback") private var autoMigrateFallback: Bool = true
    @AppStorage("preventSleep") private var preventSleep: Bool = true
    
    @EnvironmentObject var env: AppEnvironment
    
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(header: LocalizedText("advancedPerf").font(.headline).foregroundColor(.primary)) {
                    Picker(env.localized("backupStrategyTitle"), selection: $comparisonStrategy) {
                        Text(env.localized("strategySizeDate")).tag(BackupComparisonStrategy.updateIfModified)
                        Text(env.localized("strategyIgnore")).tag(BackupComparisonStrategy.skipIfExists)
                    }
                    .pickerStyle(.menu)
                    
                    Toggle(isOn: $enableVerification.animation(.spring())) {
                        VStack(alignment: .leading, spacing: 2) {
                            LocalizedText("enableVerification")
                            LocalizedText("verifyChecksumHint").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    
                    if enableVerification {
                        Picker(env.localized("checksumType"), selection: $verificationLevel) {
                            LocalizedText("verifBasic").tag(PostTransferVerificationLevel.basic)
                            LocalizedText("verifMD5").tag(PostTransferVerificationLevel.md5)
                            LocalizedText("verifSHA256").tag(PostTransferVerificationLevel.sha256)
                        }
                        .pickerStyle(.menu)
                        .padding(.leading, 12)
                        .transition(.opacity)
                    }
                }
                .padding(.bottom, 8)
                
                Section(header: LocalizedText("advancedPost").font(.headline).foregroundColor(.primary)) {
                    Toggle(isOn: $preventSleep) { LocalizedText("preventSleep") }
                    Toggle(isOn: $ejectOnFinish) { LocalizedText("ejectFinish") }
                    Toggle(isOn: $openFinderOnFinish) { LocalizedText("finderFinish") }
                    Toggle(isOn: $autoMigrateFallback) { LocalizedText("migrateFallback") }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct LogsView: View {
    @ObservedObject var backupManager: BackupManager
    @EnvironmentObject var env: AppEnvironment
    @State private var selectedLogID: BackupLog.ID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if backupManager.backupHistory.isEmpty {
                LocalizedText("noLogs").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(backupManager.backupHistory, selection: $selectedLogID) {
                    TableColumn(env.localized("timeCol")) { log in
                        Text("\(log.date, style: .date) \(log.date, style: .time)").font(.caption)
                    }
                    TableColumn(env.localized("sourceCol")) { log in
                        Text(log.sourceName).font(.caption)
                    }
                    TableColumn(env.localized("destCol")) { log in
                        Text(log.destinationPath ?? "-").font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn(env.localized("filesCol")) { log in
                        Text("\(log.fileCount) \(env.localized("filesTx"))").font(.caption).foregroundColor(.secondary)
                    }
                    TableColumn(env.localized("sizeCol")) { log in
                        Text(log.dataTransferredStr).font(.caption)
                    }
                    TableColumn(env.localized("durationCol")) { log in
                        Text("\(Int(log.durationSeconds)) \(env.localized("sec"))").font(.caption)
                    }
                    TableColumn(env.localized("statusCol")) { log in
                        let statusColor: Color = log.result.hasPrefix("成功") ? .green : (log.result.contains("无新文件") ? .secondary : .red)
                        Text(log.result).font(.caption).foregroundColor(statusColor)
                    }
                }
                .frame(minHeight: 300)
                .contextMenu(forSelectionType: BackupLog.ID.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first,
                       let log = backupManager.backupHistory.first(where: { $0.id == id }),
                       let dest = log.destinationPath {
                        if FileManager.default.fileExists(atPath: dest) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: dest))
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(action: {
                    let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Logs")
                    let logURL = logDir?.appendingPathComponent("SDBackupApp.log")
                    if let url = logURL, FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.open(url)
                    } else if let dir = logDir {
                        NSWorkspace.shared.open(dir)
                    }
                }) { Label(env.localized("openLogFolder"), systemImage: "doc.text.viewfinder") }
                Spacer()
            }
        }
    }
}

struct OtherSettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var backupManager: BackupManager
    @AppStorage("hideDockIcon") private var hideDockIcon: Bool = true
    @StateObject private var loginManager = LaunchAtLoginManager.shared
    @AppStorage("appLanguage") private var appLanguage: String = "zh-Hans"
    @State private var showingResetAlert = false
    
    var body: some View {
        VStack(spacing: 24) {
            Form {
                Section(header: LocalizedText("otherLook").font(.headline).foregroundColor(.primary)) {
                    Toggle(isOn: $hideDockIcon) { LocalizedText("hideDock") }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { loginManager.isEnabled },
                            set: { _ in loginManager.toggle() }
                        )) { LocalizedText("autoStart") }
                        LocalizedText("autoStartDisabled").font(.caption2).foregroundColor(.secondary)
                    }
                    Picker(selection: $appLanguage, label: LocalizedText("lang")) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text(env.localized("resetTitle")).font(.headline).foregroundColor(.red)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(env.localized("resetWarning")).font(.caption).foregroundColor(.secondary)
                        Button(role: .destructive, action: { showingResetAlert = true }) {
                            HStack { Image(systemName: "trash"); Text(env.localized("resetBtn")) }
                        }
                        .alert(isPresented: $showingResetAlert) {
                            Alert(title: Text(env.localized("resetTitle")), message: Text(env.localized("resetConfirm")), primaryButton: .destructive(Text(env.localized("resetBtn"))) { backupManager.resetAllSettings() }, secondaryButton: .cancel())
                        }
                    }
                }
                Section(header: LocalizedText("about").font(.headline).foregroundColor(.primary).padding(.top, 16)) {
                    HStack { LocalizedText("version").foregroundColor(.secondary); Spacer(); Text(AppEnvironment.appVersion).foregroundColor(.secondary) }
                    HStack { LocalizedText("developerKey").foregroundColor(.secondary); Spacer(); Text("南洋Nayan").foregroundColor(.secondary) }
                }
            }
            .formStyle(.grouped)
        }
    }
}
