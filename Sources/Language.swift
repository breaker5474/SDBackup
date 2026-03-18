import Foundation
import SwiftUI

class AppEnvironment: ObservableObject {
    @AppStorage("appLanguage") var languageCode: String = "zh-Hans"
    
    func localized(_ key: String) -> String {
        return L10n.translate(key, lang: languageCode)
    }
}

struct LocalizedText: View {
    @EnvironmentObject var env: AppEnvironment
    let key: String
    
    init(_ key: String) {
        self.key = key
    }
    
    var body: some View {
        Text(env.localized(key))
    }
}

// 供那些无法使用 EnvironmentObject 的地方（比如 MenuBarExtra 内的静态文本组装）使用
struct L10n {
    static func translate(_ key: String, lang: String) -> String {
        guard let dict = strings[lang], let val = dict[key] else {
            return key // Fallback
        }
        return val
    }
    
    static let strings: [String: [String: String]] = [
        "zh-Hans": [
            "appName": "SD 备份助手",
            "ready": "准备就绪",
            "working": "🔴 正在处理...",
            "migrating": "🔴 正在迁移...",
            "calculating": "计算待传输文件...",
            "connectedCards": "已挂载存储卡：",
            "noCards": "未检测到外部存储设备。",
            "settingsAction": "首选项...",
            "quit": "退出",
            "eject": "推出",
            "lastBackup": "上次备份：",
            "cancelTransfer": "中断传输 (取消)",
            "eta": "预计剩余时间：",
            "selectSources": "选择要备份的源目录...",
            "ignoreDevice": "忽略此存储设备",
            "ignoreSuccess": "已将设备加入黑名单",
            
            "navBackup": "备份设置",
            "navAdvanced": "高级设置",
            "navLogs": "传输历史",
            "navOther": "其他",
            
            "timeCol": "时间",
            "sourceCol": "源设备",
            "destCol": "目标路径",
            "statusCol": "状态",
            "durationCol": "耗时",
            "sizeCol": "大小",
            "filesCol": "文件数",
            
            "triggerMode": "触发方式",
            "autoBackupMount": "插入存储卡时自动开始备份",
            "manualBackupAll": "立即备份所有已挂载设备",
            
            "targetLocation": "目标位置",
            "targetMain": "主备份路径 (移动硬盘)",
            "enableFallback": "启用临时备份路径 (硬盘未连接时使用)",
            "targetFallback": "本地暂存路径",
            "notSet": "未选择文件夹",
            "select": "选择文件夹",
            "revealFinder": "在访达中打开",
            "spaceWarn": "空间不足 10%！",
            "freeSpace": "可用空间:",
            "openPanelTitle": "选择备份目标文件夹",
            "openPanelPrompt": "设为备份目录",
            
            "cardDetails": "当前存储卡详情",
            "totalCap": "容量",
            "freeCap": "剩余",
            "usedPerc": "已用",
            
            "advancedPerf": "备份性能与自动整理",
            "verifyChecksum": "传输完成后静默校验完整性 (Checksum)",
            "verifyChecksumHint": "强一致性，按字节比对（耗时较长）。",
            "sortFormats": "提取 EXIF 并按自定义结构归档文件",
            "sortFormatsHint": "重命名并组织照片/视频的目录层级结构。",
            "dirTemplate": "目录命名模板",
            
            "advancedPost": "备份完成后动作",
            "ejectFinish": "自动推出 (卸载) 存储卡",
            "finderFinish": "在访达中自动打开目标文件夹",
            "migrateFallback": "主硬盘插入时自动静默迁移暂存数据",
            
            "backupStrategyTitle": "备份比对策略",
            "strategySizeDate": "根据文件大小与修改日期判断更新 (推荐)",
            "strategyIgnore": "完全忽略目标同名文件 (速度极快，防覆盖)",
            
            "trustCard": "已校验为安全设备，允许读写该卡",
            "revokeTrust": "取消授权 (不信任此卡)",
            "untrustedWarn": "新设备！请先勾选授权后才能自动备份，防止数据泄露。",
            "fileFilters": "格式过滤（开启以只同步勾选的类型）：",
            
            "arwDesc": "ARW (索尼RAW图片)",
            "cr3Desc": "CR3 (佳能RAW图片)",
            "jpgDesc": "JPG (常见图片格式)",
            "heifDesc": "HEIF (高效率图片格式)",
            "mp4Desc": "MP4 (常见视频格式)",
            "xmlDesc": "XML (视频配置文件)",
            "xmpDesc": "XMP (图片配置文件)",
            
            "logsTitle": "备份日志",
            "noLogs": "暂无传输记录",
            "filesTx": "个文件",
            "timeCost": "耗时",
            "sec": "秒",
            
            "otherLook": "外观与语言",
            "hideDock": "隐藏 Dock 栏图标 (仅保留系统状态栏)",
            "autoStart": "开机自动启动 (待接入 macOS 服务)",
            "openLogFolder": "打开日志",
            "logMenu": "运行日志",
            "lang": "界面语言",
            
            "about": "关于",
            "version": "版本",
            "developer": "开发者",
            "delete": "删除",
            "noSources": "由系统自动决定备份位置 (DCIM)",
            "addSource": "添加要备份的文件夹...",
            "resetTitle": "重置软件设置",
            "resetWarning": "⚠️ 确定要重置吗？所有授权设备、路径设置、文件过滤以及历史记录都将被清除且无法恢复。",
            "resetBtn": "立即重置 (需重启软件)",
            "resetSuccess": "重置成功，请手动重新启动软件。"
        ],
        "en": [
            "appName": "SD Backup Pro",
            "ready": "Ready",
            "working": "🔴 Processing...",
            "migrating": "🔴 Migrating...",
            "calculating": "Calculating files...",
            "connectedCards": "Mounted External Drives:",
            "noCards": "No external drives detected.",
            "settingsAction": "Settings...",
            "quit": "Quit",
            "eject": "Eject",
            "lastBackup": "Last Backup: ",
            "cancelTransfer": "Cancel Transfer",
            "eta": "Estimated Time Remaining: ",
            "selectSources": "Select Source Folders...",
            "ignoreDevice": "Ignore this device",
            "ignoreSuccess": "Device added to blacklist",
            
            "navBackup": "Backup Settings",
            "navAdvanced": "Advanced",
            "navLogs": "Transfer History",
            "navOther": "Other",
            
            "timeCol": "Time",
            "sourceCol": "Source",
            "destCol": "Destination",
            "statusCol": "Status",
            "durationCol": "Duration",
            "sizeCol": "Size",
            "filesCol": "Files",
            
            "triggerMode": "Trigger Logic",
            "autoBackupMount": "Auto Backup when SD Card Mounts",
            "manualBackupAll": "Backup All Mounted Devices Now",
            
            "targetLocation": "Destinations",
            "targetMain": "Primary Target Path (External Drive)",
            "enableFallback": "Enable Temporary Backup Path",
            "targetFallback": "Temporary Path",
            "notSet": "Not Set",
            "select": "Choose Folder",
            "revealFinder": "Reveal in Finder",
            "spaceWarn": "Less than 10% space remaining!",
            "freeSpace": "Free:",
            "openPanelTitle": "Select Backup Target Folder",
            "openPanelPrompt": "Set as Target",
            
            "cardDetails": "SD Card Details",
            "totalCap": "Total",
            "freeCap": "Free",
            "usedPerc": "Used",
            
            "advancedPerf": "Performance & Sorting",
            "verifyChecksum": "Verify Checksum exactly after finish",
            "verifyChecksumHint": "Byte-to-byte validation. Slower but secure.",
            "sortFormats": "Parse EXIF and Archive into Custom Folders",
            "sortFormatsHint": "Rename and organize files by formats.",
            "dirTemplate": "Directory Template",
            
            "advancedPost": "Post-Backup Actions",
            "ejectFinish": "Auto Eject SD Card on Finish",
            "finderFinish": "Auto Reveal Destination in Finder",
            "migrateFallback": "Auto Migrate Fallback silently on Target Mount",
            
            "backupStrategyTitle": "Conflict Strategy",
            "strategySizeDate": "Compare size & time (Recommended)",
            "strategyIgnore": "Skip existing cleanly (Fastest)",
            
            "trustCard": "Trust this security source and allow backup",
            "revokeTrust": "Revoke Trust",
            "untrustedWarn": "Unknown device. Please authorize before backup to prevent leaks.",
            "fileFilters": "File Format Filter (checked extensions will be transferred):",
            
            "arwDesc": "ARW (Sony RAW)",
            "cr3Desc": "CR3 (Canon RAW)",
            "jpgDesc": "JPG (Standard Image)",
            "heifDesc": "HEIF (High Efficiency Image)",
            "mp4Desc": "MP4 (Standard Video)",
            "xmlDesc": "XML (Video Metadata)",
            "xmpDesc": "XMP (Image Metadata)",
            
            "logsTitle": "Backup Logs",
            "noLogs": "No Logs Available",
            "filesTx": "files",
            "timeCost": "Duration",
            "sec": "s",
            
            "otherLook": "Appearance & Language",
            "hideDock": "Hide Dock Icon (Status Bar Only)",
            "autoStart": "Launch at System Login (Pending)",
            "openLogFolder": "Open Logs",
            "logMenu": "Runtime Logs",
            "lang": "Language",
            
            "about": "About",
            "version": "Version",
            "developer": "Developer",
            "delete": "Delete",
            "noSources": "Automatic (Default Camera Folders)",
            "addSource": "Add Source Folder...",
            "resetTitle": "Reset App Settings",
            "resetWarning": "⚠️ Are you sure? All trust history, paths, and logs will be permanently deleted.",
            "resetBtn": "Reset Now (Restart Required)",
            "resetSuccess": "Reset complete. Please restart the app."
        ]
    ]
}
