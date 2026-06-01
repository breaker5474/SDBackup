import Foundation

enum BackupComparisonStrategy: Int, CaseIterable, Identifiable {
    case skipIfExists = 0
    case updateIfModified = 1
    
    var id: Int { self.rawValue }
}

enum PostTransferVerificationLevel: Int, CaseIterable, Identifiable {
    case basic = 0
    case md5 = 1
    case sha256 = 2
    
    var id: Int { self.rawValue }
}

enum FileFilterMode: Int, CaseIterable, Identifiable {
    case include = 0
    case exclude = 1
    
    var id: Int { self.rawValue }
}
