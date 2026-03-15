import Foundation

// 辅助函数，用于获取路径的剩余空间
func getFreeSpace(forPath path: String) -> (text: String, isWarning: Bool) {
    if path.isEmpty { return ("路径未配置", false) }
    
    var checkPath = path
    var isDir: ObjCBool = false
    while !FileManager.default.fileExists(atPath: checkPath, isDirectory: &isDir) {
        let parent = URL(fileURLWithPath: checkPath).deletingLastPathComponent().path
        if parent == checkPath { break }
        checkPath = parent
    }
    
    do {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: checkPath)
        if let freeSize = attrs[.systemFreeSize] as? NSNumber {
            let gigabytes = Double(freeSize.int64Value) / 1_000_000_000.0
            let formatted = String(format: "%.1f GB", gigabytes)
            let isWarning = gigabytes < 10.0
            return ("可用: \(formatted)", isWarning)
        }
    } catch {
        return ("无法读取空间信息", true)
    }
    return ("未知空间", false)
}
