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
    @AppStorage("autoStart") private var autoStart: Bool = false
    
    var body: some Scene {
        MenuBarExtra(L10n.translate("appName", lang: env.languageCode), systemImage: backupManager.isWorking ? (backupManager.isWorkingAnimationToggle ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath") : "sdcard") {
            if backupManager.isWorking {
                Text(L10n.translate(backupManager.currentActionTextKey, lang: env.languageCode))
                    .disabled(true)
                
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
                    
                    Menu("• \(card.name)") {
                        Text("\(card.format) | \(L10n.translate("freeCap", lang: env.languageCode)): \(String(format: "%.1f", freeGB))GB / \(String(format: "%.1f", totalGB))GB")
                            .disabled(true)
                        
                        Divider()
                        
                        Button("\(L10n.translate("eject", lang: env.languageCode)) \(card.name)") {
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
        
        Window("首选项", id: "settings") {
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
                    case .other: OtherSettingsView()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // Using empty string as navigationTitle handles dynamic changes better
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
    @AppStorage("allowedFileExtensions") private var allowedFileExtensions: String = "arw, cr2, cr3, jpg, heif, mov, mp4, xml"
    
    @ObservedObject var backupManager: BackupManager
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var refreshToggle = false
    
    var body: some View {
        VStack(spacing: 20) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $autoBackupOnMount) { LocalizedText("autoBackupMount") }
                        .toggleStyle(.switch)
                    
                    if !autoBackupOnMount {
                        Button(action: { backupManager.manualBackupAll() }) {
                            LocalizedText("manualBackupAll")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(backupManager.connectedCards.isEmpty || backupManager.isWorking)
                    }
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
                    Toggle(isOn: $enableFileFilter) { LocalizedText("fileFilters") }
                    if enableFileFilter {
                        let formats = [
                            ("ARW", env.localized("arwDesc")),
                            ("CR3", env.localized("cr3Desc")),
                            ("JPG", env.localized("jpgDesc")),
                            ("HEIF", env.localized("heifDesc")),
                            ("MP4", env.localized("mp4Desc")),
                            ("XML", env.localized("xmlDesc")),
                            ("XMP", env.localized("xmpDesc"))
                        ]
                        
                        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                            ForEach(formats, id: \.0) { fmt in
                                Toggle(isOn: Binding(
                                    get: { self.allowedFileExtensions.uppercased().contains(fmt.0) },
                                    set: { isEnabled in
                                        var exts = self.allowedFileExtensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
                                        if isEnabled {
                                            if !exts.contains(fmt.0) { exts.append(fmt.0) }
                                        } else {
                                            exts.removeAll { $0 == fmt.0 }
                                        }
                                        self.allowedFileExtensions = exts.joined(separator: ", ")
                                    }
                                )) {
                                    VStack(alignment: .leading) {
                                        Text(fmt.0).font(.body)
                                        Text(fmt.1).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.leading, 18)
                    }
                    
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
                                        Text(card.name).fontWeight(.medium)
                                        Text(card.format).font(.caption).padding(.horizontal, 4).padding(.vertical, 2).background(Color.secondary.opacity(0.2)).cornerRadius(4)
                                        Spacer()
                                        Text("\(env.localized("freeCap")): \(String(format: "%.1f", freeGB))GB / \(String(format: "%.1f", totalGB))GB")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // 存储卡容量横条
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
                                }
                                .contextMenu {
                                    if card.isTrusted {
                                        Button(action: { backupManager.toggleTrust(for: card.url) }) {
                                            Text(env.localized("revokeTrust"))
                                            Image(systemName: "xmark.shield")
                                        }
                                    }
                                }
                                
                                Button(action: { backupManager.ejectCard(url: card.url) }) {
                                    LocalizedText("eject")
                                }
                                .disabled(backupManager.isWorking)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: { LocalizedText("cardDetails").font(.headline) }
        }
        .onReceive(timer) { _ in refreshToggle.toggle() }
    }
}

// 支持绘制原生进度条的提取组件
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
                    
                    Text("\(env.localized("freeSpace")) \(spaceInfo.text)")
                        .font(.caption)
                        .foregroundColor(spaceInfo.isWarning ? .red : .secondary)
                    
                    if spaceInfo.isWarning && spaceInfo.text != "" {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption)
                        Text(env.localized("spaceWarn")).font(.caption).foregroundColor(.red)
                    }
                    Spacer()
                }
                
                // 空间百分比条
                if spaceInfo.total > 0 {
                    GeometryReader { geo in
                        let percent = spaceInfo.usedPercent
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 6)
                            Capsule()
                                .fill(spaceInfo.isWarning ? Color.red : Color.blue)
                                .frame(width: geo.size.width * CGFloat(percent), height: 6)
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
        while !FileManager.default.fileExists(atPath: checkPath, isDirectory: &isDir) {
            let parent = URL(fileURLWithPath: checkPath).deletingLastPathComponent().path
            if parent == checkPath { break }
            checkPath = parent
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: checkPath))
    }
}

// 拓展原有的 Free Space 以支持带进度条返回
func getFreeSpacePercentage(forPath path: String) -> (text: String, isWarning: Bool, usedPercent: Double, total: Double, format: String) {
    if path.isEmpty { return ("", false, 0.0, 0.0, "") }
    
    var checkPath = path
    var isDir: ObjCBool = false
    while !FileManager.default.fileExists(atPath: checkPath, isDirectory: &isDir) {
        let parent = URL(fileURLWithPath: checkPath).deletingLastPathComponent().path
        if parent == checkPath { break }
        checkPath = parent
    }
    
    var format = ""
    let url = URL(fileURLWithPath: checkPath)
    if let r = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]) {
        if let fmt = r.volumeLocalizedFormatDescription { format = fmt }
    }
    
    do {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: checkPath)
        if let freeSize = attrs[.systemFreeSize] as? NSNumber, let sysTotal = attrs[.systemSize] as? NSNumber {
            let gigabytes = Double(freeSize.int64Value) / 1_000_000_000.0
            let tGB = Double(sysTotal.int64Value) / 1_000_000_000.0
            let used = tGB - gigabytes
            let perc = tGB > 0 ? (used / tGB) : 0.0
            
            let formatted = String(format: "%.1f GB", gigabytes)
            let isWarning = gigabytes < 10.0 || (1.0 - perc) < 0.1 // 空间少于10G或少于10%变红
            
            return (formatted, isWarning, perc, tGB, format)
        }
    } catch {
        return ("", false, 0.0, 0.0, format)
    }
    return ("", false, 0.0, 0.0, format)
}

struct AdvancedSettingsView: View {
    @AppStorage("verifyChecksum") private var verifyChecksum: Bool = false
    @AppStorage("sortFormats") private var sortFormats: Bool = false
    @AppStorage("directoryTemplate") private var directoryTemplate: String = "{YYYY}-{MM}-{DD}/{MODEL}/{EXT}/"
    @AppStorage("ejectOnFinish") private var ejectOnFinish: Bool = false
    @AppStorage("openFinderOnFinish") private var openFinderOnFinish: Bool = true
    @AppStorage("autoMigrateFallback") private var autoMigrateFallback: Bool = true
    @AppStorage("backupStrategy") private var backupStrategy: Int = 0
    
    @EnvironmentObject var env: AppEnvironment
    
    var body: some View {
        VStack(spacing: 24) {
            Form {
                Section(header: LocalizedText("advancedPerf").font(.headline).foregroundColor(.primary)) {
                    Picker(env.localized("backupStrategyTitle"), selection: $backupStrategy) {
                        Text(env.localized("strategySizeDate")).tag(0)
                        Text(env.localized("strategyIgnore")).tag(1)
                    }
                    .pickerStyle(.menu)
                    
                    Toggle(isOn: $verifyChecksum) {
                        VStack(alignment: .leading) {
                            LocalizedText("verifyChecksum")
                            LocalizedText("verifyChecksumHint").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $sortFormats) {
                        VStack(alignment: .leading) {
                            LocalizedText("sortFormats")
                            LocalizedText("sortFormatsHint").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    
                    if sortFormats {
                        HStack {
                            LocalizedText("dirTemplate")
                            TextField("", text: $directoryTemplate)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.leading, 20)
                        
                        Text("支持变量: {YYYY}, {MM}, {DD}, {MAKE}, {MODEL}, {EXT}").font(.caption2).foregroundColor(.secondary).padding(.leading, 20)
                    }
                }
                
                Section(header: LocalizedText("advancedPost").font(.headline).foregroundColor(.primary).padding(.top, 16)) {
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
                LocalizedText("noLogs")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(backupManager.backupHistory, selection: $selectedLogID) {
                    TableColumn(env.localized("timeCol")) { log in
                        Text("\(log.date, style: .date) \(log.date, style: .time)")
                            .font(.caption)
                    }
                    TableColumn(env.localized("sourceCol")) { log in
                        Text(log.sourceName).font(.caption)
                    }
                    TableColumn(env.localized("destCol")) { log in
                        Text(log.destinationPath ?? "-")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn(env.localized("filesCol")) { log in
                        Text("\(log.fileCount) \(env.localized("filesTx"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    TableColumn(env.localized("sizeCol")) { log in
                        Text(log.dataTransferredStr)
                            .font(.caption)
                    }
                    TableColumn(env.localized("durationCol")) { log in
                        Text("\(Int(log.durationSeconds)) \(env.localized("sec"))")
                            .font(.caption)
                    }
                    TableColumn(env.localized("statusCol")) { log in
                        let statusColor: Color = log.result == "成功" ? .green : (log.result == "无新文件" ? .secondary : .red)
                        Text(log.result)
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                }
                .frame(minHeight: 300)
                .contextMenu(forSelectionType: BackupLog.ID.self) { items in
                    // Context menu empty
                } primaryAction: { items in
                    if let id = items.first, let log = backupManager.backupHistory.first(where: { $0.id == id }), let dest = log.destinationPath {
                        NSWorkspace.shared.open(URL(fileURLWithPath: dest))
                    }
                }
            }
            
            HStack {
                Spacer()
                Button(action: {
                    let logURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Logs/SDBackupApp.log")
                    if FileManager.default.fileExists(atPath: logURL.path) {
                        NSWorkspace.shared.open(logURL)
                    } else {
                        NSWorkspace.shared.open(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Logs"))
                    }
                }) {
                    Label(env.localized("openLogFolder"), systemImage: "doc.text.viewfinder")
                }
                Spacer()
            }
        }
    }
}

struct OtherSettingsView: View {
    @AppStorage("hideDockIcon") private var hideDockIcon: Bool = true
    @AppStorage("autoStart") private var autoStart: Bool = false
    @AppStorage("appLanguage") private var appLanguage: String = "zh-Hans"
    
    @EnvironmentObject var env: AppEnvironment
    
    var body: some View {
        VStack(spacing: 24) {
            Form {
                Section(header: LocalizedText("otherLook").font(.headline).foregroundColor(.primary)) {
                    Toggle(isOn: $hideDockIcon) { LocalizedText("hideDock") }
                    
                    Toggle(isOn: $autoStart) { LocalizedText("autoStart") }
                        .disabled(true) 
                    
                    Picker(selection: $appLanguage, label: LocalizedText("lang")) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    // 当切换时，AppEnvironment @AppStorage 自动更新触发通知
                }
                
                Section(header: LocalizedText("about").font(.headline).foregroundColor(.primary).padding(.top, 16)) {
                    HStack {
                        LocalizedText("version").foregroundColor(.secondary)
                        Spacer()
                        Text("Pro 1.5.2 (Build 7)")
                    }
                    HStack {
                        LocalizedText("developer").foregroundColor(.secondary)
                        Spacer()
                        Text("南洋 (Nanyang)")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
