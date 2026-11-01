import Foundation
import CoreGraphics
import Darwin

enum ScreenLocker {
    /// Locks the screen through the login framework (undocumented, but used by the system lock item).
    static func lock() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias LockFn = @convention(c) () -> Int32
        return unsafeBitCast(sym, to: LockFn.self)() == 0
    }

    static var isLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
