import Foundation

/// Resolve the real home directory (bypasses sandbox container redirection).
enum HomeDirectory {
    static let path: String = {
        if let pw = getpwuid(getuid()) {
            return String(cString: pw.pointee.pw_dir)
        }
        return NSHomeDirectory()
    }()
}
