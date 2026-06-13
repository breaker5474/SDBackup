import Foundation
import SwiftUI

class AppEnvironment: ObservableObject {
    @AppStorage("appLanguage") var languageCode: String = "zh-Hans"
    static let appVersion = "1.0.0"
    
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
            "working": "正在备份...",
            "migrating": "正在迁移...",
            "calculating": "计算待传输文件...",
            "connectedCards": "已挂载存储卡：",
            "noCards": "未检测到外部存储设备。",
            "settingsAction": "设置...",
            "settingsTitle": "设置",
            "cancel": "取消",
            "quit": "退出",
            "eject": "推出",
            "lastBackup": "上次备份：",
            "cancelTransfer": "取消备份",
            "eta": "剩余：",
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
            
            "triggerMode": "备份方式",
            "autoBackupMount": "插入存储卡时自动开始备份",
            "manualBackupAll": "立即备份所有已挂载设备",
            "backupCardNow": "立即备份此卡",
            "renameCard": "重命名",
            "renameCardTitle": "重命名存储卡",
            "renameCardPlaceholder": "输入新名称",
            
            "targetLocation": "目标位置",
            "targetMain": "主备份路径 (移动硬盘)",
            "enableFallback": "启用临时备份路径",
            "targetFallback": "临时备份路径",
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
            
            "advancedPerf": "备份策略",
            "verifyChecksumHint": "校验文件是否完整无损，异常时推送通知。",
            "advancedPost": "备份完成后动作",
            "ejectFinish": "自动推出存储卡",
            "finderFinish": "在访达中打开目标文件夹",
            "migrateFallback": "主硬盘连接时自动迁移暂存数据",
            
            "backupStrategyTitle": "备份比对策略",
            "strategySizeDate": "根据文件大小与修改日期判断更新 (推荐)",
            "strategyIgnore": "跳过已存在的文件",
            
            "trustCard": "信任此卡，允许自动备份",
            "revokeTrust": "取消授权 (不信任此卡)",
            "untrustedWarn": "新设备，请先授权后再启用自动备份。",
            "fileFilters": "格式过滤",
            "fileFilterMode": "过滤模式",
            "filterInclude": "仅备份以下类型",
            "filterExclude": "不备份以下类型",
            "filterHint": "输入扩展名，用逗号分隔，如 .xml, .arw",
            "checksumType": "校验算法",
            "verifBasic": "基础校验 (核对大小与时间)",
            "verifMD5": "MD5 完整校验 (计算文件哈希)",
            "verifSHA256": "SHA256 高强度校验 (大文件较多时较慢)",
            "enableVerification": "传输完成后自动校验文件完整性",
            "enableFileFilter": "开启格式过滤策略",
            "preventSleep": "备份时阻止系统休眠",

            
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
            "autoStart": "登录时自动启动程序",
            "autoStartDisabled": "开启后，App 将在您登录系统时自动运行",
            "openLogFolder": "打开日志",
            "logMenu": "运行日志",
            "lang": "界面语言",
            
            "about": "关于",
            "version": "版本",
            "developerKey": "开发者",
            "developer": "南洋Nayan",
            "delete": "删除",
            "noSources": "默认 (DCIM 等相机目录)",
            "addSource": "添加要备份的文件夹...",
            "sourceSelectionHint": "仅备份以下指定目录 (留空则全盘备份)：",
            "resetTitle": "重置软件设置",
            "resetWarning": "⚠️ 确定要重设吗？所有授权设备、路径设置、文件过滤以及历史记录都将被清除且无法恢复。",
            "resetBtn": "恢复默认设置",
            "resetConfirm": "此操作不可撤销，确定继续？",
            "resetSuccess": "重置成功，请手动重新启动软件。",
            
            "catPhoto": "照片",
            "catVideo": "视频",
            "catMetadata": "配置文件",
            "catOther": "其他",
            "backupEstimate": "即将备份 {files} 个文件 (约 {size})，预计 {seconds} 秒",
            "cardHealthWarning": "⚠️ 存储卡 {name} 已连续出现 {count} 次传输异常，建议更换该卡",
            "exportLogs": "导出日志",
            "incompleteBackupDetected": "检测到未完成的备份任务，建议重新插入存储卡继续备份",
            "updateAvailable": "发现新版本: {version}"
        ],
        "en": [
            "appName": "SD Backup Pro",
            "ready": "Ready",
            "working": "Processing...",
            "migrating": "Migrating...",
            "calculating": "Calculating files...",
            "connectedCards": "Mounted External Drives:",
            "noCards": "No external drives detected.",
            "settingsAction": "Settings...",
            "settingsTitle": "Settings",
            "cancel": "Cancel",
            "quit": "Quit",
            "eject": "Eject",
            "lastBackup": "Last Backup: ",
            "cancelTransfer": "Cancel Backup Task",
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
            
            "triggerMode": "Backup Mode",
            "autoBackupMount": "Auto Backup when SD Card Mounts",
            "manualBackupAll": "Backup All Mounted Devices Now",
            "backupCardNow": "Backup This Card Now",
            "renameCard": "Rename",
            "renameCardTitle": "Rename Card",
            "renameCardPlaceholder": "Enter new name",
            
            "targetLocation": "Destinations",
            "targetMain": "Primary Target Path (External Drive)",
            "enableFallback": "Enable Temporary Path",
            "targetFallback": "Temporary Backup Path",
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
            
            "advancedPerf": "Performance",
            "verifyChecksumHint": "Byte-to-byte validation. Notifies if corruption detected.",
            "advancedPost": "Post-Backup Actions",
            "ejectFinish": "Auto Eject SD Card",
            "finderFinish": "Reveal Destination in Finder",
            "migrateFallback": "Auto Migrate Fallback on Target Connect",
            
            "backupStrategyTitle": "Conflict Strategy",
            "strategySizeDate": "Compare size & time (Recommended)",
            "strategyIgnore": "Skip existing files",
            
            "trustCard": "Trust this card for auto backup",
            "revokeTrust": "Revoke Trust",
            "untrustedWarn": "New device — authorize before enabling auto backup.",
            "fileFilters": "Format Filtering",
            "fileFilterMode": "Filter Mode",
            "filterInclude": "Include only",
            "filterExclude": "Exclude these",
            "filterHint": "Enter extensions, e.g. .xml, .arw",
            "checksumType": "Verification Algorithm",
            "verifBasic": "Basic (Check size & time)",
            "verifMD5": "MD5 Full (Hash verification)",
            "verifSHA256": "SHA256 High-strength (Slow on large files)",
            "enableVerification": "Verify file integrity after transfer",
            "enableFileFilter": "Enable file format filtering",
            "preventSleep": "Prevent system sleep during backup",

            
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
            "autoStart": "Launch at System Login",
            "autoStartDisabled": "App will automatically run when you log in",
            "openLogFolder": "Open Logs",
            "logMenu": "Runtime Logs",
            "lang": "Language",
            
            "about": "About",
            "version": "Version",
            "developerKey": "Developer",
            "developer": "Nayan",
            "delete": "Delete",
            "noSources": "Automatic (Default Camera Folders)",
            "addSource": "Add Source Folder...",
            "sourceSelectionHint": "Only backup specified folders (leave empty for full backup):",
            "resetTitle": "Reset App Settings",
            "resetWarning": "⚠️ Are you sure? All trust history, paths, and logs will be permanently deleted.",
            "resetBtn": "Restore Default Settings",
            "resetConfirm": "This cannot be undone. Continue?",
            "resetSuccess": "Reset complete. Please restart the app.",
            
            "catPhoto": "Photos",
            "catVideo": "Videos",
            "catMetadata": "Metadata",
            "catOther": "Other",
            "backupEstimate": "Backing up {files} files (~{size}), est. {seconds}s",
            "cardHealthWarning": "⚠️ Card {name} has had {count} consecutive transfer errors. Consider replacing it.",
            "exportLogs": "Export Logs",
            "incompleteBackupDetected": "Incomplete backup detected. Re-insert the SD card to resume.",
            "updateAvailable": "Update available: {version}"
        ]
    ]
}
